import Foundation
import SimmerShared

/// Runs a command with a timeout. Never call on the engine queue for slow tools.
enum Shell {
    struct Result { var status: Int32; var out: String; var err: String; var timedOut: Bool }

    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch {
            return Result(status: -1, out: "", err: "cannot run \(path): \(error.localizedDescription)", timedOut: false)
        }
        // Drain pipes concurrently so a chatty child can not block on a full pipe.
        let outBox = DataBox(), errBox = DataBox()
        let group = DispatchGroup()
        DispatchQueue.global(qos: .utility).async(group: group) { outBox.set(out.fileHandleForReading.readDataToEndOfFile()) }
        DispatchQueue.global(qos: .utility).async(group: group) { errBox.set(err.fileHandleForReading.readDataToEndOfFile()) }
        var timedOut = false
        if done.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            p.terminate()
            _ = done.wait(timeout: .now() + 2)
        }
        _ = group.wait(timeout: .now() + 2)
        return Result(status: timedOut ? -1 : p.terminationStatus,
                      out: String(decoding: outBox.get(), as: UTF8.self),
                      err: String(decoding: errBox.get(), as: UTF8.self), timedOut: timedOut)
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
}

/// Parses `pmset -g custom` and runs pmset power-mode writes, all off the engine queue.
final class PowerModeMonitor: @unchecked Sendable {
    static let pmset = "/usr/bin/pmset"

    private let lock = NSLock()
    private var current = PowerModeStatus()
    private var lastRefresh = Date.distantPast
    private var refreshing = false
    private var highPowerCapability: Bool?       // from `pmset -g cap`, probed once
    private let queue = DispatchQueue(label: "com.umarwaseem.simmer.pmset", qos: .utility)
    private let maxAge: TimeInterval = 30

    /// Called on the pmset queue when the parsed status changes.
    var onChange: ((PowerModeStatus) -> Void)?

    var status: PowerModeStatus { lock.lock(); defer { lock.unlock() }; return current }

    /// Starts a background refresh when the cached value is older than 30 s.
    func refreshIfStale(now: Date = Date()) {
        lock.lock()
        let stale = now.timeIntervalSince(lastRefresh) >= maxAge && !refreshing
        if stale { refreshing = true }
        lock.unlock()
        if stale { queue.async { self.refreshBlocking() } }
    }

    /// Forces a refresh (after a power-mode command).
    func refreshSoon() {
        lock.lock(); refreshing = true; lock.unlock()
        queue.async { self.refreshBlocking() }
    }

    /// Blocking refresh. Use only off the engine queue or in one-shot CLI modes.
    func refreshBlocking() {
        if highPowerCapabilityProbe() == nil {
            let cap = Shell.run(Self.pmset, ["-g", "cap"], timeout: 5)
            let caps = cap.status == 0 ? cap.out : nil
            lock.lock()
            highPowerCapability = caps.map { $0.contains("highpowermode") }
            lock.unlock()
        }
        let r = Shell.run(Self.pmset, ["-g", "custom"], timeout: 5)
        lock.lock()
        refreshing = false
        lastRefresh = Date()
        guard r.status == 0 else {
            lock.unlock()
            log.error("pmset -g custom failed: \(r.err, privacy: .public)")
            return
        }
        let parsed = Self.parse(r.out, highPowerCapability: highPowerCapability)
        let changed = parsed != current
        current = parsed
        lock.unlock()
        if changed { onChange?(parsed) }
    }

    private func highPowerCapabilityProbe() -> Bool? { lock.lock(); defer { lock.unlock() }; return highPowerCapability }

    /// Parses the "Battery Power:" and "AC Power:" sections of `pmset -g custom`.
    /// Newer macOS reports Low Power Mode as `powermode 1` and has no `lowpowermode` key.
    static func parse(_ text: String, highPowerCapability: Bool? = nil) -> PowerModeStatus {
        var sections: [String: [String: String]] = [:]
        var section: String?
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":") && !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                section = String(trimmed.dropLast())
                continue
            }
            guard let s = section else { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }
            let key = parts.dropLast().joined(separator: " ").lowercased()
            sections[s, default: [:]][key] = String(parts.last!)
        }
        let batt = sections["Battery Power"] ?? [:]
        let ac = sections["AC Power"] ?? [:]
        var st = PowerModeStatus()
        st.lowPowerBattery = batt["lowpowermode"] == "1" || batt["powermode"] == "1"
        st.lowPowerCharger = ac["lowpowermode"] == "1" || ac["powermode"] == "1"
        st.highPowerBattery = batt["powermode"] == "2"
        st.highPowerCharger = ac["powermode"] == "2"
        let hasKey = batt["powermode"] != nil || ac["powermode"] != nil
        // `powermode` also exists on Macs without High Power Mode; `pmset -g cap` disambiguates when available.
        st.highPowerSupported = hasKey && (highPowerCapability ?? true)
        return st
    }

    static func scopeFlag(_ s: PowerModeScope) -> String {
        switch s { case .all: return "-a"; case .battery: return "-b"; case .charger: return "-c" }
    }

    /// Runs a pmset write on the pmset queue, then refreshes. `done` gets nil or an error message.
    func set(_ args: [String], dryRun: Bool, done: @escaping (String?) -> Void) {
        queue.async {
            if dryRun {
                log.info("[dry-run] would run pmset \(args.joined(separator: " "), privacy: .public)")
                done(nil); return
            }
            let r = Shell.run(Self.pmset, args, timeout: 10)
            if r.status == 0 {
                log.info("pmset \(args.joined(separator: " "), privacy: .public) ok")
                self.lock.lock(); self.refreshing = true; self.lock.unlock()
                self.refreshBlocking()
                done(nil)
            } else {
                let msg = r.timedOut ? "pmset timed out" : "pmset failed: \(r.err.trimmingCharacters(in: .whitespacesAndNewlines))"
                log.error("pmset \(args.joined(separator: " "), privacy: .public): \(msg, privacy: .public)")
                done(msg)
            }
        }
    }
}

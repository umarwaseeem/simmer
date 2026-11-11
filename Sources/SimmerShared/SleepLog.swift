import Foundation
import IOKit.pwr_mgt

// MARK: - pmset -g log parser

extension SleepLogParser {
    /// "2026-11-11 16:11:02 +0500" — the first 25 characters of every pmset log event line.
    static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()

    struct Event: Equatable {
        enum Kind: Equatable { case sleep, darkWake, wake }
        var time: Date
        var kind: Kind
        var message: String
    }

    /// Only "Sleep", "DarkWake" and "Wake" event lines (not "Wake Requests", "WakeDetails", "WakeTime").
    /// Dates are parsed only for those lines; the log has ~50k lines and most are assertions.
    static func events(_ log: String) -> [Event] {
        var out: [Event] = []
        log.enumerateLines { line, _ in
            // Cheap checks on UTF-8 first: ~50k lines, most of them assertions.
            let u = line.utf8
            guard u.count > 27, let tabU = u.firstIndex(of: 9), u.distance(from: u.startIndex, to: tabU) > 26 else { return }
            let tab = tabU
            let head = line[line.startIndex..<tab]
            let tsEnd = head.index(head.startIndex, offsetBy: 25)
            let domain = head[tsEnd...].trimmingCharacters(in: .whitespaces)
            let kind: Event.Kind
            switch domain {
            case "Sleep": kind = .sleep
            case "DarkWake": kind = .darkWake
            case "Wake": kind = .wake
            default: return
            }
            guard let t = timestampFormatter.date(from: String(head[..<tsEnd])) else { return }
            out.append(Event(time: t, kind: kind, message: String(line[line.index(after: tab)...])))
        }
        return out
    }

    static func charge(_ msg: String) -> Int? {
        guard let r = msg.range(of: #"Charge:\s*(\d{1,3})%"#, options: .regularExpression) else { return nil }
        return Int(msg[r].filter(\.isNumber))
    }

    static func onBattery(_ msg: String) -> Bool? {
        guard let r = msg.range(of: #"Using (Batt|BATT|AC)\b"#, options: .regularExpression) else { return nil }
        return !msg[r].hasSuffix("AC")
    }

    static func durationSeconds(_ msg: String) -> Double? {
        guard let r = msg.range(of: #"\)\s+(\d+) secs"#, options: .regularExpression) else { return nil }
        return Double(msg[r].filter(\.isNumber))
    }

    /// The quoted reason of a Sleep line, without a trailing " pid=NNN".
    static func sleepReason(_ msg: String) -> String {
        guard let a = msg.range(of: "due to '"), let b = msg[a.upperBound...].firstIndex(of: "'") else { return "Sleep" }
        var r = String(msg[a.upperBound..<b])
        if let p = r.range(of: #"\s+pid=\d+$"#, options: .regularExpression) { r.removeSubrange(p) }
        return r
    }

    /// Short wake reason: an "rtc/..." token, else the text after the last "/" (e.g. "HID Activity",
    /// "Notification"), else the first driver token without its hex code (e.g. "smc.sysState.Wake"),
    /// with a hint for network and USB-C plug wakes.
    static func wakeReason(_ msg: String) -> String {
        guard let a = msg.range(of: " due to ") else { return "Unknown" }
        var body = String(msg[a.upperBound...])
        if let u = body.range(of: " Using ") { body = String(body[..<u.lowerBound]) }
        body = body.trimmingCharacters(in: .whitespaces)
        let tokens = body.split(separator: " ").map(String.init)
        if let rtc = tokens.first(where: { $0.hasPrefix("rtc/") }) { return rtc }
        if let slash = body.lastIndex(of: "/") {
            let after = body[body.index(after: slash)...].trimmingCharacters(in: .whitespaces)
            if !after.isEmpty { return after }
        }
        var first = tokens.first ?? "Unknown"
        if let p = first.range(of: #"\(0x[0-9a-fA-F]+\)"#, options: .regularExpression) { first.removeSubrange(p) }
        if first.hasSuffix("/") { first.removeLast() }
        if tokens.contains(where: { $0 == "wifibt" || $0.hasPrefix("ARPT") || $0 == "en0" }) { return first + " (network)" }
        if tokens.contains(where: { $0.hasPrefix("USB-C_plug") }) { return first + " (USB-C plug)" }
        return first
    }

    /// A sleep that macOS starts by itself right after a brief wake.
    static func isBackToSleep(_ reason: String) -> Bool {
        reason.contains("Back to Sleep") || reason == "Maintenance Sleep"
    }

    /// A full wake caused by the user (keyboard, trackpad, lid, power button).
    static func isUserWake(_ reason: String) -> Bool {
        let r = reason.lowercased()
        return r.contains("hid activity") || r.contains("user") || r.contains("lid") || r.contains("power button")
    }

    /// See `parse(_:)`. `minimumSeconds` drops sessions shorter than this (0 keeps all).
    public static func parse(_ log: String, minimumSeconds: Double) -> [SleepSession] {
        struct PendingEnd { var time: Date; var pct: Int?; var reason: String; var duration: Double? }
        var sessions: [SleepSession] = []
        var open: SleepSession?
        var pending: PendingEnd?
        let resumeWindow: TimeInterval = 300

        func close(_ s: SleepSession, _ p: PendingEnd?) {
            var s = s
            s.end = p?.time
            s.percentEnd = p?.pct
            sessions.append(s)
        }

        for e in events(log) {
            switch e.kind {
            case .sleep:
                let reason = sleepReason(e.message)
                if var s = open, let p = pending {
                    if isBackToSleep(reason), !isUserWake(p.reason), e.time.timeIntervalSince(p.time) <= resumeWindow {
                        s.wakes.append(WakeEvent(time: p.time, isDarkWake: false, reason: p.reason, durationSeconds: p.duration))
                        open = s; pending = nil
                        continue
                    }
                    close(s, p); open = nil; pending = nil
                }
                if open == nil && e.message.hasPrefix("Entering Sleep state") {
                    open = SleepSession(start: e.time, end: nil, percentStart: charge(e.message), percentEnd: nil,
                                        onBattery: onBattery(e.message) ?? false, reason: reason, wakes: [])
                }
            case .darkWake:
                guard var s = open, pending == nil else { continue }
                s.wakes.append(WakeEvent(time: e.time, isDarkWake: true, reason: wakeReason(e.message),
                                         durationSeconds: durationSeconds(e.message)))
                open = s
            case .wake:
                guard open != nil, pending == nil else { continue }
                pending = PendingEnd(time: e.time, pct: charge(e.message), reason: wakeReason(e.message),
                                     duration: durationSeconds(e.message))
            }
        }
        if let s = open { close(s, pending) }
        return sessions.filter { s in
            guard let end = s.end else { return true }
            return end.timeIntervalSince(s.start) >= minimumSeconds
        }
    }
}

// MARK: - Sleep blockers

extension SleepBlocker {
    /// Assertion types that keep the system or the display awake. `AssertionTrueType` is preferred when
    /// present, so legacy names (NoIdleSleepAssertion) map to the modern ones.
    static let blockingTypes: Set<String> = [
        "PreventUserIdleSystemSleep", "PreventSystemSleep", "PreventUserIdleDisplaySleep",
        "NoIdleSleepAssertion", "NoDisplaySleepAssertion", "DenySystemSleep",
    ]

    static func readCurrent() -> [SleepBlocker] {
        var ref: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&ref) == kIOReturnSuccess, let cf = ref?.takeRetainedValue() else { return [] }
        var byPID: [Int32: [[String: Any]]] = [:]
        for (k, v) in (cf as NSDictionary) {
            guard let pid = (k as? NSNumber)?.int32Value, let arr = v as? [[String: Any]] else { continue }
            byPID[pid] = arr
        }
        return parse(byPID)
    }

    /// Pure: turns the IOPMCopyAssertionsByProcess dictionary into blockers.
    static func parse(_ byPID: [Int32: [[String: Any]]]) -> [SleepBlocker] {
        var out: [SleepBlocker] = []
        for (pid, list) in byPID {
            for a in list {
                let level = (a["AssertLevel"] as? NSNumber)?.intValue ?? 255
                guard level != 0 else { continue }
                let type = (a["AssertType"] as? String) ?? ""
                let trueType = (a["AssertionTrueType"] as? String) ?? type
                guard blockingTypes.contains(trueType) || blockingTypes.contains(type) else { continue }
                let process = (a["Process Name"] as? String) ?? "pid \(pid)"
                let name = (a["AssertName"] as? String) ?? ""
                // powerd holds this one whenever the display is on; it is not a reason the Mac stays awake.
                if process == "powerd" && name.hasPrefix("Powerd - Prevent sleep while display is on") { continue }
                out.append(SleepBlocker(pid: pid, processName: process, assertionType: trueType, name: name,
                                        since: a["AssertStartWhen"] as? Date))
            }
        }
        return out.sorted { ($0.since ?? .distantFuture, $0.id) < ($1.since ?? .distantFuture, $1.id) }
    }
}

// MARK: - Battery sessions

extension BatterySession {
    static func split(_ samples: [HistorySample]) -> [BatterySession] {
        let sorted = samples.sorted { $0.t < $1.t }
        var out: [BatterySession] = []
        var run: [HistorySample] = []

        func flush() {
            defer { run.removeAll() }
            guard run.count >= 2, let first = run.first, let last = run.last, last.t > first.t else { return }
            let draws = run.map { max(0, -$0.batteryW) }
            let avg = draws.reduce(0, +) / Double(draws.count)
            out.append(BatterySession(start: first.t, end: last.t, percentStart: first.pct, percentEnd: last.pct,
                                      averageWatts: (avg * 10).rounded() / 10))
        }

        for s in sorted {
            if s.plugged { flush(); continue }
            if let prev = run.last, s.t.timeIntervalSince(prev.t) > 20 * 60, s.pct >= prev.pct + 2 { flush() }
            run.append(s)
        }
        flush()
        return out.reversed()
    }
}

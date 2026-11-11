import Darwin
import Foundation

// MARK: - Process list (libproc; works as any user, root sees every process)

/// Counters of one process from proc_pid_rusage(RUSAGE_INFO_V6).
public struct ProcessSample: Equatable, Sendable {
    public var pid: Int32
    public var path: String
    public var startAbs: UInt64       // ri_proc_start_abstime: tells a reused pid from the old process
    public var energyNJ: UInt64       // ri_energy_nj (fallback ri_billed_energy), nanojoules since process start
    public var cpuNS: UInt64          // user + system time, nanoseconds
    public var wakeups: UInt64        // package idle + interrupt wakeups
    public init(pid: Int32, path: String, startAbs: UInt64, energyNJ: UInt64, cpuNS: UInt64, wakeups: UInt64) {
        self.pid = pid; self.path = path; self.startAbs = startAbs; self.energyNJ = energyNJ; self.cpuNS = cpuNS; self.wakeups = wakeups
    }
}

public enum ProcessList {
    public struct Entry: Equatable, Sendable { public var pid: Int32; public var path: String }

    public static func pids() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var buf = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = buf.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard got > 0 else { return [] }
        return buf.prefix(Int(got)).filter { $0 > 0 }
    }

    public static func path(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    /// Every process whose executable path is readable.
    public static func all() -> [Entry] {
        pids().compactMap { pid in path(of: pid).map { Entry(pid: pid, path: $0) } }
    }

    static let timebase: (numer: Double, denom: Double) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (Double(tb.numer), Double(max(1, tb.denom)))
    }()

    /// Mach absolute time units → nanoseconds (Apple silicon ticks are 125/3 ns; Intel is 1:1).
    public static func nanoseconds(_ abs: UInt64) -> UInt64 { UInt64(Double(abs) * timebase.numer / timebase.denom) }

    /// rusage counters of every process this user may inspect (root: all). Processes that exit while the
    /// list is read are skipped.
    public static func sampleAll() -> [ProcessSample] {
        var out: [ProcessSample] = []
        out.reserveCapacity(1000)
        var pathBuf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids() {
            var ri = rusage_info_v6()
            let r = withUnsafeMutablePointer(to: &ri) { p in
                p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            guard r == 0 else { continue }
            let n = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
            let path = n > 0 ? String(cString: pathBuf) : "pid \(pid)"
            let energy = ri.ri_energy_nj > 0 ? ri.ri_energy_nj : ri.ri_billed_energy
            out.append(ProcessSample(pid: pid, path: path, startAbs: ri.ri_proc_start_abstime, energyNJ: energy,
                                     cpuNS: nanoseconds(ri.ri_user_time &+ ri.ri_system_time),
                                     wakeups: ri.ri_pkg_idle_wkups &+ ri.ri_interrupt_wkups))
        }
        return out
    }
}

// MARK: - Grouping processes under their app

public struct EnergyGroup: Hashable, Sendable {
    public var id: String
    public var name: String
    public var bundlePath: String?
    public var isApp: Bool
}

/// Maps an executable path to the app it belongs to: the outermost enclosing `.app` bundle (so helpers and
/// XPC services inside an app count for the app), else the process's responsible app (when the system
/// reports one), else the executable name.
public final class EnergyGrouper {
    public typealias BundleInfo = (_ appPath: String) -> (id: String?, name: String?)
    private let bundleInfo: BundleInfo
    private let responsiblePID: (pid_t) -> pid_t?
    private var cache: [String: EnergyGroup] = [:]

    public static let simmerGroup = EnergyGroup(id: Simmer.helperLabel, name: "Simmer helper", bundlePath: nil, isApp: false)

    public init(bundleInfo: @escaping BundleInfo = EnergyGrouper.readBundleInfo,
                responsiblePID: @escaping (pid_t) -> pid_t? = EnergyGrouper.systemResponsiblePID) {
        self.bundleInfo = bundleInfo
        self.responsiblePID = responsiblePID
    }

    /// "/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/Contents/MacOS/Helper" → "/Applications/Google Chrome.app".
    public static func outermostAppBundle(_ path: String) -> String? {
        guard let r = path.range(of: ".app/") else { return path.hasSuffix(".app") ? path : nil }
        return String(path[..<r.lowerBound]) + ".app"
    }

    public func group(path: String, pid: pid_t, pathOfPID: (pid_t) -> String? = ProcessList.path(of:)) -> EnergyGroup {
        if path == Simmer.helperInstallPath || (pid == getpid() && path.hasSuffix("/simmerd")) { return Self.simmerGroup }
        if let app = Self.outermostAppBundle(path) { return appGroup(app) }
        if let rp = responsiblePID(pid), rp != pid, rp > 0, let rpath = pathOfPID(rp), let app = Self.outermostAppBundle(rpath) {
            return appGroup(app)
        }
        let name = (path as NSString).lastPathComponent
        return EnergyGroup(id: path, name: name.isEmpty ? path : name, bundlePath: nil, isApp: false)
    }

    private func appGroup(_ app: String) -> EnergyGroup {
        if let g = cache[app] { return g }
        let info = bundleInfo(app)
        let fallback = ((app as NSString).lastPathComponent as NSString).deletingPathExtension
        let g = EnergyGroup(id: info.id ?? app, name: info.name ?? fallback, bundlePath: app, isApp: true)
        cache[app] = g
        return g
    }

    public static func readBundleInfo(_ app: String) -> (id: String?, name: String?) {
        let plist = app + "/Contents/Info.plist"
        guard let d = FileManager.default.contents(atPath: plist),
              let p = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { return (nil, nil) }
        let raw = (p["CFBundleDisplayName"] as? String) ?? (p["CFBundleName"] as? String)
        let name = raw.map(cleanName)
        return (p["CFBundleIdentifier"] as? String, name?.isEmpty == false ? name : nil)
    }

    /// Removes invisible format characters (some apps put U+200E in their name) and outer spaces.
    public static func cleanName(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.filter { $0.properties.generalCategory != .format })
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `responsibility_get_pid_responsible_for_pid` (libsystem, used by Activity Monitor) is not public API, so it is
    /// looked up at run time; without it, processes outside bundles are grouped by executable name.
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsibleFn: ResponsibleFn? = {
        guard let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()
    public static func systemResponsiblePID(_ pid: pid_t) -> pid_t? {
        guard let f = responsibleFn else { return nil }
        let r = f(pid)
        return r > 0 ? r : nil
    }
}

// MARK: - Deltas, rolling averages, report

/// Turns successive process samples into an EnergyReport. Not thread-safe; use from one queue.
public final class EnergyAccumulator {
    private struct Prev { var startAbs: UInt64; var energyNJ: UInt64; var cpuNS: UInt64; var wakeups: UInt64 }
    private struct Window { var time: Date; var seconds: Double; var joules: [String: Double] }

    public let grouper: EnergyGrouper
    public var maxEntries = 40
    public var hourWindow: TimeInterval = 3600
    private var prev: [Int32: Prev] = [:]
    private var groupCache: [Int32: (startAbs: UInt64, group: EnergyGroup)] = [:]
    private var lastTime: Date?
    private var lastAbs: UInt64 = 0
    private var history: [Window] = []
    private var sinceUnplugJ: [String: Double] = [:]
    private var wasOnBattery = false

    public init(grouper: EnergyGrouper = EnergyGrouper()) { self.grouper = grouper }

    /// Adds one sample set taken at `time` (wall clock) / `abs` (mach_absolute_time). Returns nil for the first call.
    public func ingest(_ samples: [ProcessSample], time: Date, abs: UInt64, onBattery: Bool,
                       pathOfPID: (pid_t) -> String? = ProcessList.path(of:)) -> EnergyReport? {
        defer {
            prev = Dictionary(samples.map { ($0.pid, Prev(startAbs: $0.startAbs, energyNJ: $0.energyNJ, cpuNS: $0.cpuNS, wakeups: $0.wakeups)) },
                              uniquingKeysWith: { a, _ in a })
            lastTime = time; lastAbs = abs
        }
        guard let last = lastTime else { wasOnBattery = onBattery; return nil }
        let seconds = time.timeIntervalSince(last)
        guard seconds > 0.5 else { return nil }

        struct Acc { var group: EnergyGroup; var joules = 0.0; var cpuNS = 0.0; var wakeups = 0.0; var pids = 0 }
        var acc: [String: Acc] = [:]
        var nextGroupCache: [Int32: (startAbs: UInt64, group: EnergyGroup)] = [:]
        defer { groupCache = nextGroupCache }
        for s in samples {
            let g: EnergyGroup
            if let c = groupCache[s.pid], c.startAbs == s.startAbs { g = c.group }
            else { g = grouper.group(path: s.path, pid: s.pid, pathOfPID: pathOfPID) }
            nextGroupCache[s.pid] = (s.startAbs, g)
            var a = acc[g.id] ?? Acc(group: g)
            a.pids += 1
            if let p = prev[s.pid], p.startAbs == s.startAbs {
                a.joules += Double(s.energyNJ &- min(s.energyNJ, p.energyNJ)) / 1e9
                a.cpuNS += Double(s.cpuNS &- min(s.cpuNS, p.cpuNS))
                a.wakeups += Double(s.wakeups &- min(s.wakeups, p.wakeups))
            } else if s.startAbs >= lastAbs {
                // Started during this window: all of its counters belong to the window.
                a.joules += Double(s.energyNJ) / 1e9
                a.cpuNS += Double(s.cpuNS)
                a.wakeups += Double(s.wakeups)
            }
            acc[g.id] = a
        }

        // Rolling hour.
        history.append(Window(time: time, seconds: seconds, joules: acc.mapValues(\.joules)))
        history.removeAll { time.timeIntervalSince($0.time) >= hourWindow }
        let hourSeconds = history.reduce(0) { $0 + $1.seconds }
        var hourJ: [String: Double] = [:]
        for w in history { for (k, v) in w.joules { hourJ[k, default: 0] += v } }

        // Since unplug.
        if onBattery {
            if !wasOnBattery { sinceUnplugJ.removeAll() }
            for (k, a) in acc { sinceUnplugJ[k, default: 0] += a.joules }
        } else {
            sinceUnplugJ.removeAll()
        }
        wasOnBattery = onBattery

        func r3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
        var entries = acc.values.map { a in
            EnergyEntry(id: a.group.id, name: a.group.name, bundlePath: a.group.bundlePath, isApp: a.group.isApp,
                        pidCount: a.pids, watts1m: r3(a.joules / seconds),
                        watts1h: r3(hourSeconds > 0 ? (hourJ[a.group.id] ?? 0) / hourSeconds : 0),
                        cpuPercent1m: r3(a.cpuNS / (seconds * 1e9) * 100),
                        wakeupsPerSec1m: r3(a.wakeups / seconds),
                        energySinceUnplugWh: onBattery ? r3((sinceUnplugJ[a.group.id] ?? 0) / 3600) : nil)
        }
        entries.sort { ($0.watts1m, $0.cpuPercent1m, $0.id) > ($1.watts1m, $1.cpuPercent1m, $1.id) }

        var report = EnergyReport()
        report.generatedAt = time
        report.windowSeconds = (seconds * 10).rounded() / 10
        report.totalWatts1m = r3(acc.values.reduce(0) { $0 + $1.joules } / seconds)
        var top = Array(entries.prefix(maxEntries))
        if !top.contains(where: { $0.id == EnergyGrouper.simmerGroup.id }), let me = entries.first(where: { $0.id == EnergyGrouper.simmerGroup.id }) {
            top.append(me)
        }
        report.entries = top
        report.processCount = samples.count
        return report
    }
}

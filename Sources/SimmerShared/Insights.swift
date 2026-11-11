import Foundation

// CONTRACTS for the insight features. Types are final; function bodies marked "STUB" are
// implemented by the backend work (keep the signatures). UI, widgets and intents code against these.

extension Simmer {
    /// Written by simmerd (root can read every process), world-readable 0644.
    public static let energyPath = "/Library/Application Support/Simmer/energy.json"
}

// MARK: - LED notifications

public enum LEDPattern: String, Codable, CaseIterable, Sendable {
    case blinkGreen, blinkOrange, alternate, heartbeat, chargeLevel   // chargeLevel: one blink per 10%
    public var title: String {
        switch self {
        case .blinkGreen: return "Blink green"
        case .blinkOrange: return "Blink orange"
        case .alternate: return "Green / orange"
        case .heartbeat: return "Heartbeat"
        case .chargeLevel: return "Blink the charge level"
        }
    }
}

// MARK: - Energy use by apps and processes (root sampler in simmerd)

public struct EnergyEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String               // bundle id, or executable path for plain processes
    public var name: String             // app display name or process name
    public var bundlePath: String?      // enclosing .app, for the icon
    public var isApp: Bool
    public var pidCount: Int
    public var watts1m: Double          // average estimated power over the last sample window
    public var watts1h: Double          // rolling average over the last hour
    public var cpuPercent1m: Double     // 100 = one full core
    public var wakeupsPerSec1m: Double
    public var energySinceUnplugWh: Double?   // nil while plugged in
    public init(id: String, name: String, bundlePath: String?, isApp: Bool, pidCount: Int, watts1m: Double, watts1h: Double,
                cpuPercent1m: Double, wakeupsPerSec1m: Double, energySinceUnplugWh: Double?) {
        self.id = id; self.name = name; self.bundlePath = bundlePath; self.isApp = isApp; self.pidCount = pidCount
        self.watts1m = watts1m; self.watts1h = watts1h; self.cpuPercent1m = cpuPercent1m
        self.wakeupsPerSec1m = wakeupsPerSec1m; self.energySinceUnplugWh = energySinceUnplugWh
    }
}

public struct EnergyReport: Codable, Equatable, Sendable {
    public var generatedAt = Date()
    public var windowSeconds = 60.0
    public var totalWatts1m = 0.0           // sum over all processes (CPU/GPU attributable part only)
    public var entries: [EnergyEntry] = []  // top 40 by watts1m, grouped by app
    /// How long the sampler took for this report (ms). Optional so older/newer files still decode.
    public var sampleMillis: Double? = nil
    /// Number of processes sampled.
    public var processCount: Int? = nil
    public init() {}
    public static func load(from path: String = Simmer.energyPath) -> EnergyReport? {
        guard let d = FileManager.default.contents(atPath: path) else { return nil }
        return try? SimmerJSON.decode(EnergyReport.self, d)
    }
}

// MARK: - Sleep drain (parsed from `pmset -g log`, readable by any user)

public struct WakeEvent: Codable, Equatable, Sendable {
    public var time: Date
    public var isDarkWake: Bool
    public var reason: String            // e.g. "smc.sysState.Wake", "rtc/Maintenance", "UserActivity"
    public var durationSeconds: Double?
    public init(time: Date, isDarkWake: Bool, reason: String, durationSeconds: Double?) {
        self.time = time; self.isDarkWake = isDarkWake; self.reason = reason; self.durationSeconds = durationSeconds
    }
}

public struct SleepSession: Codable, Equatable, Identifiable, Sendable {
    public var start: Date
    public var end: Date?                // nil while still asleep (not possible when parsed live, kept for safety)
    public var percentStart: Int?
    public var percentEnd: Int?
    public var onBattery: Bool
    public var reason: String            // sleep reason, e.g. "Clamshell Sleep", "Idle Sleep"
    public var wakes: [WakeEvent]        // DarkWakes / maintenance wakes during this sleep
    public var id: Date { start }
    public var hours: Double { ((end ?? start).timeIntervalSince(start)) / 3600 }
    public var percentLost: Int? { if let a = percentStart, let b = percentEnd { return max(0, a - b) } else { return nil } }
    public var percentPerHour: Double? { if let l = percentLost, hours > 0.05 { return Double(l) / hours } else { return nil } }
    public init(start: Date, end: Date?, percentStart: Int?, percentEnd: Int?, onBattery: Bool, reason: String, wakes: [WakeEvent]) {
        self.start = start; self.end = end; self.percentStart = percentStart; self.percentEnd = percentEnd
        self.onBattery = onBattery; self.reason = reason; self.wakes = wakes
    }
}

public enum SleepLogParser {
    /// Parse `pmset -g log` text into sleep sessions (oldest first). A session starts at a
    /// "Sleep ... Entering Sleep state due to '<reason>' ... Using Batt|AC (Charge:NN%)" line and ends at the
    /// next full "Wake" line (its Charge:NN% is percentEnd). "DarkWake" lines in between are wakes.
    /// A short full wake that macOS ends by itself ("Notification Wake Back to Sleep", e.g. after plugging in
    /// the charger) does not end the session; it is kept as a wake event. Sessions shorter than 60 s are dropped.
    /// Implementation: SleepLog.swift.
    public static func parse(_ log: String) -> [SleepSession] { parse(log, minimumSeconds: 60) }

    /// Runs `/usr/bin/pmset -g log` and parses the result (last `days` days).
    public static func recentSessions(days: Int = 7) -> [SleepSession] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["-g", "log"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return parse(String(decoding: data, as: UTF8.self)).filter { $0.start >= cutoff }
    }
}

/// A process holding a power assertion that blocks sleep ("Why won't my Mac sleep?").
public struct SleepBlocker: Codable, Equatable, Identifiable, Sendable {
    public var pid: Int32
    public var processName: String
    public var assertionType: String     // PreventUserIdleSystemSleep, PreventSystemSleep, PreventUserIdleDisplaySleep...
    public var name: String              // the assertion's own name
    public var since: Date?
    public var id: String { "\(pid)-\(assertionType)-\(name)" }
    public init(pid: Int32, processName: String, assertionType: String, name: String, since: Date?) {
        self.pid = pid; self.processName = processName; self.assertionType = assertionType; self.name = name; self.since = since
    }
    /// Read with IOPMCopyAssertionsByProcess (works as a normal user). Only assertions that keep the Mac or
    /// the display awake are listed; powerd's own "display is on" assertion is left out. Longest-held first.
    public static func current() -> [SleepBlocker] { readCurrent() }
}

// MARK: - Battery sessions (from history.json samples)

public struct BatterySession: Codable, Equatable, Identifiable, Sendable {
    public var start: Date, end: Date
    public var percentStart: Int, percentEnd: Int
    public var id: Date { start }
    public var hours: Double { end.timeIntervalSince(start) / 3600 }
    public var percentPerHour: Double { hours > 0 ? Double(percentStart - percentEnd) / hours : 0 }
    public var averageWatts: Double
    public init(start: Date, end: Date, percentStart: Int, percentEnd: Int, averageWatts: Double) {
        self.start = start; self.end = end; self.percentStart = percentStart; self.percentEnd = percentEnd; self.averageWatts = averageWatts
    }
    /// Split history samples into on-battery sessions (plugged == false runs, gaps > 20 min split
    /// a session only if the charger was connected in between). Newest first.
    /// A gap counts as "charger connected in between" when the level rose by 2 or more points across it.
    public static func sessions(from samples: [HistorySample]) -> [BatterySession] { split(samples) }
}

// MARK: - Battery details beyond BatterySnapshot (IORegistry BatteryData)

public struct BatteryDetails: Codable, Equatable, Sendable {
    public var cellVoltagesMV: [Int] = []
    public var cellImbalanceMV: Int { (cellVoltagesMV.max() ?? 0) - (cellVoltagesMV.min() ?? 0) }
    public var manufactureDate: Date? = nil
    public var serial = ""
    public var chemistryID: Int? = nil
    public var qmaxMAh: [Int] = []
    public var lifetimeMaxTempC: Double? = nil
    public var lifetimeMinTempC: Double? = nil
    public var lifetimeAvgTempC: Double? = nil
    public var totalOperatingHours: Double? = nil
    /// Hours spent at a high state of charge, if decodable from LifetimeData.TimeAtHighSoc.
    public var hoursAtHighCharge: Double? = nil
    public var dailyMinSoc: Int? = nil
    public var dailyMaxSoc: Int? = nil
    public init() {}

    /// Severity of cell imbalance: < 30 mV normal, 30–80 watch, > 80 service soon (rule of thumb).
    public enum CellBalance: String, Codable, Sendable { case good, watch, poor }
    public var cellBalance: CellBalance { cellImbalanceMV < 30 ? .good : (cellImbalanceMV <= 80 ? .watch : .poor) }

    /// Read AppleSmartBattery → BatteryData (CellVoltage, Qmax, ChemID, LifetimeData, DailyMin/MaxSoc,
    /// ManufactureDate). Unknown encodings stay nil — never guess. Implementation and unit notes: BatteryDetails+Read.swift.
    public static func read() -> BatteryDetails { readFromRegistry() }
}

// MARK: - Charger report

public struct ChargerReport: Codable, Equatable, Sendable {
    public enum Rating: String, Codable, Sendable { case none, excellent, good, limited, insufficient }
    public var rating: Rating = .none
    public var headline = ""             // plain words, e.g. "Your 30 W charger can't keep up"
    public var details: [String] = []    // one sentence each
    public var adapterName = ""
    public var negotiatedWatts = 0       // what the adapter offers (AdapterDetails.Watts)
    public var voltageV = 0.0
    public var currentA = 0.0
    public var peakSystemWatts: Double? = nil   // highest Mac power use seen recently (history)
    public var isUSBPD = false
    public init() {}
}

public enum ChargerAnalyzer {
    /// Pure function: compare what the charger offers with what the Mac uses (now and recent peak),
    /// detect a cable/hub limit (e.g. exactly 60 W with a higher-rated adapter name, or 15 W/5 V),
    /// and explain in plain words. Implementation: ChargerAnalyzer.swift.
    public static func report(battery: BatterySnapshot, systemW: Double?, adapterW: Double?, recentPeakSystemW: Double?) -> ChargerReport {
        analyze(battery: battery, systemW: systemW, adapterW: adapterW, recentPeakSystemW: recentPeakSystemW)
    }
}

// MARK: - Conflicts with other charge limiters

public struct Conflict: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case leftoverHelper, runningApp, nativeChargeLimit }
    public var id: String                // stable, e.g. the launchd label
    public var kind: Kind
    public var name: String              // "Charge limiter helper", "macOS Charge Limit"...
    public var detail: String            // plain-language explanation
    public var paths: [String]           // files a fix would remove
    public var fixableBySimmer: Bool     // removeConflict can fix it (helpers); apps/native settings: user action
    public init(id: String, kind: Kind, name: String, detail: String, paths: [String], fixableBySimmer: Bool) {
        self.id = id; self.kind = kind; self.name = name; self.detail = detail; self.paths = paths; self.fixableBySimmer = fixableBySimmer
    }
}

public enum ConflictScanner {
    /// Known helpers of other tools (launchd label → product name). Extend as needed.
    public static let knownHelpers: [String: String] = [
        "com.apphousekitchen.aldente-pro.helper": "Third-party charge limiter",
        "com.apphousekitchen.aldente.helper": "Third-party charge limiter",
        "me.mhaeuser.batterytoolkitd": "Battery Toolkit",
        "software.micropixels.BatFi.Helper": "BatFi",
        "cc.chlc.batt": "batt",
        "com.zackelia.bclm": "bclm (persist)",
    ]
    /// Read-only scan of /Library/LaunchDaemons, /Library/PrivilegedHelperTools, running apps,
    /// and the macOS 26.4+ native charge-limit setting. Never lists Simmer itself. No subprocesses;
    /// works from the app, the CLI and the daemon. Implementation: ConflictScanner.swift.
    public static func scan() -> [Conflict] { scan(environment: .live) }
}

// MARK: - Effective limit (desk mode, smart top-up, cheap windows)

public struct LimitContext: Sendable {
    public var now: Date
    public var pluggedIn: Bool
    public var pluggedSince: Date?
    public var lidClosed: Bool
    public var predictedDeparture: Date?
    public init(now: Date, pluggedIn: Bool, pluggedSince: Date?, lidClosed: Bool, predictedDeparture: Date?) {
        self.now = now; self.pluggedIn = pluggedIn; self.pluggedSince = pluggedSince; self.lidClosed = lidClosed
        self.predictedDeparture = predictedDeparture
    }
}

public enum EffectiveLimit {
    /// Priority: smart top-up (100 within lead time before departure) > desk mode (deskModeLimit, never above
    /// the user limit) > cheap windows (outside a window: min(limit, cheapFloorPercent)) > user limit.
    /// The reason is `.user` whenever the result equals the user limit. Smart top-up and desk mode need the
    /// charger connected; cheap windows also apply on battery so plugging in does not cause a charge burst.
    public static func compute(_ cfg: SimmerConfig, _ ctx: LimitContext) -> (limit: Int, reason: LimitReason) {
        evaluate(cfg, ctx)
    }
}

public enum DeparturePredictor {
    /// From history samples, find unplug events (plugged → unplugged with ≥ 30 min plugged before),
    /// group by weekday, and predict the next departure if the same weekday has ≥ 2 events within 45 min of
    /// each other (use their median time). Return nil when there is no confident pattern.
    /// Looks at today (departures still ahead) and the next 7 days; returns the earliest prediction.
    public static func nextDeparture(samples: [HistorySample], now: Date, calendar: Calendar = .current) -> Date? {
        predict(samples: samples, now: now, calendar: calendar)
    }
}

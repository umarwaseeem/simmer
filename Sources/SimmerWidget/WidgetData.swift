import Foundation
import AppIntents
import WidgetKit
import SimmerShared

/// Data for one widget timeline entry. Built from the world-readable files that simmerd writes
/// (status.json, history.json, energy.json, config.json), with an IORegistry read as the fallback
/// for percent and charging.
struct SimmerEntry: TimelineEntry {
    var date: Date
    /// nil when status.json is missing, unreadable or stale (the helper is not running).
    var status: SimmerStatus?
    var battery: BatterySnapshot
    var history: BatteryHistory?
    var energy: EnergyReport? = nil
    var details: BatteryDetails? = nil
    var config: SimmerConfig? = nil

    /// Which optional files a widget kind needs. Each widget loads only what it shows.
    struct Parts: OptionSet {
        let rawValue: Int
        static let history = Parts(rawValue: 1 << 0)
        static let energy = Parts(rawValue: 1 << 1)
        static let details = Parts(rawValue: 1 << 2)
        static let config = Parts(rawValue: 1 << 3)
    }

    /// status.json older than this means the helper is not running.
    static let staleAfter: TimeInterval = 10 * 60
    /// energy.json older than this is not shown.
    static let energyStaleAfter: TimeInterval = 15 * 60

    var helperRunning: Bool { status != nil }
    var percent: Int { battery.percent }
    var target: Int? { status?.targetPercent }
    /// The user's limit (config.json), else the target from status.json.
    var userLimit: Int? { config?.chargeLimit ?? status?.targetPercent }
    var temperatureC: Double { status?.temperatureC ?? battery.temperatureC }
    var healthPercent: Double { battery.healthPercent }

    /// Battery power in watts: + charging, - discharging.
    var batteryW: Double { battery.batteryPowerW }
    var pluggedIn: Bool { battery.externalConnected }
    var adapterW: Double? {
        guard pluggedIn else { return nil }
        if let w = status?.adapterPowerW { return w }
        return nil
    }
    var systemW: Double? { status?.systemPowerW }

    /// History samples inside [date - seconds, date].
    func samples(last seconds: TimeInterval) -> [HistorySample] {
        guard let h = history else { return [] }
        let cutoff = date.addingTimeInterval(-seconds)
        return h.samples.filter { $0.t >= cutoff && $0.t <= date.addingTimeInterval(60) }
    }

    /// Charge % samples of the last 24 h.
    var daySamples: [HistorySample] { samples(last: 86_400) }

    /// Daily health records, oldest first, at most 60 days.
    var healthDays: [DailyBatteryRecord] { healthDays(last: 60) }

    func healthDays(last days: Int) -> [DailyBatteryRecord] {
        guard let h = history else { return [] }
        return Array(h.daily.filter { $0.healthPercent > 0 }.sorted { $0.day < $1.day }.suffix(days))
    }

    /// Minutes until the battery is empty (on battery) or reaches the charge limit / full (charging). nil when idle.
    var minutesRemaining: Int? {
        let b = battery
        if !b.externalConnected { return b.timeRemainingMin }
        guard b.isCharging || b.amperageA > 0.05 else { return nil }
        let goal = Double(status?.targetPercent ?? 100)
        if goal < 100, b.amperageA > 0.05, b.nominalCapacity > 0 || b.rawMaxCapacity > 0 {
            let capacity = Double(b.nominalCapacity > 0 ? b.nominalCapacity : b.rawMaxCapacity)
            let missing = max(0, goal - Double(b.percent)) / 100 * capacity   // mAh
            guard missing > 0 else { return nil }
            return Int((missing / (b.amperageA * 1000) * 60).rounded())
        }
        return b.timeRemainingMin
    }

    /// Recent energy report, or nil when missing or stale.
    var freshEnergy: EnergyReport? {
        guard let e = energy, date.timeIntervalSince(e.generatedAt) < Self.energyStaleAfter else { return nil }
        return e
    }

    /// Charger verdict. Falls back to plain adapter facts while the analyzer has nothing to say.
    var chargerReport: ChargerReport {
        let peak = samples(last: 86_400).compactMap(\.systemW).max()
        var r = ChargerAnalyzer.report(battery: battery, systemW: systemW, adapterW: adapterW, recentPeakSystemW: peak)
        if r.adapterName.isEmpty { r.adapterName = battery.adapterName }
        if r.negotiatedWatts == 0 { r.negotiatedWatts = battery.adapterWatts }
        if r.voltageV == 0 { r.voltageV = battery.adapterVoltageV }
        if r.currentA == 0 { r.currentA = battery.adapterCurrentA }
        if r.peakSystemWatts == nil { r.peakSystemWatts = peak }
        return r
    }

    // MARK: loading

    static func load(now: Date = Date(), parts: Parts = [.history]) -> SimmerEntry {
        let status = loadStatus(now: now)
        var battery = status?.battery ?? BatterySnapshot.read()
        if status == nil, !battery.present { battery.percent = 0 }
        var e = SimmerEntry(date: now, status: status, battery: battery,
                            history: parts.contains(.history) ? BatteryHistory.load() : nil)
        if parts.contains(.energy) { e.energy = EnergyReport.load() }
        if parts.contains(.details) { e.details = BatteryDetails.read() }
        if parts.contains(.config) { e.config = loadConfig() }
        return e
    }

    static func loadStatus(path: String = Simmer.statusSnapshotPath, now: Date) -> SimmerStatus? {
        guard let d = FileManager.default.contents(atPath: path),
              let s = try? SimmerJSON.decode(SimmerStatus.self, d) else { return nil }
        guard now.timeIntervalSince(s.updatedAt) < staleAfter else { return nil }
        return s
    }

    static func loadConfig(path: String = Simmer.configPath) -> SimmerConfig? {
        guard let d = FileManager.default.contents(atPath: path) else { return nil }
        return try? SimmerJSON.decode(SimmerConfig.self, d)
    }

    // MARK: gallery sample

    /// Gallery preview data, used when the real files are not available.
    static var sample: SimmerEntry {
        let now = Date()
        var s = SimmerStatus()
        s.state = .limitReached
        s.targetPercent = 80
        s.effectiveLimit = 80
        s.chargingInhibited = true
        s.adapterPowerW = 13.1
        s.systemPowerW = 12.4
        s.smcTemperatureC = 29.5
        s.updatedAt = now
        var b = BatterySnapshot()
        b.present = true; b.percent = 80; b.hardwarePercent = 76.4; b.externalConnected = true
        b.voltageV = 12.3; b.amperageA = -0.08
        b.designCapacity = 6249; b.rawMaxCapacity = 5742; b.nominalCapacity = 5900; b.cycleCount = 111
        b.adapterName = "96W USB-C Power Adapter"; b.adapterWatts = 94; b.adapterVoltageV = 20; b.adapterCurrentA = 4.7
        s.battery = b
        var details = BatteryDetails()
        details.cellVoltagesMV = [4012, 4018, 4009]
        var cfg = SimmerConfig()
        cfg.chargeLimit = 80
        return SimmerEntry(date: now, status: s, battery: b, history: sampleHistory(now: now, target: 80),
                           energy: sampleEnergy(now: now), details: details, config: cfg)
    }

    /// 14 days of plausible 5-minute samples plus daily health records.
    static func sampleHistory(now: Date, target: Int) -> BatteryHistory {
        var h = BatteryHistory()
        var t = now.addingTimeInterval(-14 * 86_400)
        var pct = Double(target)
        let cal = Calendar.current
        while t <= now {
            let hour = cal.component(.hour, from: t)
            let minuteOfDay = Double(hour * 60 + cal.component(.minute, from: t))
            var plugged = true, charging = false, sysW = 9.0 + 4 * sin(minuteOfDay / 37)
            switch hour {
            case 1..<7: t = t.addingTimeInterval(300); continue                     // asleep: gap
            case 9..<12: plugged = false; pct -= 0.45; sysW += 3
            case 12..<14: charging = pct < Double(target); pct = min(Double(target), pct + 1.6); sysW += 6
            case 17..<19: plugged = false; pct -= 0.35
            case 19..<21: charging = pct < Double(target); pct = min(Double(target), pct + 1.2)
            default: break
            }
            pct = max(20, pct)
            let temp = 27.5 + (charging ? 4 : 0) + 1.5 * sin(minuteOfDay / 90)
            let batW = charging ? 22.0 : (plugged ? 0 : -sysW)
            h.samples.append(HistorySample(t: t, pct: Int(pct.rounded()), hwPct: pct * 0.95, tempC: (temp * 10).rounded() / 10,
                                           batteryW: batW, systemW: (sysW * 10).rounded() / 10, plugged: plugged, charging: charging))
            t = t.addingTimeInterval(300)
        }
        for i in 0..<30 {
            let d = now.addingTimeInterval(Double(i - 29) * 86_400)
            let health = 93.1 - Double(i) * 0.03 + (i % 4 == 0 ? 0.06 : 0)
            let json = """
            {"day":"\(DailyBatteryRecord.dayFormatter.string(from: d))","healthPercent":\((health * 10).rounded() / 10),\
            "rawMaxCapacity":5742,"designCapacity":6249,"cycleCount":\(90 + i),"avgTempC":29,"maxTempC":33,\
            "minPct":40,"maxPct":80,"samples":200}
            """
            if let r = try? SimmerJSON.decode(DailyBatteryRecord.self, Data(json.utf8)) { h.daily.append(r) }
        }
        return h
    }

    static func sampleEnergy(now: Date) -> EnergyReport {
        var r = EnergyReport()
        r.generatedAt = now
        let rows: [(String, String, String?, Double)] = [
            // Generic processes: the gallery preview shows no app artwork.
            ("/usr/local/bin/node", "node", nil, 4.2),
            ("/opt/homebrew/bin/ffmpeg", "ffmpeg", nil, 3.1),
            ("/usr/bin/python3", "python3", nil, 1.4),
            ("/usr/bin/rsync", "rsync", nil, 0.8),
            ("/usr/libexec/mds", "mds_stores", nil, 0.6),
            ("/usr/sbin/WindowServer", "WindowServer", nil, 0.25),
        ]
        r.entries = rows.map { EnergyEntry(id: $0.0, name: $0.1, bundlePath: $0.2, isApp: $0.2 != nil, pidCount: 1, watts1m: $0.3,
                                           watts1h: $0.3 * 0.9, cpuPercent1m: $0.3 * 6, wakeupsPerSec1m: 20, energySinceUnplugWh: nil) }
        r.totalWatts1m = r.entries.reduce(0) { $0 + $1.watts1m }
        return r
    }
}

/// Entry for a widget with an App Intents configuration.
struct ConfiguredEntry<Config: WidgetConfigurationIntent>: TimelineEntry {
    var data: SimmerEntry
    var config: Config
    var date: Date { data.date }
}

/// Timeline provider for configurable widgets. Refreshes every `refresh` seconds; the app and the
/// control buttons also reload the timelines when the state changes.
struct ConfiguredProvider<Config: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    typealias Entry = ConfiguredEntry<Config>
    typealias Intent = Config
    var parts: SimmerEntry.Parts
    var refresh: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> Entry { Entry(data: .sample, config: Config()) }

    func snapshot(for configuration: Config, in context: Context) async -> Entry {
        let e = SimmerEntry.load(parts: parts)
        return Entry(data: context.isPreview && !e.helperRunning ? .sample : e, config: configuration)
    }

    func timeline(for configuration: Config, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        return Timeline(entries: [Entry(data: SimmerEntry.load(now: now, parts: parts), config: configuration)],
                        policy: .after(now.addingTimeInterval(refresh)))
    }
}

/// Timeline provider for widgets without options.
struct StaticProvider: TimelineProvider {
    var parts: SimmerEntry.Parts
    var refresh: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> SimmerEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (SimmerEntry) -> Void) {
        let e = SimmerEntry.load(parts: parts)
        completion(context.isPreview && !e.helperRunning ? .sample : e)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimmerEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [SimmerEntry.load(now: now, parts: parts)], policy: .after(now.addingTimeInterval(refresh))))
    }
}

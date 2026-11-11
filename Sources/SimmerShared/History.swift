import Foundation

extension Simmer {
    /// World-readable files written by simmerd for the app and the widget (no XPC needed, works in a sandbox).
    public static let historyPath = "/Library/Application Support/Simmer/history.json"
    public static let statusSnapshotPath = "/Library/Application Support/Simmer/status.json"
}

/// One reading every `HistoryRecorder.sampleInterval` (5 min), kept for `sampleRetention` (14 days).
public struct HistorySample: Codable, Equatable, Sendable {
    public var t: Date
    public var pct: Int
    public var hwPct: Double
    public var tempC: Double
    public var batteryW: Double
    public var systemW: Double?
    public var plugged: Bool
    public var charging: Bool
    public init(t: Date, pct: Int, hwPct: Double, tempC: Double, batteryW: Double, systemW: Double?, plugged: Bool, charging: Bool) {
        self.t = t; self.pct = pct; self.hwPct = hwPct; self.tempC = tempC; self.batteryW = batteryW
        self.systemW = systemW; self.plugged = plugged; self.charging = charging
    }
}

/// One summary per calendar day, kept forever (about 40 KB per year).
public struct DailyBatteryRecord: Codable, Equatable, Identifiable, Sendable {
    public var day: String                 // yyyy-MM-dd, local time
    public var healthPercent: Double
    public var rawMaxCapacity: Int
    public var designCapacity: Int
    public var cycleCount: Int
    public var avgTempC: Double
    public var maxTempC: Double
    public var minPct: Int
    public var maxPct: Int
    public var samples: Int
    public var id: String { day }

    public var date: Date { DailyBatteryRecord.dayFormatter.date(from: day) ?? Date.distantPast }

    public static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
}

public struct BatteryHistory: Codable, Equatable, Sendable {
    public var samples: [HistorySample] = []
    public var daily: [DailyBatteryRecord] = []
    public init() {}

    public static func load(from path: String = Simmer.historyPath) -> BatteryHistory? {
        guard let d = FileManager.default.contents(atPath: path) else { return nil }
        return try? SimmerJSON.decode(BatteryHistory.self, d)
    }
}

/// Pure history bookkeeping, unit tested. The daemon owns persistence.
public enum HistoryRecorder {
    public static let sampleInterval: TimeInterval = 300
    public static let sampleRetention: TimeInterval = 14 * 86_400

    /// Adds a sample when the interval has passed, folds it into today's daily record, prunes old samples.
    /// Returns true when the history changed.
    @discardableResult
    public static func record(_ h: inout BatteryHistory, battery b: BatterySnapshot, tempC: Double, systemW: Double?,
                              plugged: Bool, now: Date, force: Bool = false) -> Bool {
        guard b.present else { return false }
        if !force, let last = h.samples.last, now.timeIntervalSince(last.t) < sampleInterval { return false }

        // Whole seconds: the ISO 8601 JSON encoding drops fractions.
        h.samples.append(HistorySample(t: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded()), pct: b.percent, hwPct: (b.hardwarePercent * 10).rounded() / 10,
                                       tempC: (tempC * 10).rounded() / 10, batteryW: (b.batteryPowerW * 10).rounded() / 10,
                                       systemW: systemW.map { ($0 * 10).rounded() / 10 }, plugged: plugged, charging: b.isCharging))
        let cutoff = now.addingTimeInterval(-sampleRetention)
        if let first = h.samples.firstIndex(where: { $0.t >= cutoff }), first > 0 { h.samples.removeFirst(first) }

        let day = DailyBatteryRecord.dayFormatter.string(from: now)
        let health = (b.healthPercent * 10).rounded() / 10
        if let i = h.daily.lastIndex(where: { $0.day == day }) {
            var r = h.daily[i]
            r.avgTempC = ((r.avgTempC * Double(r.samples) + tempC) / Double(r.samples + 1) * 10).rounded() / 10
            r.maxTempC = max(r.maxTempC, (tempC * 10).rounded() / 10)
            r.minPct = min(r.minPct, b.percent); r.maxPct = max(r.maxPct, b.percent)
            r.healthPercent = health; r.rawMaxCapacity = b.rawMaxCapacity; r.designCapacity = b.designCapacity
            r.cycleCount = b.cycleCount; r.samples += 1
            h.daily[i] = r
        } else {
            h.daily.append(DailyBatteryRecord(day: day, healthPercent: health, rawMaxCapacity: b.rawMaxCapacity,
                                              designCapacity: b.designCapacity, cycleCount: b.cycleCount,
                                              avgTempC: (tempC * 10).rounded() / 10, maxTempC: (tempC * 10).rounded() / 10,
                                              minPct: b.percent, maxPct: b.percent, samples: 1))
        }
        return true
    }
}

import Foundation
import SimmerShared

/// Time window for the 5-minute sample charts.
enum HistoryRange: String, CaseIterable, Identifiable {
    case day = "24 h", week = "7 d", twoWeeks = "14 d"
    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .twoWeeks: return 14 * 86_400
        }
    }

    /// Samples are averaged into buckets of this size so that long ranges stay readable.
    var bucket: TimeInterval {
        switch self {
        case .day: return HistoryRecorder.sampleInterval
        case .week: return 1_800
        case .twoWeeks: return 3_600
        }
    }

    var spanName: String {
        switch self {
        case .day: return "24 hours"
        case .week: return "7 days"
        case .twoWeeks: return "14 days"
        }
    }
}

/// One averaged reading on the sample charts. `segment` changes where readings are missing (Mac asleep or off),
/// so that lines break at the gap instead of bridging it.
struct HistoryPoint: Identifiable, Equatable {
    let t: Date
    let pct: Double
    let tempC: Double
    let batteryW: Double
    let segment: Int
    var id: Date { t }
}

/// A period while the charger was connected.
struct PluggedSpan: Identifiable, Equatable {
    let start: Date
    let end: Date
    var id: Date { start }
}

/// Sample-chart data for one range.
struct HistorySeries: Equatable {
    let points: [HistoryPoint]
    let plugged: [PluggedSpan]
    let domain: ClosedRange<Date>
    let rawCount: Int

    /// A gap longer than this between readings starts a new line segment.
    static let gapLimit: TimeInterval = HistoryRecorder.sampleInterval * 3
    /// Shortest time span the sample charts show.
    static let minimumSpan: TimeInterval = 2 * 3_600


    init(samples all: [HistorySample], range: HistoryRange, now: Date) {
        let from = now.addingTimeInterval(-range.seconds)
        let samples = all.filter { $0.t >= from && $0.t <= now.addingTimeInterval(60) }.sorted { $0.t < $1.t }
        rawCount = samples.count
        // Early on, when recording started inside the range, zoom to the recorded part (at least 2 hours).
        if let first = samples.first, first.t > from {
            let start = min(first.t.addingTimeInterval(-HistoryRecorder.sampleInterval * 2), now.addingTimeInterval(-Self.minimumSpan))
            domain = max(from, start)...now
        } else {
            domain = from...now
        }

        // Segments on raw samples.
        var segOf: [Int] = []
        var seg = 0
        for (i, s) in samples.enumerated() {
            if i > 0, s.t.timeIntervalSince(samples[i - 1].t) > Self.gapLimit { seg += 1 }
            segOf.append(seg)
        }

        // Average into buckets within each segment.
        var pts: [HistoryPoint] = []
        var i = 0
        while i < samples.count {
            let key = (samples[i].t.timeIntervalSince1970 / range.bucket).rounded(.down)
            var j = i
            var n = 0.0, t = 0.0, p = 0.0, c = 0.0, w = 0.0
            while j < samples.count, segOf[j] == segOf[i],
                  (samples[j].t.timeIntervalSince1970 / range.bucket).rounded(.down) == key {
                let s = samples[j]
                n += 1; t += s.t.timeIntervalSince1970; p += Double(s.pct); c += s.tempC; w += s.batteryW
                j += 1
            }
            pts.append(HistoryPoint(t: Date(timeIntervalSince1970: t / n), pct: p / n, tempC: c / n, batteryW: w / n, segment: segOf[i]))
            i = j
        }
        points = pts

        // Plugged-in spans on raw samples. Each reading covers the interval after it, up to the next reading.
        var spans: [PluggedSpan] = []
        var start: Date?
        var last: Date?
        for s in samples {
            if s.plugged {
                if let l = last, start != nil, s.t.timeIntervalSince(l) > Self.gapLimit {
                    spans.append(PluggedSpan(start: start!, end: min(now, l.addingTimeInterval(HistoryRecorder.sampleInterval))))
                    start = nil
                }
                if start == nil { start = s.t }
                last = s.t
            } else if let st = start {
                spans.append(PluggedSpan(start: st, end: s.t))
                start = nil
                last = nil
            }
        }
        if let st = start, let l = last {
            spans.append(PluggedSpan(start: st, end: min(now, l.addingTimeInterval(HistoryRecorder.sampleInterval))))
        }
        plugged = spans
    }

    /// The reading closest to `date`, if it is near enough to be meaningful.
    func nearest(to date: Date) -> HistoryPoint? {
        guard let p = points.min(by: { abs($0.t.timeIntervalSince(date)) < abs($1.t.timeIntervalSince(date)) }) else { return nil }
        let tolerance = max(HistoryRecorder.sampleInterval, (domain.upperBound.timeIntervalSince(domain.lowerBound)) / 60)
        return abs(p.t.timeIntervalSince(date)) <= tolerance ? p : nil
    }
}

/// Numbers for the summary tiles.
struct HistorySummary {
    let healthPercent: Double
    let rawMaxCapacity: Int
    let designCapacity: Int
    let cycleCount: Int
    let avgTempC: Double?
    let cyclesLast30Days: Int?
    let healthChange: Double?        // percentage points since the first daily record
    let firstDay: Date?

    init(history: BatteryHistory?, live: BatterySnapshot, now: Date) {
        let daily = (history?.daily ?? []).sorted { $0.day < $1.day }
        if live.present && live.designCapacity > 0 {
            healthPercent = live.healthPercent
            rawMaxCapacity = live.rawMaxCapacity
            designCapacity = live.designCapacity
            cycleCount = live.cycleCount
        } else if let last = daily.last {
            healthPercent = last.healthPercent
            rawMaxCapacity = last.rawMaxCapacity
            designCapacity = last.designCapacity
            cycleCount = last.cycleCount
        } else {
            healthPercent = 0; rawMaxCapacity = 0; designCapacity = 0; cycleCount = 0
        }

        // Average temperature, last 7 days, weighted by sample count.
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let recentDays = daily.filter { $0.date >= Calendar.current.startOfDay(for: weekAgo) && $0.samples > 0 }
        let n = recentDays.reduce(0) { $0 + $1.samples }
        if n > 0 {
            avgTempC = recentDays.reduce(0.0) { $0 + $1.avgTempC * Double($1.samples) } / Double(n)
        } else {
            let recent = (history?.samples ?? []).filter { $0.t >= weekAgo }
            avgTempC = recent.isEmpty ? nil : recent.reduce(0.0) { $0 + $1.tempC } / Double(recent.count)
        }

        let monthAgo = Calendar.current.startOfDay(for: now.addingTimeInterval(-30 * 86_400))
        if let base = daily.first(where: { $0.date >= monthAgo }), daily.count > 1 {
            cyclesLast30Days = max(0, cycleCount - base.cycleCount)
        } else {
            cyclesLast30Days = nil
        }
        if let first = daily.first, daily.count > 1 {
            healthChange = healthPercent - first.healthPercent
            firstDay = first.date
        } else {
            healthChange = nil
            firstDay = daily.first?.date
        }
    }
}

extension Array where Element == DailyBatteryRecord {
    /// The record closest to `date` (by day).
    func nearest(to date: Date) -> DailyBatteryRecord? {
        self.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }
}

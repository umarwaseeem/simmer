import SwiftUI
import WidgetKit
import Charts
import SimmerShared

// MARK: - Battery History widget: one metric over 24 h, 7 d or 14 d.

/// Chart-ready data for one metric and range.
struct HistorySeries {
    struct Point: Identifiable {
        var t: Date
        var v: Double
        var segment: Int
        var id: Date { t }
    }

    var metric: HistoryMetricOption
    var start: Date
    var end: Date
    var rangeTitle: String
    var points: [Point]
    var current: Double?
    var limit: Int?

    var title: String {
        switch metric {
        case .charge: return "Charge"
        case .temperature: return "Temperature"
        case .power: return "Mac Power"
        case .health: return "Health"
        }
    }

    var symbol: String {
        switch metric {
        case .charge: return "battery.75percent"
        case .temperature: return "thermometer.medium"
        case .power: return "bolt.fill"
        case .health: return "heart.fill"
        }
    }

    var color: Color {
        switch metric {
        case .charge: return .green
        case .temperature: return .orange
        case .power: return .blue
        case .health: return .pink
        }
    }

    func format(_ v: Double?) -> String {
        guard let v else { return "–" }
        switch metric {
        case .charge: return "\(Int(v.rounded()))%"
        case .temperature: return String(format: "%.1f°", v)
        case .power: return WFmt.watts(v)
        case .health: return String(format: "%.1f%%", v)
        }
    }

    var values: [Double] { points.map(\.v) }
    var minValue: Double? { values.min() }
    var maxValue: Double? { values.max() }
    var average: Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }

    var yDomain: ClosedRange<Double> {
        let lo = minValue ?? 0, hi = maxValue ?? 1
        switch metric {
        case .charge: return 0...100
        case .temperature: return (floor(lo) - 2)...(ceil(hi) + 2)
        case .power: return 0...max(5, hi * 1.15)
        case .health:
            let pad = max(0.5, (hi - lo) * 0.3)
            return (lo - pad)...(hi + pad)
        }
    }

    /// Bucket size that keeps the chart light (the widget has a small memory budget).
    static func bucket(for range: HistoryRangeOption) -> TimeInterval {
        switch range {
        case .day: return 600
        case .week: return 3600
        case .twoWeeks: return 7200
        }
    }

    static func make(_ e: SimmerEntry, metric: HistoryMetricOption, range: HistoryRangeOption) -> HistorySeries {
        let end = e.date
        if metric == .health {
            // Health changes slowly: one point per day, at least one week.
            let days = range == .twoWeeks ? 14 : 7
            let recs = e.healthDays(last: days)
            let pts = recs.map { Point(t: $0.date, v: $0.healthPercent, segment: 0) }
            let start = Calendar.current.startOfDay(for: end.addingTimeInterval(-Double(days - 1) * 86_400))
            return HistorySeries(metric: metric, start: start, end: end, rangeTitle: "\(days) d", points: pts,
                                 current: e.healthPercent > 0 ? e.healthPercent : recs.last?.healthPercent, limit: nil)
        }

        let start = end.addingTimeInterval(-range.seconds)
        let size = bucket(for: range)
        func value(_ s: HistorySample) -> Double? {
            switch metric {
            case .charge: return Double(s.pct)
            case .temperature: return s.tempC > 0 ? s.tempC : nil
            case .power: return s.systemW ?? abs(s.batteryW)
            case .health: return nil
            }
        }
        // Average the samples per bucket; split the line where the Mac slept.
        var sums: [Int: (Double, Int)] = [:]
        for s in e.samples(last: range.seconds) {
            guard let v = value(s) else { continue }
            let k = Int(s.t.timeIntervalSince(start) / size)
            let cur = sums[k] ?? (0, 0)
            sums[k] = (cur.0 + v, cur.1 + 1)
        }
        var pts: [Point] = []
        var seg = 0
        var lastKey: Int?
        let maxGap = max(2, Int((20 * 60 / size).rounded(.up)) + 1)
        for k in sums.keys.sorted() {
            if let lastKey, k - lastKey > maxGap { seg += 1 }
            let (sum, n) = sums[k]!
            pts.append(Point(t: start.addingTimeInterval((Double(k) + 0.5) * size), v: sum / Double(n), segment: seg))
            lastKey = k
        }
        let current: Double?
        switch metric {
        case .charge: current = Double(e.percent)
        case .temperature: current = e.temperatureC > 0 ? e.temperatureC : nil
        case .power: current = e.systemW ?? pts.last?.v
        case .health: current = nil
        }
        return HistorySeries(metric: metric, start: start, end: end, rangeTitle: range.shortTitle, points: pts,
                             current: current, limit: metric == .charge ? e.userLimit : nil)
    }
}

struct HistoryWidgetView: View {
    var entry: SimmerEntry
    var metric: HistoryMetricOption
    var range: HistoryRangeOption
    var family: WidgetFamily

    var body: some View {
        let series = HistorySeries.make(entry, metric: metric, range: range)
        Group {
            switch family {
            case .systemSmall: small(series)
            case .systemLarge, .systemExtraLarge: large(series)
            default: medium(series)
            }
        }
        .simmerWidgetChrome(tint: series.color)
    }

    private var emptyText: String { entry.helperRunning || entry.history != nil ? "Collecting data" : "Helper not running" }
    private var emptySymbol: String { entry.helperRunning || entry.history != nil ? "clock" : "exclamationmark.triangle" }

    private func headline(_ s: HistorySeries, size: CGFloat) -> some View {
        Text(s.format(s.current))
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func small(_ s: HistorySeries) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetHeader(symbol: s.symbol, title: s.title, tint: s.color)
            HStack(alignment: .firstTextBaseline) {
                headline(s, size: 24)
                Spacer(minLength: 2)
                Text(s.rangeTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if s.points.count >= 2 {
                HistoryChart(series: s, axes: false)
                    .padding(.top, 4)
            } else {
                Placeholder(symbol: emptySymbol, text: emptyText)
                    .padding(.top, 4)
            }
        }
    }

    private func medium(_ s: HistorySeries) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(symbol: s.symbol, title: "\(s.title) · \(s.rangeTitle)", tint: s.color,
                         trailing: s.points.isEmpty ? nil : "min \(s.format(s.minValue)) · max \(s.format(s.maxValue))")
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    headline(s, size: 26)
                    Text(s.metric == .health ? "Today" : "Now")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let a = s.average, s.metric != .charge || s.limit == nil {
                        Text("avg \(s.format(a))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    } else if let l = s.limit {
                        Text("Limit \(l)%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                }
                .frame(width: 72, alignment: .leading)
                if s.points.count >= 2 {
                    HistoryChart(series: s, axes: true)
                } else {
                    Placeholder(symbol: emptySymbol, text: emptyText)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func large(_ s: HistorySeries) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(symbol: s.symbol, title: "\(s.title) · \(s.rangeTitle)", tint: s.color,
                         trailing: s.limit.map { "Limit \($0)%" })
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                headline(s, size: 32)
                Text(s.metric == .health ? "today" : "now")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if s.points.count >= 2 {
                HistoryChart(series: s, axes: true)
                    .frame(maxHeight: .infinity)
            } else {
                Placeholder(symbol: emptySymbol, text: emptyText)
                    .frame(maxHeight: .infinity)
            }
            Tile {
                HStack(spacing: 4) {
                    StatItem(symbol: "arrow.down", value: s.format(s.minValue), label: "Min", tint: s.color)
                    StatItem(symbol: "equal", value: s.format(s.average), label: "Average", tint: s.color)
                    StatItem(symbol: "arrow.up", value: s.format(s.maxValue), label: "Max", tint: s.color)
                }
            }
        }
    }
}

/// Line + area chart for a HistorySeries.
struct HistoryChart: View {
    var series: HistorySeries
    var axes: Bool

    var body: some View {
        let s = series
        let domain = s.yDomain
        Chart {
            ForEach(s.points) { p in
                AreaMark(x: .value("Time", p.t), yStart: .value("Base", domain.lowerBound), yEnd: .value(s.title, p.v),
                         series: .value("Segment", p.segment))
                    .foregroundStyle(LinearGradient(colors: [s.color.opacity(0.28), s.color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.t), y: .value(s.title, p.v), series: .value("Segment", p.segment))
                    .foregroundStyle(s.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let l = s.limit {
                RuleMark(y: .value("Limit", l))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .widgetAccentable()
        .chartXScale(domain: s.start...s.end)
        .chartYScale(domain: domain)
        .chartYAxis {
            if axes {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.secondary.opacity(0.4))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(axisLabel(d)) } }
                        .font(.system(size: 9))
                }
            }
        }
        .chartXAxis {
            if axes {
                if s.end.timeIntervalSince(s.start) <= 86_400 + 60 {
                    AxisMarks(values: hourMarks(start: s.start, end: s.end)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.secondary.opacity(0.25))
                        AxisValueLabel(format: .dateTime.hour(), anchor: .top).font(.system(size: 9))
                    }
                } else {
                    AxisMarks(values: dayMarks(start: s.start, end: s.end)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.secondary.opacity(0.25))
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), anchor: .top).font(.system(size: 9))
                    }
                }
            }
        }
    }

    private func axisLabel(_ d: Double) -> String {
        switch series.metric {
        case .charge: return "\(Int(d))%"
        case .temperature: return "\(Int(d))°"
        case .power: return "\(Int(d)) W"
        case .health: return String(format: "%.1f%%", d)
        }
    }
}

/// Local midnights inside the window (every second one for longer ranges), away from the right edge.
func dayMarks(start: Date, end: Date) -> [Date] {
    let cal = Calendar.current
    var d = cal.startOfDay(for: start)
    if d < start { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
    let step = end.timeIntervalSince(start) > 8 * 86_400 ? 3 : 2
    var out: [Date] = []
    while d < end {
        if end.timeIntervalSince(d) > 12 * 3600, d.timeIntervalSince(start) > 12 * 3600 { out.append(d) }
        d = cal.date(byAdding: .day, value: step, to: d) ?? end
    }
    return out
}

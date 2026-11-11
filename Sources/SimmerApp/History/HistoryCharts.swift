import SwiftUI
import Charts
import SimmerShared

// MARK: - Shared pieces

enum ChartColors {
    static let charge = Color.blue
    static let plugged = Color.green
    static let temperature = Color.red
    static let charging = Color.green
    static let discharging = Color.orange
    static let health = Color.pink
    static let cycles = Color.purple
    static let reference = Color.secondary
}

/// Large value + context line above a chart. Shows the latest reading, or the hovered one.
struct ChartReadout<Legend: View>: View {
    let value: String
    let detail: String
    @ViewBuilder var legend: Legend

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 12) { legend }
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct LegendSwatch: View {
    enum Kind { case box, line, dashed }
    let kind: Kind
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            switch kind {
            case .box:
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            case .line:
                Capsule().fill(color).frame(width: 14, height: 2.5)
            case .dashed:
                Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 14, y: 1)) }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .frame(width: 14, height: 2)
            }
            Text(text)
        }
    }
}

/// Shown in place of a chart when there are too few points to draw.
struct ChartPlaceholder: View {
    let text: String
    var height: CGFloat = 150
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.flattrend.xyaxis").font(.title2).foregroundStyle(.tertiary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: height)
    }
}

enum HistoryAxis {
    enum Style { case minutes, hours, weekdays, days }

    /// Tick spacing and label style for a time span.
    static func layout(span: TimeInterval) -> (Calendar.Component, Int, Style) {
        switch span {
        case ..<(3.5 * 3_600): return (.minute, 30, .minutes)
        case ..<(9 * 3_600): return (.hour, 1, .hours)
        case ..<(26 * 3_600): return (.hour, 4, .hours)
        case ..<(8 * 86_400): return (.day, 1, .weekdays)
        default: return (.day, 2, .days)
        }
    }

    static func ticks(domain: ClosedRange<Date>) -> [Date] {
        let cal = Calendar.current
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        let (component, step, _) = layout(span: span)
        let startMargin = span * 0.03, endMargin = span * 0.07
        var d: Date
        switch component {
        case .minute:
            let start = cal.dateInterval(of: .hour, for: domain.lowerBound)?.start ?? domain.lowerBound
            d = start
        case .hour:
            let start = cal.dateInterval(of: .hour, for: domain.lowerBound)?.start ?? domain.lowerBound
            let h = cal.component(.hour, from: start)
            d = cal.date(byAdding: .hour, value: (step - h % step) % step, to: start) ?? start
        default:
            d = cal.startOfDay(for: domain.lowerBound)
        }
        var out: [Date] = []
        while d <= domain.upperBound.addingTimeInterval(-endMargin) {
            if d >= domain.lowerBound.addingTimeInterval(startMargin) { out.append(d) }
            guard let next = cal.date(byAdding: component, value: step, to: d) else { break }
            d = next
        }
        return out
    }
}

enum ChartFormat {
    static func time(_ d: Date, range: HistoryRange) -> String {
        range == .day ? d.formatted(date: .omitted, time: .shortened)
                      : d.formatted(.dateTime.weekday(.abbreviated).day().hour().minute())
    }
    static func day(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated).year()) }
}

/// Recessive dashed reference line.
let referenceStroke = StrokeStyle(lineWidth: 1, dash: [4, 3])
let lineStroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

extension View {
    /// Time axis for the sample charts. Tick dates are calendar-aligned; ticks too close to an edge are
    /// dropped so that their labels are not clipped.
    func historyXAxis(domain: ClosedRange<Date>) -> some View {
        let ticks = HistoryAxis.ticks(domain: domain)
        let style = HistoryAxis.layout(span: domain.upperBound.timeIntervalSince(domain.lowerBound)).2
        return chartXAxis {
            AxisMarks(values: ticks) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                switch style {
                case .minutes: AxisValueLabel(format: .dateTime.hour().minute())
                case .hours: AxisValueLabel(format: .dateTime.hour())
                case .weekdays: AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                case .days: AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
    }

    func yAxisLabels(_ values: [Double], format: @escaping (Double) -> String) -> some View {
        chartYAxis {
            AxisMarks(position: .leading, values: values) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel { if let d = v.as(Double.self) { Text(format(d)) } }
            }
        }
    }
}

/// Selection marker: a thin vertical rule plus a dot on the line.
@ChartContentBuilder
func selectionMarks(x: Date, y: Double, color: Color, unit: Calendar.Component? = nil) -> some ChartContent {
    if let unit {
        RuleMark(x: .value("Selected", x, unit: unit))
            .foregroundStyle(Color.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1))
        PointMark(x: .value("Selected", x, unit: unit), y: .value("Value", y))
            .foregroundStyle(color).symbolSize(60)
    } else {
        RuleMark(x: .value("Selected", x))
            .foregroundStyle(Color.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1))
        PointMark(x: .value("Selected", x), y: .value("Value", y))
            .foregroundStyle(color).symbolSize(60)
    }
}

private let chartHeight: CGFloat = 160

// MARK: - Charge level

struct ChargeHistoryChart: View {
    let series: HistorySeries
    let range: HistoryRange
    let limit: Int?
    @State private var selected: Date?

    var body: some View {
        let sel = selected.flatMap { series.nearest(to: $0) }
        let shown = sel ?? series.points.last
        VStack(alignment: .leading, spacing: 10) {
            ChartReadout(value: shown.map { "\(Int($0.pct.rounded()))%" } ?? "–",
                         detail: shown.map { sel == nil ? "Latest reading" : ChartFormat.time($0.t, range: range) } ?? "No readings") {
                LegendSwatch(kind: .box, color: ChartColors.plugged.opacity(0.25), text: "Plugged in")
                if limit != nil { LegendSwatch(kind: .dashed, color: ChartColors.reference, text: "Charge limit") }
            }
            if series.points.count < 2 {
                ChartPlaceholder(text: "Not enough readings in the last \(range.spanName) yet.", height: chartHeight)
            } else {
                Chart {
                    ForEach(series.plugged) { s in
                        RectangleMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end),
                                      yStart: .value("Bottom", 0.0), yEnd: .value("Top", 100.0))
                            .foregroundStyle(ChartColors.plugged.opacity(0.12))
                    }
                    ForEach(series.points) { p in
                        AreaMark(x: .value("Time", p.t), yStart: .value("Base", 0.0), yEnd: .value("Charge", p.pct),
                                 series: .value("Segment", "a\(p.segment)"))
                            .foregroundStyle(LinearGradient(colors: [ChartColors.charge.opacity(0.22), ChartColors.charge.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", p.t), y: .value("Charge", p.pct), series: .value("Segment", "l\(p.segment)"))
                            .foregroundStyle(ChartColors.charge)
                            .lineStyle(lineStroke)
                            .interpolationMethod(.monotone)
                    }
                    if let limit {
                        RuleMark(y: .value("Limit", Double(limit)))
                            .foregroundStyle(ChartColors.reference)
                            .lineStyle(referenceStroke)
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                Text("\(limit)%").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            }
                    }
                    if let sel { selectionMarks(x: sel.t, y: sel.pct, color: ChartColors.charge) }
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: series.domain)
                .yAxisLabels([0, 25, 50, 75, 100]) { "\(Int($0))%" }
                .historyXAxis(domain: series.domain)
                .chartXSelection(value: $selected)
                .frame(height: chartHeight)
                .accessibilityLabel("Charge level over the last \(range.spanName)")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Temperature

struct TemperatureHistoryChart: View {
    let series: HistorySeries
    let range: HistoryRange
    @State private var selected: Date?

    static let comfortLimit = 35.0

    var body: some View {
        let sel = selected.flatMap { series.nearest(to: $0) }
        let shown = sel ?? series.points.last
        let temps = series.points.map(\.tempC)
        let lo = min(20, ((temps.min() ?? 25) - 2).rounded(.down))
        let hi = max(40, ((temps.max() ?? 35) + 2).rounded(.up))
        VStack(alignment: .leading, spacing: 10) {
            ChartReadout(value: shown.map { Fmt.temp($0.tempC) } ?? "–",
                         detail: shown.map { sel == nil ? "Latest reading" : ChartFormat.time($0.t, range: range) } ?? "No readings") {
                LegendSwatch(kind: .dashed, color: ChartColors.reference, text: "35 °C")
            }
            if series.points.count < 2 {
                ChartPlaceholder(text: "Not enough readings in the last \(range.spanName) yet.", height: chartHeight)
            } else {
                Chart {
                    RuleMark(y: .value("Comfort", Self.comfortLimit))
                        .foregroundStyle(ChartColors.reference)
                        .lineStyle(referenceStroke)
                    ForEach(series.points) { p in
                        LineMark(x: .value("Time", p.t), y: .value("Temperature", p.tempC), series: .value("Segment", "l\(p.segment)"))
                            .foregroundStyle(ChartColors.temperature)
                            .lineStyle(lineStroke)
                            .interpolationMethod(.monotone)
                    }
                    if let sel { selectionMarks(x: sel.t, y: sel.tempC, color: ChartColors.temperature) }
                }
                .chartYScale(domain: lo...hi)
                .chartXScale(domain: series.domain)
                .yAxisLabels(stride(from: lo, through: hi, by: (hi - lo) > 30 ? 10 : 5).map { $0 }) { "\(Int($0))°" }
                .historyXAxis(domain: series.domain)
                .chartXSelection(value: $selected)
                .frame(height: chartHeight)
                .accessibilityLabel("Battery temperature over the last \(range.spanName)")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Battery power

struct PowerHistoryChart: View {
    let series: HistorySeries
    let range: HistoryRange
    @State private var selected: Date?

    var body: some View {
        let sel = selected.flatMap { series.nearest(to: $0) }
        let shown = sel ?? series.points.last
        let watts = series.points.map(\.batteryW)
        let lo = min(-5, ((watts.min() ?? 0) * 1.15).rounded(.down))
        let hi = max(5, ((watts.max() ?? 0) * 1.15).rounded(.up))
        VStack(alignment: .leading, spacing: 10) {
            ChartReadout(value: shown.map { String(format: "%+.1f W", $0.batteryW) } ?? "–",
                         detail: shown.map { p in
                             let what = abs(p.batteryW) < 0.3 ? "resting" : (p.batteryW > 0 ? "charging" : "discharging")
                             return sel == nil ? "Latest reading, \(what)" : "\(ChartFormat.time(p.t, range: range)), \(what)"
                         } ?? "No readings") {
                LegendSwatch(kind: .box, color: ChartColors.charging, text: "Charging")
                LegendSwatch(kind: .box, color: ChartColors.discharging, text: "Discharging")
            }
            if series.points.count < 2 {
                ChartPlaceholder(text: "Not enough readings in the last \(range.spanName) yet.", height: chartHeight)
            } else {
                Chart {
                    ForEach(series.points) { p in
                        AreaMark(x: .value("Time", p.t), yStart: .value("Zero", 0.0), yEnd: .value("Charging", max(0, p.batteryW)),
                                 series: .value("Series", "c\(p.segment)"))
                            .foregroundStyle(ChartColors.charging.opacity(0.75))
                            .interpolationMethod(.monotone)
                        AreaMark(x: .value("Time", p.t), yStart: .value("Zero", 0.0), yEnd: .value("Discharging", min(0, p.batteryW)),
                                 series: .value("Series", "d\(p.segment)"))
                            .foregroundStyle(ChartColors.discharging.opacity(0.75))
                            .interpolationMethod(.monotone)
                    }
                    RuleMark(y: .value("Zero", 0.0))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    if let sel {
                        selectionMarks(x: sel.t, y: sel.batteryW,
                                       color: sel.batteryW >= 0 ? ChartColors.charging : ChartColors.discharging)
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartXScale(domain: series.domain)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel { if let d = v.as(Double.self) { Text(d == 0 ? "0 W" : String(format: "%+.0f W", d)) } }
                    }
                }
                .historyXAxis(domain: series.domain)
                .chartXSelection(value: $selected)
                .frame(height: chartHeight)
                .accessibilityLabel("Battery power over the last \(range.spanName)")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Long term (daily)

struct LongTermChart: View {
    let daily: [DailyBatteryRecord]
    let metric: LongTermMetric
    @State private var selected: Date?

    static let serviceLevel = 80.0

    private func value(_ r: DailyBatteryRecord) -> Double {
        metric == .health ? r.healthPercent : Double(r.rawMaxCapacity)
    }
    private func format(_ v: Double) -> String {
        metric == .health ? Fmt.percent(v) : "\(Int(v).formatted()) mAh"
    }

    var body: some View {
        let sel = selected.flatMap { daily.nearest(to: $0) }
        let shown = sel ?? daily.last
        let design = Double(daily.last?.designCapacity ?? 0)
        let values = daily.map(value)
        let (lo, hi): (Double, Double) = {
            if metric == .health {
                return (min(Self.serviceLevel - 3, ((values.min() ?? 90) - 2).rounded(.down)),
                        max(100, ((values.max() ?? 100) + 1).rounded(.up)))
            }
            let ref = design > 0 ? design : (values.max() ?? 1000)
            return (((min(values.min() ?? ref, ref * 0.77)) / 100).rounded(.down) * 100,
                    ((max(values.max() ?? ref, ref) * 1.03) / 100).rounded(.up) * 100)
        }()
        VStack(alignment: .leading, spacing: 10) {
            ChartReadout(value: shown.map { format(value($0)) } ?? "–",
                         detail: shown.map { sel == nil ? "Today" : ChartFormat.day($0.date) } ?? "No daily summary yet") {
                if metric == .health {
                    LegendSwatch(kind: .dashed, color: ChartColors.reference, text: "80%: service may be suggested")
                } else if design > 0 {
                    LegendSwatch(kind: .dashed, color: ChartColors.reference, text: "Design capacity")
                }
            }
            if daily.count < 2 {
                ChartPlaceholder(text: daily.isEmpty ? "No daily summary yet." : "One day recorded so far. The trend line appears after the second day.",
                                 height: chartHeight)
            } else {
                Chart {
                    if metric == .health {
                        RuleMark(y: .value("Service", Self.serviceLevel))
                            .foregroundStyle(ChartColors.reference).lineStyle(referenceStroke)
                    } else if design > 0 {
                        RuleMark(y: .value("Design", design))
                            .foregroundStyle(ChartColors.reference).lineStyle(referenceStroke)
                    }
                    ForEach(daily) { r in
                        AreaMark(x: .value("Day", r.date, unit: .day), yStart: .value("Base", lo), yEnd: .value(metric.rawValue, value(r)))
                            .foregroundStyle(LinearGradient(colors: [ChartColors.health.opacity(0.10), ChartColors.health.opacity(0.0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Day", r.date, unit: .day), y: .value(metric.rawValue, value(r)))
                            .foregroundStyle(ChartColors.health)
                            .lineStyle(lineStroke)
                            .interpolationMethod(.monotone)
                        if daily.count <= 31 {
                            PointMark(x: .value("Day", r.date, unit: .day), y: .value(metric.rawValue, value(r)))
                                .foregroundStyle(ChartColors.health).symbolSize(14)
                        }
                    }
                    if let sel { selectionMarks(x: sel.date, y: value(sel), color: ChartColors.health, unit: .day) }
                }
                .chartYScale(domain: lo...hi)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text(metric == .health ? "\(Int(d))%" : "\(Int(d).formatted())") }
                        }
                    }
                }
                .chartXSelection(value: $selected)
                .frame(height: chartHeight)
                .accessibilityLabel(metric == .health ? "Battery health by day" : "Battery capacity by day")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Cycle count

struct CycleHistoryChart: View {
    let daily: [DailyBatteryRecord]
    @State private var selected: Date?

    var body: some View {
        let sel = selected.flatMap { daily.nearest(to: $0) }
        let shown = sel ?? daily.last
        let counts = daily.map { Double($0.cycleCount) }
        let lo = max(0, (counts.min() ?? 0) - 1)
        let hi = max(lo + 4, (counts.max() ?? 0) + 1)
        VStack(alignment: .leading, spacing: 10) {
            ChartReadout(value: shown.map { "\($0.cycleCount) cycles" } ?? "–",
                         detail: shown.map { sel == nil ? "Today" : ChartFormat.day($0.date) } ?? "No daily summary yet") {
                EmptyView()
            }
            if daily.count < 2 {
                ChartPlaceholder(text: daily.isEmpty ? "No daily summary yet." : "One day recorded so far. The trend line appears after the second day.",
                                 height: 120)
            } else {
                Chart {
                    ForEach(daily) { r in
                        AreaMark(x: .value("Day", r.date, unit: .day), yStart: .value("Base", lo), yEnd: .value("Cycles", Double(r.cycleCount)))
                            .foregroundStyle(ChartColors.cycles.opacity(0.12))
                            .interpolationMethod(.stepEnd)
                        LineMark(x: .value("Day", r.date, unit: .day), y: .value("Cycles", Double(r.cycleCount)))
                            .foregroundStyle(ChartColors.cycles)
                            .lineStyle(lineStroke)
                            .interpolationMethod(.stepEnd)
                    }
                    if let sel { selectionMarks(x: sel.date, y: Double(sel.cycleCount), color: ChartColors.cycles, unit: .day) }
                }
                .chartYScale(domain: lo...hi)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))") } }
                    }
                }
                .chartXSelection(value: $selected)
                .frame(height: 120)
                .accessibilityLabel("Cycle count by day")
            }
        }
        .padding(.vertical, 4)
    }
}

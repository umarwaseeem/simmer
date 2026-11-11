import SwiftUI
import WidgetKit
import Charts
import SimmerShared

// MARK: - State presentation

struct StateStyle {
    var title: String
    var symbol: String
    var color: Color
}

extension SimmerEntry {
    var style: StateStyle {
        guard let s = status else {
            return StateStyle(title: "Helper Not Running", symbol: "exclamationmark.triangle.fill", color: .orange)
        }
        switch s.state {
        case .charging: return StateStyle(title: "Charging", symbol: "bolt.fill", color: .green)
        case .limitReached: return StateStyle(title: "Limit Reached", symbol: "pause.fill", color: .teal)
        case .sailing: return StateStyle(title: "Sailing", symbol: "sailboat.fill", color: .teal)
        case .discharging: return StateStyle(title: "Discharging", symbol: "arrow.down", color: .orange)
        case .heatProtection: return StateStyle(title: "Heat Protection", symbol: "thermometer.high", color: .red)
        case .topUp: return StateStyle(title: "Topping Up", symbol: "bolt.fill", color: .green)
        case .calibration: return StateStyle(title: "Calibrating", symbol: "arrow.triangle.2.circlepath", color: .purple)
        case .limiterOff:
            return StateStyle(title: "Limiter Off", symbol: battery.isCharging ? "bolt.fill" : "powerplug.fill", color: .gray)
        case .notPluggedIn:
            return StateStyle(title: "On Battery", symbol: WFmt.batterySymbol(percent), color: percent <= 20 ? .red : .blue)
        case .unsupported: return StateStyle(title: "Unsupported", symbol: "exclamationmark.triangle.fill", color: .gray)
        }
    }

    /// Second line under the state title.
    var subtitle: String { subtitle(BatteryOptions()) }

    func subtitle(_ o: BatteryOptions) -> String {
        guard let s = status else { return "Open Simmer to fix" }
        if o.showTimeRemaining, let m = minutesRemaining, m > 0 {
            switch s.state {
            case .notPluggedIn: return "\(WFmt.duration(m)) remaining"
            case .charging, .topUp:
                return "\(s.state == .topUp ? 100 : s.targetPercent)% in \(WFmt.duration(m))"
            default: break
            }
        }
        switch s.state {
        case .limiterOff: return "Charges to 100%"
        case .unsupported: return "No charge control"
        case .calibration:
            return s.runtime.calibrationPhase?.title ?? "In progress"
        default: return "Limit \(s.targetPercent)%"
        }
    }

    func displayPercent(_ o: BatteryOptions) -> Int {
        o.hardwarePercent && battery.hardwarePercent > 0 ? Int(battery.hardwarePercent.rounded()) : percent
    }
}

/// Battery Status widget options (from BatteryStatusConfig).
struct BatteryOptions {
    var showLimitMarker = true
    var showTimeRemaining = true
    var hardwarePercent = false
}

enum WFmt {
    static func watts(_ w: Double?) -> String {
        guard let w else { return "–" }
        let a = abs(w)
        return a >= 10 ? String(format: "%.0f W", a) : String(format: "%.1f W", a)
    }

    static func signedWatts(_ w: Double) -> String {
        if abs(w) < 0.05 { return "0 W" }
        return (w > 0 ? "+" : "\u{2212}") + watts(w)
    }

    static func batterySymbol(_ pct: Int) -> String {
        switch pct {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// 3:45 (hours:minutes), or "42 min" under one hour.
    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func temp(_ c: Double) -> String { c > 0 ? String(format: "%.1f°", c) : "–" }
    static func health(_ p: Double) -> String { p > 0 ? String(format: "%.1f%%", p) : "–" }
}

// MARK: - Background

struct SimmerBackground: View {
    var tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base = scheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.135) : Color(red: 0.975, green: 0.975, blue: 0.98)
        ZStack {
            base
            LinearGradient(colors: [tint.opacity(scheme == .dark ? 0.22 : 0.14), tint.opacity(0.0)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Ring

/// Battery ring: track, charge arc, charge-limit tick, percent in the middle.
struct ChargeRing: View {
    var percent: Int
    var target: Int?
    var color: Color
    var symbol: String
    var lineWidth: CGFloat = 9

    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = (size - lineWidth) / 2
            ZStack {
                Circle()
                    .stroke(color.opacity(mode == .fullColor ? 0.18 : 0.25), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(min(100, max(0, percent))) / 100)
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                if let target, target < 100 {
                    LimitTick(lineWidth: lineWidth)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(Double(target) / 100 * 360))
                }
                VStack(spacing: size * 0.01) {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.14, weight: .bold))
                        .foregroundStyle(mode == .fullColor ? color : .primary)
                        .widgetAccentable()
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(percent)")
                            .font(.system(size: size * 0.30, weight: .semibold, design: .rounded))
                        Text("%")
                            .font(.system(size: size * 0.14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                }
                .padding(.horizontal, lineWidth + 4)
                .offset(y: -size * 0.02)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Small bar across the ring at the charge limit.
struct LimitTick: View {
    var lineWidth: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Capsule()
            .fill(.primary)
            .frame(width: 3, height: lineWidth + 6)
            .overlay(Capsule().stroke(scheme == .dark ? Color.black.opacity(0.6) : Color.white.opacity(0.9), lineWidth: 1.5))
    }
}

// MARK: - Shared pieces

/// Ring plus state title and limit text. The whole small widget, and the left half of medium and large.
struct SummaryView: View {
    var entry: SimmerEntry
    var ringSize: CGFloat
    var options = BatteryOptions()
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let st = entry.style
        VStack(spacing: 7) {
            ChargeRing(percent: entry.displayPercent(options), target: options.showLimitMarker ? entry.target : nil,
                       color: st.color, symbol: st.symbol,
                       lineWidth: ringSize * 0.105)
                .frame(width: ringSize, height: ringSize)
            VStack(spacing: 1) {
                Text(st.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(entry.subtitle(options))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

struct PowerNode: View {
    var symbol: String
    var value: String
    var label: String
    var dimmed = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(height: 19)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .opacity(dimmed ? 0.45 : 1)
    }
}

struct FlowArrow: View {
    var symbol: String
    var active: Bool
    var color: Color
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(active && mode == .fullColor ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
            .widgetAccentable(active)
            .offset(y: -8)
    }
}

/// Adapter -> Mac <- / -> Battery, with watts.
struct PowerFlowView: View {
    var entry: SimmerEntry

    var body: some View {
        let bw = entry.batteryW
        let flowing = abs(bw) >= 0.3
        HStack(spacing: 0) {
            PowerNode(symbol: "powerplug.fill", value: entry.pluggedIn ? WFmt.watts(entry.adapterW ?? Double(entry.battery.adapterWatts)) : "–",
                      label: "Adapter", dimmed: !entry.pluggedIn)
            FlowArrow(symbol: "arrow.right", active: entry.pluggedIn, color: .green)
            PowerNode(symbol: "laptopcomputer", value: WFmt.watts(entry.systemW), label: "Mac")
            FlowArrow(symbol: !flowing ? "minus" : (bw > 0 ? "arrow.right" : "arrow.left"), active: flowing,
                      color: bw > 0 ? .green : .orange)
            PowerNode(symbol: bw > 0.3 ? "battery.100percent.bolt" : WFmt.batterySymbol(entry.percent),
                      value: WFmt.signedWatts(bw), label: "Battery")
        }
    }
}

struct StatItem: View {
    var symbol: String
    var value: String
    var label: String
    var tint: Color
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(mode == .fullColor ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Tile<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        content
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(.primary.opacity(mode == .fullColor ? 0.05 : 0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// Right half of the medium widget: power flow and stats, or the helper warning.
struct DetailsView: View {
    var entry: SimmerEntry
    /// The large widget shows health in its own section, so it shows cycles here instead.
    var showCycles = false
    var options = BatteryOptions()

    var body: some View {
        VStack(spacing: 8) {
            if entry.helperRunning {
                Tile { PowerFlowView(entry: entry) }
            } else {
                Tile {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)
                            .widgetAccentable()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Charge limit not active")
                                .font(.system(size: 12, weight: .semibold))
                            Text("The Simmer helper is not running. Open Simmer to install or start it.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            Tile {
                HStack(spacing: 4) {
                    StatItem(symbol: "thermometer.medium", value: WFmt.temp(entry.temperatureC), label: "Temp", tint: .orange)
                    if showCycles {
                        StatItem(symbol: "arrow.triangle.2.circlepath", value: entry.battery.cycleCount > 0 ? "\(entry.battery.cycleCount)" : "–",
                                 label: "Cycles", tint: .blue)
                    } else {
                        StatItem(symbol: "heart.fill", value: WFmt.health(entry.healthPercent), label: "Health", tint: .pink)
                    }
                }
            }
        }
    }
}

// MARK: - Charts

/// Charge % over the last 24 h, with the charge limit as a dashed rule.
struct DayChart: View {
    var entry: SimmerEntry
    var color: Color
    var showLimit = true

    private struct Point: Identifiable { var id: Date { t }; var t: Date; var pct: Int; var segment: Int }

    /// Splits the samples where the Mac slept (gap > 20 min) so the line does not bridge the gap.
    private var points: [Point] {
        var seg = 0
        var out: [Point] = []
        var last: Date?
        for s in entry.daySamples {
            if let last, s.t.timeIntervalSince(last) > 20 * 60 { seg += 1 }
            out.append(Point(t: s.t, pct: s.pct, segment: seg))
            last = s.t
        }
        return out
    }

    var body: some View {
        let pts = points
        let start = entry.date.addingTimeInterval(-86_400)
        if pts.count < 2 {
            Placeholder(symbol: "chart.xyaxis.line", text: "Collecting data")
        } else {
            Chart {
                ForEach(pts) { p in
                    AreaMark(x: .value("Time", p.t), y: .value("Charge", p.pct), series: .value("Segment", p.segment))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", p.t), y: .value("Charge", p.pct), series: .value("Segment", p.segment))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if showLimit, let target = entry.target {
                    RuleMark(y: .value("Limit", target))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .widgetAccentable()
            .chartXScale(domain: start...entry.date)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.secondary.opacity(0.4))
                    AxisValueLabel { if let i = v.as(Int.self) { Text("\(i)%") } }
                        .font(.system(size: 9))
                }
            }
            .chartXAxis {
                AxisMarks(values: hourMarks(start: start, end: entry.date)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.secondary.opacity(0.25))
                    AxisValueLabel(format: .dateTime.hour(), anchor: .top)
                        .font(.system(size: 9))
                }
            }
        }
    }
}

/// Every 6th local hour inside the window, away from the edges so the labels are not clipped.
func hourMarks(start: Date, end: Date) -> [Date] {
    let cal = Calendar.current
    guard var d = cal.nextDate(after: start, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) else { return [] }
    var out: [Date] = []
    while d < end {
        if cal.component(.hour, from: d) % 6 == 0, d.timeIntervalSince(start) > 1800, end.timeIntervalSince(d) > 5400 { out.append(d) }
        d = d.addingTimeInterval(3600)
    }
    return out
}

/// Health % per day.
struct HealthChart: View {
    var days: [DailyBatteryRecord]
    var color: Color

    var body: some View {
        let vals = days.map(\.healthPercent)
        let lo = (vals.min() ?? 0), hi = (vals.max() ?? 100)
        let pad = max(0.5, (hi - lo) * 0.3)
        Chart(days) { d in
            LineMark(x: .value("Day", d.date), y: .value("Health", d.healthPercent))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            AreaMark(x: .value("Day", d.date), yStart: .value("Min", lo - pad), yEnd: .value("Health", d.healthPercent))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
        }
        .widgetAccentable()
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

struct Placeholder: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SectionLabel: View {
    var text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

struct HealthSection: View {
    var entry: SimmerEntry

    var body: some View {
        let days = entry.healthDays
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                SectionLabel(text: "Health")
                Text(WFmt.health(entry.healthPercent))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(trendText(days))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 104, alignment: .leading)
            if days.count >= 2 {
                HealthChart(days: days, color: .pink)
            } else {
                Placeholder(symbol: "clock", text: "Collecting data")
            }
        }
    }

    private func trendText(_ days: [DailyBatteryRecord]) -> String {
        guard days.count >= 2, let f = days.first, let l = days.last else {
            return entry.battery.cycleCount > 0 ? "\(entry.battery.cycleCount) cycles" : "Daily record"
        }
        let delta = l.healthPercent - f.healthPercent
        let span = max(1, Int((l.date.timeIntervalSince(f.date) / 86_400).rounded()))
        let d = abs(delta) < 0.05 ? "No change" : String(format: "%@%.1f%%", delta > 0 ? "+" : "\u{2212}", abs(delta))
        return "\(d) in \(span) d"
    }
}

// MARK: - Families

struct SmallWidgetView: View {
    var entry: SimmerEntry
    var options = BatteryOptions()
    var body: some View {
        SummaryView(entry: entry, ringSize: 88, options: options)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MediumWidgetView: View {
    var entry: SimmerEntry
    var showCycles = false
    var options = BatteryOptions()
    var body: some View {
        HStack(spacing: 14) {
            SummaryView(entry: entry, ringSize: 88, options: options)
                .frame(width: 120)
            DetailsView(entry: entry, showCycles: showCycles, options: options)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LargeWidgetView: View {
    var entry: SimmerEntry
    var options = BatteryOptions()
    var body: some View {
        VStack(spacing: 12) {
            MediumWidgetView(entry: entry, showCycles: true, options: options)
                .frame(height: 128)
            VStack(spacing: 5) {
                SectionLabel(text: "Last 24 Hours", trailing: options.showLimitMarker ? entry.target.map { "Limit \($0)%" } : nil)
                DayChart(entry: entry, color: entry.style.color, showLimit: options.showLimitMarker)
            }
            .frame(maxHeight: .infinity)
            HealthSection(entry: entry)
                .frame(height: 50)
        }
    }
}

struct SimmerWidgetView: View {
    var entry: SimmerEntry
    var options = BatteryOptions()
    var family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .systemMedium: MediumWidgetView(entry: entry, options: options)
            case .systemLarge, .systemExtraLarge: LargeWidgetView(entry: entry, options: options)
            default: SmallWidgetView(entry: entry, options: options)
            }
        }
        .containerBackground(for: .widget) { SimmerBackground(tint: entry.style.color) }
        .widgetURL(URL(string: "simmer://open"))
    }
}

// MARK: - Shared chrome for all widget kinds

extension View {
    /// Background, deep link and padding shared by every Simmer widget.
    func simmerWidgetChrome(tint: Color) -> some View {
        self
            .containerBackground(for: .widget) { SimmerBackground(tint: tint) }
            .widgetURL(URL(string: "simmer://open"))
    }
}

/// "Helper not running" notice. Compact for small widgets, a tile for wider ones.
struct HelperOffNotice: View {
    var compact = false
    var message = "Open Simmer to install or start it."

    var body: some View {
        if compact {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                    .widgetAccentable()
                Text("Helper Not Running")
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Tile {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Helper not running")
                            .font(.system(size: 12, weight: .semibold))
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Small header used by the single-purpose widgets: tinted symbol and an uppercase title.
struct WidgetHeader: View {
    var symbol: String
    var title: String
    var tint: Color
    var trailing: String? = nil
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(mode == .fullColor ? AnyShapeStyle(tint) : AnyShapeStyle(.primary))
                .widgetAccentable()
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

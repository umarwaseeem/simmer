import SwiftUI
import WidgetKit
import Charts
import SimmerShared

// MARK: - Power Flow widget: adapter -> Mac -> battery, plus the Mac's power over the last hour.

struct PowerFlowWidgetView: View {
    var entry: SimmerEntry
    var family: WidgetFamily

    var body: some View {
        Group {
            if !entry.helperRunning {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(symbol: "bolt.horizontal.fill", title: "Power Flow", tint: .orange)
                    HelperOffNotice(compact: family == .systemSmall, message: "Power readings need the Simmer helper.")
                }
            } else if family == .systemSmall {
                PowerFlowSmallView(entry: entry)
            } else {
                PowerFlowMediumView(entry: entry)
            }
        }
        .simmerWidgetChrome(tint: entry.helperRunning ? .green : .orange)
    }
}

/// One node of the vertical flow: tinted symbol, name, watts.
private struct FlowRow: View {
    var symbol: String
    var label: String
    var value: String
    var tint: Color
    var dimmed = false
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(mode == .fullColor ? AnyShapeStyle(tint) : AnyShapeStyle(.primary))
                .widgetAccentable()
                .frame(width: 26, height: 26)
                .background(tint.opacity(mode == .fullColor ? 0.16 : 0.1), in: Circle())
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .opacity(dimmed ? 0.45 : 1)
    }
}

/// Vertical connector between two flow rows.
private struct FlowConnector: View {
    var symbol: String
    var active: Bool
    var color: Color
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(active && mode == .fullColor ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
            .widgetAccentable(active)
            .frame(width: 26, height: 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PowerFlowSmallView: View {
    var entry: SimmerEntry

    var body: some View {
        let bw = entry.batteryW
        let flowing = abs(bw) >= 0.3
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(symbol: "bolt.horizontal.fill", title: "Power Flow", tint: .green)
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                FlowRow(symbol: "powerplug.fill", label: "Adapter",
                        value: entry.pluggedIn ? WFmt.watts(entry.adapterW ?? Double(entry.battery.adapterWatts)) : "–",
                        tint: .green, dimmed: !entry.pluggedIn)
                FlowConnector(symbol: "arrow.down", active: entry.pluggedIn, color: .green)
                FlowRow(symbol: "laptopcomputer", label: "Mac", value: WFmt.watts(entry.systemW), tint: .blue)
                FlowConnector(symbol: !flowing ? "minus" : (bw > 0 ? "arrow.down" : "arrow.up"), active: flowing,
                              color: bw > 0 ? .green : .orange)
                FlowRow(symbol: bw > 0.3 ? "battery.100percent.bolt" : WFmt.batterySymbol(entry.percent), label: "Battery",
                        value: WFmt.signedWatts(bw), tint: bw < -0.3 ? .orange : .teal)
            }
            Spacer(minLength: 0)
        }
    }
}

struct PowerFlowMediumView: View {
    var entry: SimmerEntry

    var body: some View {
        let pts = SparkPoint.lastHour(entry)
        let ws = pts.map(\.w)
        VStack(spacing: 8) {
            Tile { PowerFlowView(entry: entry) }
            VStack(spacing: 4) {
                SectionLabel(text: "Mac · Last Hour",
                             trailing: ws.count < 2 ? nil : "avg \(WFmt.watts(ws.reduce(0, +) / Double(ws.count))) · peak \(WFmt.watts(ws.max()))")
                if pts.count >= 2 {
                    PowerSparkline(points: pts, start: entry.date.addingTimeInterval(-3600), end: entry.date, color: .blue)
                } else {
                    Placeholder(symbol: "chart.xyaxis.line", text: "Collecting data")
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct SparkPoint: Identifiable {
    var t: Date
    var w: Double
    var segment: Int
    var id: Date { t }

    /// System watts from the last hour of history, plus the live reading at the end.
    static func lastHour(_ e: SimmerEntry) -> [SparkPoint] {
        var raw: [(Date, Double)] = e.samples(last: 3600).compactMap { s in s.systemW.map { (s.t, $0) } }
        if let live = e.systemW, (raw.last?.0 ?? .distantPast) < e.date.addingTimeInterval(-30) { raw.append((e.date, live)) }
        var seg = 0
        var out: [SparkPoint] = []
        var last: Date?
        for (t, w) in raw {
            if let last, t.timeIntervalSince(last) > 15 * 60 { seg += 1 }
            out.append(SparkPoint(t: t, w: w, segment: seg))
            last = t
        }
        return out
    }
}

/// Minimal area + line chart with a dot on the newest value.
struct PowerSparkline: View {
    var points: [SparkPoint]
    var start: Date
    var end: Date
    var color: Color

    var body: some View {
        let hi = max(5, (points.map(\.w).max() ?? 5) * 1.2)
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.t), y: .value("Watts", p.w), series: .value("Segment", p.segment))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.t), y: .value("Watts", p.w), series: .value("Segment", p.segment))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(x: .value("Time", last.t), y: .value("Watts", last.w))
                    .foregroundStyle(color)
                    .symbolSize(28)
            }
        }
        .widgetAccentable()
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...hi)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

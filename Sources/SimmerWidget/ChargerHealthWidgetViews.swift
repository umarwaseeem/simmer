import SwiftUI
import WidgetKit
import SimmerShared

// MARK: - Charger & Health widget: charger verdict, battery health, cycles, cell balance.

struct ChargerPresentation {
    var title: String
    var symbol: String
    var color: Color
    var headline: String
    var facts: String?

    init(_ e: SimmerEntry) {
        let r = e.chargerReport
        let plugged = e.pluggedIn
        switch r.rating {
        case .excellent: title = "Excellent"; symbol = "checkmark.seal.fill"; color = .green
        case .good: title = "Good"; symbol = "checkmark.circle.fill"; color = .teal
        case .limited: title = "Limited"; symbol = "exclamationmark.circle.fill"; color = .orange
        case .insufficient: title = "Too Weak"; symbol = "xmark.octagon.fill"; color = .red
        case .none:
            title = plugged ? "Connected" : "No Charger"
            symbol = plugged ? "bolt.fill" : "powerplug"
            color = plugged ? .blue : .gray
        }
        if !r.headline.isEmpty {
            headline = r.headline
        } else if plugged {
            headline = r.adapterName.isEmpty ? "Power adapter" : r.adapterName
        } else {
            headline = "Connect a charger to check it."
        }
        if plugged, r.negotiatedWatts > 0 {
            var parts = ["\(r.negotiatedWatts) W"]
            if r.voltageV > 0 { parts.append(String(format: "%.0f V", r.voltageV)) }
            if r.currentA > 0 { parts.append(String(format: "%.1f A", r.currentA)) }
            facts = parts.joined(separator: " · ")
        } else {
            facts = nil
        }
    }
}

struct ChargerHealthWidgetView: View {
    var entry: SimmerEntry
    var family: WidgetFamily

    var body: some View {
        let p = ChargerPresentation(entry)
        Group {
            if family == .systemSmall {
                small(p)
            } else {
                medium(p)
            }
        }
        .simmerWidgetChrome(tint: p.color)
    }

    private func chargerBlock(_ p: ChargerPresentation, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetHeader(symbol: "powerplug.fill", title: "Charger", tint: p.color)
            HStack(spacing: 5) {
                Image(systemName: p.symbol)
                    .font(.system(size: compact ? 15 : 17, weight: .semibold))
                    .foregroundStyle(p.color)
                    .widgetAccentable()
                Text(p.title)
                    .font(.system(size: compact ? 16 : 19, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 2)
            Text(p.headline)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(compact ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)
            if !compact, let f = p.facts {
                Text(f)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
            }
        }
    }

    private func small(_ p: ChargerPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            chargerBlock(p, compact: true)
            Spacer(minLength: 6)
            Tile {
                HStack(spacing: 2) {
                    StatItem(symbol: "heart.fill", value: WFmt.health(entry.healthPercent), label: "Health", tint: .pink)
                    StatItem(symbol: "arrow.triangle.2.circlepath", value: cycles, label: "Cycles", tint: .blue)
                }
            }
        }
    }

    private func medium(_ p: ChargerPresentation) -> some View {
        HStack(alignment: .top, spacing: 14) {
            chargerBlock(p, compact: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack(spacing: 6) {
                HealthRow(symbol: "heart.fill", tint: .pink, label: "Health", value: WFmt.health(entry.healthPercent),
                          detail: entry.battery.rawMaxCapacity > 0 ? "\(entry.battery.rawMaxCapacity) mAh" : nil)
                HealthRow(symbol: "arrow.triangle.2.circlepath", tint: .blue, label: "Cycles", value: cycles, detail: nil)
                HealthRow(symbol: "scalemass.fill", tint: balanceColor, label: "Cell Balance", value: balanceValue, detail: balanceDetail)
            }
            .frame(width: 176)
        }
    }

    private var cycles: String { entry.battery.cycleCount > 0 ? "\(entry.battery.cycleCount)" : "–" }

    private var cells: [Int] { entry.details?.cellVoltagesMV ?? [] }

    private var balanceValue: String { cells.count >= 2 ? "\(entry.details!.cellImbalanceMV) mV" : "–" }

    private var balanceDetail: String? {
        guard cells.count >= 2, let d = entry.details else { return nil }
        switch d.cellBalance {
        case .good: return "Good"
        case .watch: return "Watch"
        case .poor: return "Service soon"
        }
    }

    private var balanceColor: Color {
        guard cells.count >= 2, let d = entry.details else { return .gray }
        switch d.cellBalance {
        case .good: return .green
        case .watch: return .orange
        case .poor: return .red
        }
    }
}

private struct HealthRow: View {
    var symbol: String
    var tint: Color
    var label: String
    var value: String
    var detail: String?
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(mode == .fullColor ? AnyShapeStyle(tint) : AnyShapeStyle(.primary))
                .widgetAccentable()
                .frame(width: 24, height: 24)
                .background(tint.opacity(mode == .fullColor ? 0.15 : 0.1), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if let detail {
                    Text(detail)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(.primary.opacity(mode == .fullColor ? 0.05 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

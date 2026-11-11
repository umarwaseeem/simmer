import SwiftUI
import AppIntents
import WidgetKit
import SimmerShared

// MARK: - Charging Controls widget: interactive buttons (macOS 14+) that run App Intents in the
// widget process. The intents call simmerd over XPC (see SimmerWidget.entitlements, mach-lookup).

/// A rounded button that runs an App Intent.
struct IntentButton<I: AppIntent>: View {
    var intent: I
    var title: String
    var symbol: String?
    var tint: Color
    var active = false
    var enabled = true
    var vertical = true
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Button(intent: intent) {
            Group {
                if vertical {
                    VStack(spacing: 3) { label }
                } else {
                    HStack(spacing: 4) { label }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(active ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.primary.opacity(mode == .fullColor ? 0.07 : 0.1)))
                    .widgetAccentable(active)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    @ViewBuilder private var label: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(height: 16)
                .foregroundStyle(active ? AnyShapeStyle(Color.white) : (mode == .fullColor ? AnyShapeStyle(tint) : AnyShapeStyle(.primary)))
        }
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

/// What the controls can do right now.
struct ControlsState {
    var topUpActive: Bool
    var dischargeActive: Bool
    var canTopUp: Bool
    var canDischarge: Bool
    var canPause: Bool
    var limit: Int?

    init(_ e: SimmerEntry) {
        let s = e.status
        topUpActive = s?.runtime.topUp == true || s?.state == .topUp
        dischargeActive = s?.runtime.manualDischarge == true
        let supportsDischarge = (s?.supportsDischarge ?? false) || (s?.capabilities.discharge ?? false)
        canTopUp = topUpActive || e.pluggedIn
        canDischarge = dischargeActive || (e.pluggedIn && supportsDischarge && e.percent > (e.userLimit ?? 100))
        canPause = e.battery.present
        limit = e.userLimit
    }
}

struct ControlsWidgetView: View {
    var entry: SimmerEntry
    var limits: [Int]
    var family: WidgetFamily

    var body: some View {
        Group {
            if !entry.helperRunning {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(symbol: "slider.horizontal.3", title: "Controls", tint: .orange)
                    HelperOffNotice(compact: family == .systemSmall, message: "The buttons need the Simmer helper. Open Simmer to start it.")
                }
            } else if family == .systemSmall {
                small
            } else {
                medium
            }
        }
        .simmerWidgetChrome(tint: entry.style.color)
    }

    private var header: some View {
        let st = entry.style
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: st.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(st.color)
                .widgetAccentable()
            Text("\(entry.percent)%")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(st.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
        }
    }

    private var small: some View {
        let c = ControlsState(entry)
        let preset = limits.count > 1 ? limits[1] : 80
        return VStack(spacing: 6) {
            header
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    topUpButton(c)
                    pauseButton(c)
                }
                GridRow {
                    dischargeButton(c)
                    IntentButton(intent: SetChargeLimitIntent(percent: preset), title: "Limit \(preset)%", symbol: "gauge.with.dots.needle.67percent",
                                 tint: .teal, active: c.limit == preset)
                }
            }
        }
    }

    private var medium: some View {
        let c = ControlsState(entry)
        return VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                header
                Text(c.limit.map { "Limit \($0)%" } ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                topUpButton(c)
                pauseButton(c)
                dischargeButton(c)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                ForEach(Array(limits.enumerated()), id: \.offset) { _, v in
                    IntentButton(intent: SetChargeLimitIntent(percent: v), title: "\(v)%", symbol: nil, tint: .teal,
                                 active: c.limit == v, vertical: false)
                }
            }
            .frame(height: 30)
        }
    }

    private func topUpButton(_ c: ControlsState) -> some View {
        IntentButton(intent: TopUpIntent(enabled: !c.topUpActive), title: c.topUpActive ? "Stop Top Up" : "Top Up",
                     symbol: "bolt.fill", tint: .green, active: c.topUpActive, enabled: c.canTopUp)
    }

    private func pauseButton(_ c: ControlsState) -> some View {
        IntentButton(intent: PauseChargingIntent(), title: "Pause", symbol: "pause.fill", tint: .teal, enabled: c.canPause)
    }

    private func dischargeButton(_ c: ControlsState) -> some View {
        IntentButton(intent: DischargeIntent(enabled: !c.dischargeActive), title: c.dischargeActive ? "Stop" : "Discharge",
                     symbol: "arrow.down", tint: .orange, active: c.dischargeActive, enabled: c.canDischarge)
    }
}

import SwiftUI
import AppKit
import SimmerShared

// MARK: - Quick limit chips

/// One-click limits, for example 60 / 80 / 100. The presets are edited on the Menu Bar Panel settings page.
struct QuickLimitChips: View {
    let presets: [Int]
    let current: Int
    let enabled: Bool
    let set: (Int) -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.self) { p in
                let on = p == current
                Button { set(p) } label: {
                    Text("\(p)%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(on ? AnyShapeStyle(Brand.onAccent.color) : AnyShapeStyle(.primary))
                .background(Capsule().fill(on ? AnyShapeStyle(Brand.accentFill.color) : AnyShapeStyle(.primary.opacity(0.07))))
                .help("Set the charge limit to \(p)%")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Button(action: edit) {
                Image(systemName: "pencil").font(.caption.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(.limitPresets)
            .accessibilityLabel("Edit quick limits")
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

// MARK: - Effective limit

/// "Desk mode: holding 55%" and similar, when the daemon applies another limit than the user's.
struct LimitReasonRow: View {
    let status: SimmerStatus
    let userLimit: Int

    var body: some View {
        if let text = status.limitReasonText(userLimit: userLimit) {
            HStack(spacing: 6) {
                Image(systemName: status.limitReasonSymbol).foregroundStyle(.tint).imageScale(.small)
                Text(text).font(.caption.weight(.medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Your limit \(userLimit)%").font(.caption2).foregroundStyle(.secondary).fixedSize()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(.tint.opacity(0.12)))
            .help(status.limitReasonTopic)
        }
    }
}

/// Shown instead of Top Up / Discharge / sailing on Intel Macs that only support a fixed charge level (BCLM).
struct LimitOnlyNote: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var native = NativeLimitController.shared

    var body: some View {
        Label(message, systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help(model.status?.usingNativeLimit == true
                  ? "macOS only lets apps set its own Charge Limit here, in steps. Discharge, top-up timing, sailing and heat pause need direct control."
                  : HelpTopic.capabilityLimitOnly.tooltip)
    }

    private var message: String {
        guard let s = model.status, s.usingNativeLimit else { return UICapabilities.limitOnlyMessage }
        if let err = native.lastError { return "macOS Charge Limit: \(err)" }
        let held = native.appliedLimit ?? native.nativeTarget(for: s.effectiveLimit)
        let why = s.chargeControlBlocked ? "macOS blocks direct charge control" : "chosen in Settings"
        return "Using the macOS Charge Limit (\(held)%) because \(why). Steps: \(native.availableLimits.map(String.init).joined(separator: ", "))%."
    }
}

// MARK: - Charger report

struct ChargerCard: View {
    let report: ChargerReport
    let battery: BatterySnapshot
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Charger", topic: .chargerReport)
            Button(action: open) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: report.rating.symbol)
                        .foregroundStyle(report.rating.tint)
                        .font(.system(size: 15))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.headlineOrFallback(battery: battery))
                            .font(.callout.weight(.medium))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        .padding(.top, 3)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(report.rating.tint.opacity(0.10)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the full charger report")
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if report.rating != .none { parts.append(report.rating.title) }
        let w = report.negotiatedWatts > 0 ? report.negotiatedWatts : battery.adapterWatts
        if w > 0 { parts.append("\(w) W offered") }
        if let p = report.peakSystemWatts { parts.append(String(format: "peak use %.0f W", p)) }
        return parts.isEmpty ? "Tap for details" : parts.joined(separator: " · ")
    }
}

// MARK: - Top energy apps

struct TopAppsCard: View {
    let energy: EnergyReport?
    let loaded: Bool
    let fresh: Bool
    let simmerWatts: Double?
    let helperConnected: Bool
    let open: () -> Void

    static let count = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionTitle("Top Energy Apps", topic: .topApps)
                Spacer()
                Button("All…", action: open).buttonStyle(.borderless).controlSize(.small).font(.caption)
                    .help("Open the Energy page")
            }
            if let e = energy, !e.entries.isEmpty {
                let top = Array(e.entries.filter { !InsightsModel.isSimmer($0) }.sorted { $0.watts1m > $1.watts1m }.prefix(Self.count))
                let maxW = max(top.first?.watts1m ?? 1, 0.1)
                ForEach(top) { entry in
                    EnergyMiniRow(entry: entry, maxWatts: maxW)
                }
                HStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                        .resizable().frame(width: 14, height: 14)
                    Text(simmerWatts.map { String(format: "Simmer uses %.2f W", $0) } ?? "Simmer uses almost nothing")
                        .font(.caption.weight(.medium)).foregroundStyle(.tint)
                    Spacer()
                    if !fresh {
                        Text("Updated \(e.generatedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 1)
            } else {
                Text(emptyText).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyText: String {
        if !loaded { return "Loading…" }
        if energy != nil { return "No app is using noticeable power right now." }
        return helperConnected
            ? "App energy appears here once the helper records it. Update the helper if this stays empty."
            : "The helper measures app energy. Install it to see which apps drain the battery."
    }
}

struct EnergyMiniRow: View {
    let entry: EnergyEntry
    let maxWatts: Double

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: AppIcons.icon(for: entry)).resizable().frame(width: 16, height: 16)
            Text(entry.name).font(.callout).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Capsule().fill(Color.orange.opacity(0.75))
                .frame(width: max(2, 46 * entry.watts1m / maxWatts), height: 4)
                .frame(width: 46, alignment: .trailing)
            Text(EnergyFmt.watts(entry.watts1m))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .help("\(entry.name): \(EnergyFmt.watts(entry.watts1m)) now, \(EnergyFmt.watts(entry.watts1h)) on average over the last hour")
    }
}

enum EnergyFmt {
    static func watts(_ w: Double) -> String {
        if w >= 10 { return String(format: "%.0f W", w) }
        if w >= 0.995 { return String(format: "%.1f W", w) }
        return String(format: "%.2f W", w)
    }
}

// MARK: - Banners

struct ConflictBanner: View {
    let conflicts: [Conflict]
    let open: () -> Void

    var body: some View {
        Banner(symbol: "exclamationmark.octagon.fill", tint: .red,
               title: conflicts.count == 1 ? "Conflict: \(conflicts[0].name)" : "\(conflicts.count) conflicts found",
               message: conflicts.count == 1
                   ? Self.shortText(conflicts[0])
                   : "Other charge limiters can fight with Simmer over the same settings. Conflict Doctor shows how to fix it.") {
            Button("Open Conflict Doctor", action: open).help(.conflicts)
        }
    }
}

extension ConflictBanner {
    static func shortText(_ c: Conflict) -> String {
        switch c.kind {
        case .leftoverHelper: return "Its background helper can change the same charging settings as Simmer. Conflict Doctor can remove it."
        case .runningApp: return "\(c.name) is running and controls charging too. Quit it so the limit does not jump."
        case .nativeChargeLimit: return "The macOS charge limit is on. Use either the macOS limit or Simmer, not both."
        }
    }
}

struct HelperUpdateBanner: View {
    let installing: Bool
    let install: () -> Void

    var body: some View {
        Banner(symbol: "arrow.triangle.2.circlepath.circle.fill", tint: .blue,
               title: "Simmer was updated — update the helper",
               message: "The background helper is older than the app. Update it to get the new features. You need an administrator password.") {
            Button("Update Helper", action: install).disabled(installing).help(.helperUpdate)
        }
    }
}

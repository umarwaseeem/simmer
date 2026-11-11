import SwiftUI
import ServiceManagement
import SimmerShared

struct GeneralPage: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var helperLocked: Bool { model.reachable != true }

    var body: some View {
        SettingsForm(page: .general, model: model) {
            Section {
                StatusSummary(model: model)
            }

            if helperLocked {
                Section { HelperRequiredNote(model: model) }
            }

            Section {
                SettingToggle("Charge limiter", caption: "When off, your Mac charges to 100% the normal Apple way.",
                              topic: .limiter, isOn: model.binding(\.limiterEnabled))
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { Double(model.config.chargeLimit) },
                                              set: { v in model.updateConfig { c in c.chargeLimit = Int(v.rounded()) } }),
                               in: 20...100, step: 5)
                            .frame(minWidth: 160)
                        Text("\(model.config.chargeLimit)%")
                            .font(.body.monospacedDigit().weight(.medium))
                            .frame(width: 42, alignment: .trailing)
                    }
                } label: { HelpLabel("Charge limit", .chargeLimit) }
                .help(.chargeLimit)
            } header: {
                Text("Charge Limit")
            } footer: {
                SectionCaption("60–80% is gentlest for a Mac that is mostly plugged in.")
            }
            .disabled(helperLocked)

            Section("Menu Bar") {
                Picker(selection: $model.prefs.useBatteryIcon) {
                    Text("Simmer jar").tag(false)
                    Text("Battery").tag(true)
                } label: { Text("Menu bar icon") }
                .help("The Simmer jar fills with the charge and steams while charging. Battery uses the classic battery symbol.")
                Toggle(isOn: $model.prefs.showPercent) { HelpLabel("Show percentage", .menuBarExtras) }
                Toggle(isOn: $model.prefs.showHardwarePercent) { HelpLabel("Use the hardware percentage", .hardwarePercentInMenuBar) }
                    .disabled(!model.prefs.showPercent)
                Toggle(isOn: $model.prefs.showTemperature) { HelpLabel("Show battery temperature", .menuBarExtras) }
                Toggle(isOn: $model.prefs.showSystemWatts) { HelpLabel("Show system power (W)", .menuBarExtras) }
            }

            Section("Notifications & Startup") {
                SettingToggle("Notifications", caption: "Limit reached, heat, desk mode, smart top-up, a weak charger, cell balance and conflicts.",
                              topic: .notifications, isOn: $model.prefs.notificationsEnabled)
                SettingToggle("Launch at login", topic: .launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin { launchAtLogin = actual }
    }
}

/// Current state, percent, limit and helper connection, at the top of the General page.
struct StatusSummary: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let b = model.battery
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: MenuBarLabel.batterySymbol(b.percent))
                    .font(.system(size: 30))
                    .foregroundStyle(model.stateTint)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.stateTitle).font(.headline)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(b.percent)%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .help(.battery)
            }
            HStack(spacing: 8) {
                StatusChip(symbol: "target", text: model.config.limiterEnabled ? "Limit \(model.config.chargeLimit)%" : "Limiter off",
                           tint: .blue)
                    .help(.chargeLimit)
                if let s = model.status, model.config.limiterEnabled, s.limitDiffers(from: model.config.chargeLimit) {
                    StatusChip(symbol: s.limitReasonSymbol, text: "Active \(s.effectiveLimit)%", tint: .mint)
                        .help(s.limitReasonText(userLimit: model.config.chargeLimit) ?? HelpTopic.effectiveLimit.tooltip)
                }
                StatusChip(symbol: b.externalConnected ? "powerplug.fill" : "battery.50percent",
                           text: b.externalConnected ? "Plugged in" : "On battery", tint: .green)
                StatusChip(symbol: helperSymbol, text: helperText, tint: helperTint)
                    .help(.helper)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let b = model.battery
        var parts: [String] = []
        if let s = model.status { parts.append("Target \(s.targetPercent)%") }
        if let t = b.timeRemainingMin { parts.append("\(Fmt.duration(minutes: t)) \(b.isCharging ? "to full" : "left")") }
        parts.append(Fmt.temp(model.status?.temperatureC ?? b.temperatureC))
        return parts.joined(separator: " · ")
    }

    private var helperText: String {
        switch model.reachable {
        case .some(true): return "Helper connected"
        case .some(false): return model.helperInstalled ? "Helper not responding" : "Helper not installed"
        case .none: return "Checking helper…"
        }
    }
    private var helperSymbol: String {
        switch model.reachable {
        case .some(true): return "checkmark.circle.fill"
        case .some(false): return "exclamationmark.triangle.fill"
        case .none: return "ellipsis.circle"
        }
    }
    private var helperTint: Color {
        switch model.reachable {
        case .some(true): return .green
        case .some(false): return .orange
        case .none: return .secondary
        }
    }
}

struct StatusChip: View {
    let symbol: String, text: String, tint: Color
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(tint).imageScale(.small)
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

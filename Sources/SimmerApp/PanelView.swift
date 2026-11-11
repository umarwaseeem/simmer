import SwiftUI
import AppKit
import SimmerShared

struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var insights: InsightsModel = .shared
    @ObservedObject var layoutStore: PanelLayoutStore = .shared
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsPage.storageKey) private var settingsPage = SettingsPage.general.rawValue
    @State private var sliderValue: Double = 80
    @State private var dragging = false
    @Environment(\.colorScheme) private var scheme

    private var status: SimmerStatus? { model.status }
    private var caps: UICapabilities { UICapabilities(status) }

    /// Sections that have something to show right now, in the user's order.
    private var shownSections: [PanelSection] {
        layoutStore.layout.visible.filter { section in
            switch section {
            case .chargeControls, .powerFlow, .powerModes: return status != nil
            case .chargerReport: return model.battery.externalConnected
            case .battery, .topApps: return true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            banners
            ForEach(shownSections) { section in
                Divider()
                sectionView(section)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            sliderValue = Double(model.config.chargeLimit)
            model.refresh()
            insights.reloadEnergy()
        }
        .onChange(of: model.config.chargeLimit) { _, v in
            if !dragging { sliderValue = Double(v) }
        }
    }

    @ViewBuilder private func sectionView(_ section: PanelSection) -> some View {
        switch section {
        case .chargeControls: if let s = status { chargeControls(s) }
        case .chargerReport:
            ChargerCard(report: insights.chargerReport(status: status, battery: model.battery), battery: model.battery) {
                open(.charger)
            }
        case .powerFlow: if let s = status { powerFlow(s) }
        case .battery: batteryStats
        case .topApps:
            TopAppsCard(energy: insights.energy, loaded: insights.energyLoaded, fresh: insights.energyIsFresh,
                        simmerWatts: insights.simmerWatts, helperConnected: model.connected) { open(.energy) }
        case .powerModes: if let s = status { powerModes(s) }
        }
    }

    private func open(_ page: SettingsPage) {
        settingsPage = page.rawValue
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    // MARK: header

    @ViewBuilder private var header: some View {
        if layoutStore.layout.showsIllustration {
            HStack(alignment: .center, spacing: 16) {
                GlowingJar(percent: model.battery.percent, limit: jarLimit,
                           mood: JarMood(status: status, battery: model.battery))
                    .frame(width: 62, height: 104)
                    .padding(.leading, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.battery.percent)%")
                        .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(stateTitle).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let e = estimate { estimateChip(e).padding(.top, 3) }
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stateTitle).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(model.battery.percent)%")
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                }
                if let e = estimate { estimateChip(e) }
            }
        }
    }

    /// The dashed line in the jar: the level the helper holds now, hidden when the limiter is off.
    private var jarLimit: Int? {
        guard model.config.limiterEnabled else { return nil }
        if let s = status { return s.state == .topUp ? 100 : s.effectiveLimit }
        return model.config.chargeLimit
    }

    // MARK: time to limit

    /// Where the battery is heading now: the active limit while charging or discharging, 100% during Top Up and the
    /// charge phases of calibration. nil when holding, idle or on battery.
    private var estimateTarget: Int? {
        guard let s = status else { return nil }
        switch s.state {
        case .charging: return s.effectiveLimit
        case .topUp: return 100
        case .discharging: return s.effectiveLimit
        case .calibration: return !s.adapterDisabled && s.battery.isCharging ? 100 : nil
        case .limiterOff: return s.battery.isCharging ? 100 : nil
        default: return nil
        }
    }

    private var estimate: (target: Int, minutes: Int)? {
        guard let target = estimateTarget, let m = ChargeEstimate.minutes(to: target, battery: model.battery) else { return nil }
        return (target, m)
    }

    private func estimateChip(_ e: (target: Int, minutes: Int)) -> some View {
        let down = e.target < model.battery.percent
        return Label("\(e.target)% in \(ChargeEstimate.format(minutes: e.minutes))",
                     systemImage: down ? "arrow.down.circle" : "clock")
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(Brand.accentText(scheme))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Brand.ember.color(0.12)))
            .help("Estimate from the live charging current; charging slows down above 80%.")
    }

    private var stateTitle: String {
        guard let s = status else { return model.reachable == nil ? "Connecting…" : "Helper Unavailable" }
        if let p = s.runtime.calibrationPhase { return "Calibration: \(p.title)" }
        return s.state.title
    }

    private var subtitle: String {
        let b = model.battery
        var parts: [String] = []
        parts.append(b.externalConnected ? "Plugged in" : "On battery")
        if let s = status { parts.append("Target \(s.targetPercent)%") }
        if estimate == nil, let t = b.timeRemainingMin { parts.append("\(Fmt.duration(minutes: t)) \(b.isCharging ? "to full" : "left")") }
        return parts.joined(separator: " · ")
    }

    // MARK: banners

    @ViewBuilder private var banners: some View {
        if model.reachable == false {
            Banner(symbol: "exclamationmark.triangle.fill", tint: .orange,
                   title: model.helperInstalled ? "Helper not responding" : "Helper not installed",
                   message: model.helperInstalled
                       ? "Simmer cannot reach its background helper. Reinstall it to restore the charge limit."
                       : "Simmer needs a privileged helper to control charging.") {
                Button(model.helperInstalled ? "Reinstall Helper" : "Install Helper") { model.installHelper() }
                    .disabled(model.installing)
            }
        }
        if let s = status, s.helperOutdated, model.reachable == true {
            HelperUpdateBanner(installing: model.installing) { model.installHelper() }
        }
        if !insights.conflicts.isEmpty {
            ConflictBanner(conflicts: insights.conflicts) { open(.conflicts) }
        }
        if let s = status, s.state == .unsupported {
            Banner(symbol: "xmark.octagon.fill", tint: .red, title: "Unsupported hardware",
                   message: "The helper found no charge-control SMC keys on this Mac.") { EmptyView() }
        }
        if let err = model.commandError ?? status?.lastError {
            Label(err, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: charge controls

    private func chargeControls(_ s: SimmerStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if layoutStore.layout.usesKnob {
                LimitKnob(limit: model.config.chargeLimit, enabled: model.config.limiterEnabled && model.connected,
                          commit: { model.setLimit($0) }) {
                    limiterToggle
                }
            } else {
                HStack {
                    limiterToggle
                    Spacer()
                    Text("\(Int(sliderValue))%").font(.body.monospacedDigit().weight(.medium))
                        .help(.chargeLimit)
                    InfoButton(.chargeLimit)
                }
                Slider(value: $sliderValue, in: 20...100, step: 1) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("20").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("100").font(.caption2).foregroundStyle(.secondary)
                } onEditingChanged: { editing in
                    dragging = editing
                    if !editing { model.setLimit(Int(sliderValue.rounded())) }
                }
                .disabled(!model.config.limiterEnabled)
                .help(.chargeLimit)
            }

            QuickLimitChips(presets: layoutStore.layout.limitPresets, current: model.config.chargeLimit,
                            enabled: model.config.limiterEnabled,
                            set: { v in sliderValue = Double(v); model.setLimit(v) },
                            edit: { open(.panel) })

            LimitReasonRow(status: s, userLimit: model.config.chargeLimit)

            if caps.limitOnly {
                LimitOnlyNote()
            } else {
                HStack(spacing: 6) {
                    ActionButton(title: s.runtime.topUp ? "Stop Top Up" : "Top Up", symbol: "arrow.up.to.line", active: s.runtime.topUp) {
                        model.perform(.topUp(!s.runtime.topUp))
                    }
                    .help(.topUp)
                    if caps.discharge {
                        ActionButton(title: s.runtime.manualDischarge ? "Stop" : "Discharge", symbol: "arrow.down.to.line", active: s.runtime.manualDischarge) {
                            model.perform(.discharge(!s.runtime.manualDischarge))
                        }
                        .help(.discharge)
                    }
                    ActionButton(title: "Pause", symbol: "pause.circle", active: false) { model.perform(.pause) }
                        .help(.pause)
                    ActionButton(title: s.runtime.calibrationPhase == nil ? "Calibrate" : "Stop Cal.", symbol: "gauge.with.dots.needle.67percent",
                                 active: s.runtime.calibrationPhase != nil) {
                        model.perform(.calibrate(s.runtime.calibrationPhase == nil))
                    }
                    .help(.calibration)
                }
            }

            if let phase = s.runtime.calibrationPhase {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(.secondary)
                    Text(phase.title).font(.caption)
                    Spacer()
                    if let end = s.calibrationPhaseEndsAt {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text("\(Fmt.remaining(until: end, now: ctx.date)) left").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var limiterToggle: some View {
        Toggle(isOn: Binding(
            get: { model.config.limiterEnabled },
            set: { model.setLimiter($0) })) { HelpLabel("Charge Limiter", .limiter) }
        .toggleStyle(.switch).controlSize(.small)
    }

    // MARK: power flow

    private func powerFlow(_ s: SimmerStatus) -> some View {
        let b = s.battery
        let bw = b.batteryPowerW
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Power Flow", topic: .powerFlow)
            HStack(spacing: 6) {
                FlowNode(symbol: "powerplug.fill", value: b.externalConnected ? Fmt.watts(s.adapterPowerW) : "–", caption: "Adapter")
                    .help("Power coming in from the charger right now.")
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                FlowNode(symbol: "laptopcomputer", value: Fmt.watts(s.systemPowerW), caption: "Mac")
                    .help("Power your Mac is using right now (screen, chip, apps).")
                Image(systemName: bw >= 0 ? "arrow.right" : "arrow.left").foregroundStyle(.secondary)
                    .opacity(abs(bw) < 0.05 ? 0.3 : 1)
                FlowNode(symbol: MenuBarLabel.batterySymbol(b.percent), value: String(format: "%+.1f W", bw),
                         caption: abs(bw) < 0.05 ? "Idle" : (bw > 0 ? "Charging" : "Discharging"))
                    .help("Power going into the battery (+) or coming out of it (−). Near 0 means the battery is resting at the limit.")
            }
            if b.externalConnected {
                Text([b.adapterName.isEmpty ? "Power adapter" : b.adapterName, b.adapterWatts > 0 ? "\(b.adapterWatts) W" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: battery stats

    private var batteryStats: some View {
        let b = model.battery
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                BatteryTile(symbol: "thermometer.medium", value: Fmt.temp(status?.temperatureC ?? b.temperatureC),
                            caption: "Temperature", topic: .temperature)
                BatteryTile(symbol: "heart.fill", value: Fmt.percent(b.healthPercent), caption: "Health", topic: .health)
                BatteryTile(symbol: "arrow.triangle.2.circlepath", value: "\(b.cycleCount)", caption: "Cycles", topic: .cycleCount)
            }
        }
    }

    // MARK: power modes

    private func powerModes(_ s: SimmerStatus) -> some View {
        let pm = s.powerModes
        return VStack(alignment: .leading, spacing: 4) {
            SectionTitle("Power Mode", topic: .lowPowerMode)
            HStack {
                Label("Low Power", systemImage: "leaf").font(.callout).help(.lowPowerMode)
                Spacer()
                ScopeToggle(title: "Battery", isOn: pm.lowPowerBattery) { model.perform(.setLowPowerMode($0, .battery)) }
                ScopeToggle(title: "Charger", isOn: pm.lowPowerCharger) { model.perform(.setLowPowerMode($0, .charger)) }
            }
            if pm.highPowerSupported {
                HStack {
                    Label("High Power", systemImage: "hare").font(.callout).help(.highPowerMode)
                    InfoButton(.highPowerMode)
                    Spacer()
                    ScopeToggle(title: "Battery", isOn: pm.highPowerBattery) { model.perform(.setHighPowerMode($0, .battery)) }
                    ScopeToggle(title: "Charger", isOn: pm.highPowerCharger) { model.perform(.setHighPowerMode($0, .charger)) }
                }
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: { Label("Settings…", systemImage: "gearshape") }
            Button { open(.history) } label: { Label("History", systemImage: "chart.xyaxis.line") }
                .help(.history)
            Spacer()
            Button { open(.panel) } label: { Image(systemName: "slider.horizontal.3") }
                .help("Customize the panel: show, hide and reorder sections")
                .accessibilityLabel("Customize panel")
            Button { model.perform(.sleepNow) } label: { Image(systemName: "moon.zzz") }
                .help(.sleepNow).disabled(!model.connected)
            Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power") }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}

// MARK: - small components

struct SectionTitle: View {
    let text: String
    let topic: HelpTopic?
    init(_ text: String, topic: HelpTopic? = nil) { self.text = text; self.topic = topic }
    var body: some View {
        HStack(spacing: 4) {
            Text(text.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            if let topic { InfoButton(topic) }
        }
    }
}

/// Compact stat for the first-look panel; details live in Settings → Battery History.
struct BatteryTile: View {
    let symbol: String, value: String, caption: String
    let topic: HelpTopic
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit().weight(.semibold))
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .help(topic)
    }
}

struct StatRow: View {
    let symbol: String, title: String, value: String
    let topic: HelpTopic?
    init(_ symbol: String, _ title: String, _ value: String, topic: HelpTopic? = nil) {
        self.symbol = symbol; self.title = title; self.value = value; self.topic = topic
    }
    var body: some View {
        HStack {
            Label(title, systemImage: symbol).labelStyle(FixedIconLabelStyle())
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.callout)
        .contentShape(Rectangle())
        .help(topic?.tooltip ?? "")
    }
}

struct FixedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.frame(width: 18).foregroundStyle(.secondary)
            configuration.title
        }
    }
}

struct ActionButton: View {
    let title: String, symbol: String, active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.white : Color.primary)
        .background(RoundedRectangle(cornerRadius: 8).fill(active ? Color.accentColor : Color.primary.opacity(0.07)))
    }
}

struct FlowNode: View {
    let symbol: String, value: String, caption: String
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 16)).frame(height: 18)
            Text(value).font(.caption.monospacedDigit().weight(.medium))
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ScopeToggle: View {
    let title: String, isOn: Bool
    let set: (Bool) -> Void
    var body: some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: set))
            .toggleStyle(.button).controlSize(.small)
    }
}

struct Banner<Actions: View>: View {
    let symbol: String, tint: Color, title: String, message: String
    @ViewBuilder let actions: () -> Actions
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                actions().controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.12)))
    }
}

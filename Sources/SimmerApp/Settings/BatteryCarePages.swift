import SwiftUI
import SimmerShared

// MARK: - Charging

struct ChargingPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let c = model.config
        let caps = UICapabilities(model.status)
        SettingsForm(page: .charging, model: model, requiresHelper: true) {
            if caps.limitOnly {
                Section { LimitOnlyNote() }
            }
            Section {
                SettingToggle("Sailing mode", caption: "Let the battery drift below the limit before it charges again.",
                              topic: .sailing, isOn: model.binding(\.sailingEnabled))
                    .disabled(caps.limitOnly)
                StepperRow(value: model.binding(\.sailingLevel), range: 1...20, step: 1, text: "\(c.sailingLevel)%") {
                    Text("Drift allowance")
                }
                .disabled(!c.sailingEnabled)
                .help("How far the battery may drift below the limit before charging starts again. 5% is a good start.")
            } header: {
                Text("Sailing")
            } footer: {
                SectionCaption(c.sailingEnabled
                    ? "The battery floats between \(max(0, c.chargeLimit - c.sailingLevel))% and \(c.chargeLimit)%. Fewer small top-ups mean less wear."
                    : "Without sailing, the battery tops up every time it drops 1% below the limit.")
            }

            Section {
                SettingToggle("Heat protection", caption: "Pause charging while the battery is hot.",
                              topic: .heatProtection, isOn: model.binding(\.heatProtectionEnabled))
                StepperRow(value: model.binding(\.heatThresholdC), range: 25...50, step: 1, text: Fmt.temp(c.heatThresholdC)) {
                    Text("Pause charging at")
                }
                .disabled(!c.heatProtectionEnabled)
                .help("Charging pauses at this battery temperature. 35 °C suits most people; lower is gentler but pauses more often.")
            } header: {
                Text("Temperature")
            } footer: {
                SectionCaption(String(format: "Charging continues when the battery cools below %.0f °C.",
                                      c.heatThresholdC - c.heatResumeDeltaC))
            }

            Section {
                Picker(selection: model.binding(\.chargeControl)) {
                    ForEach(ChargeControlMode.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: { HelpLabel("Charge control", .chargeControl) }
                if let s = model.status {
                    Label(s.usingNativeLimit
                          ? "Now: macOS Charge Limit" + (s.chargeControlBlocked ? " (macOS blocks direct control)" : "")
                          : (s.chargeControlBlocked ? "Now: direct control is blocked by macOS" : "Now: Simmer direct control"),
                          systemImage: s.usingNativeLimit ? "gearshape.2" : "cpu")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Charge Control")
            } footer: {
                SectionCaption("Automatic uses Simmer's direct control and switches to the macOS Charge Limit if macOS blocks it (expected on macOS 27). The macOS limit only holds 80–100% in steps and has no discharge, sailing or heat pause.")
            }

            Section("Discharge & Quit") {
                SettingToggle("Automatic discharge", caption: "Drain to the limit while plugged in, when the battery is above it.",
                              topic: .automaticDischarge, isOn: model.binding(\.automaticDischarge))
                    .disabled(model.status != nil && !caps.discharge)
                SettingToggle("Keep the limit when Simmer quits", caption: "Charging stays blocked while the helper is stopped.",
                              topic: .keepLimit, isOn: model.binding(\.keepLimitWhenQuit))
            }
        }
    }
}

// MARK: - Sleep

struct SleepPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsForm(page: .sleep, model: model, requiresHelper: true) {
            Section("While Charging") {
                SettingToggle("Stop charging when sleeping",
                              caption: "Blocks charging before sleep, so the battery cannot pass the limit overnight.",
                              topic: .stopChargingWhenSleeping, isOn: model.binding(\.stopChargingWhenSleeping))
                SettingToggle("Stay awake until the limit is reached",
                              caption: "Delays sleep while the battery charges toward the limit.",
                              topic: .disableSleepUntilLimit, isOn: model.binding(\.disableSleepUntilLimit))
            }
            Section("While Discharging") {
                SettingToggle("Stay awake with the lid closed",
                              caption: "Keeps external displays on during a discharge (pmset disablesleep).",
                              topic: .clamshellAwake, isOn: model.binding(\.preventClamshellSleepWhileDischarging))
            }
        }
    }
}

// MARK: - Calibration

struct CalibrationPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsForm(page: .calibration, model: model, requiresHelper: true) {
            if UICapabilities(model.status).limitOnly {
                Section {
                    Label("Calibration needs on-demand charge control, which this Mac does not offer. " + UICapabilities.limitOnlyMessage,
                          systemImage: "info.circle")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .help(.capabilityLimitOnly)
                }
            }
            Section {
                LabeledContent("Last calibration") {
                    if let d = model.status?.runtime.lastCalibration {
                        Text(d.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Text("Never").foregroundStyle(.secondary)
                    }
                }
                if let s = model.status, let phase = s.runtime.calibrationPhase {
                    LabeledContent("Current step", value: phase.title)
                    if let end = s.calibrationPhaseEndsAt {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            LabeledContent("Time remaining", value: Fmt.remaining(until: end, now: ctx.date))
                                .monospacedDigit()
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Stop Calibration") { model.perform(.calibrate(false)) }
                    }
                } else {
                    HStack {
                        SectionCaption("Keep the charger connected. It takes several hours.")
                        Spacer()
                        Button("Start Calibration") { model.perform(.calibrate(true)) }
                            .help(.calibration)
                            .disabled(UICapabilities(model.status).limitOnly)
                    }
                }
            } header: {
                HelpLabel("Status", .calibration)
            }

            Section("Options") {
                StepperRow(value: model.binding(\.calibrationHoldMinutes), range: 0...240, step: 15,
                           text: "\(model.config.calibrationHoldMinutes) min") {
                    HelpLabel("Hold at 100% for", .calibrationHold)
                }
                StepperRow(value: model.binding(\.calibrationDischargeTo), range: 5...50, step: 5,
                           text: "\(model.config.calibrationDischargeTo)%") {
                    HelpLabel("Discharge down to", .calibrationDischargeTo)
                }
            }

            Section {
                CalibrationSteps(dischargeTo: model.config.calibrationDischargeTo, current: model.status?.runtime.calibrationPhase)
            } header: {
                Text("How It Works")
            } footer: {
                SectionCaption("The percentage drifts over time. A full cycle lets the battery chip re-learn its real capacity. Once a month is enough.")
            }
        }
    }
}

/// The six calibration steps, with the current one highlighted.
struct CalibrationSteps: View {
    let dischargeTo: Int
    let current: CalibrationPhase?

    private var steps: [(CalibrationPhase, String, String)] {
        [(.chargeToFull, "bolt.fill", "Charge to 100%"),
         (.holdFull, "hourglass", "Hold"),
         (.dischargeLow, "arrow.down", "Drain to \(dischargeTo)%"),
         (.chargeToFullAgain, "bolt.fill", "Charge to 100%"),
         (.holdFullAgain, "hourglass", "Hold"),
         (.returnToLimit, "target", "Back to limit")]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                let active = step.0 == current
                VStack(spacing: 5) {
                    Image(systemName: step.1)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? Color.white : Color.teal)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(active ? AnyShapeStyle(Color.teal) : AnyShapeStyle(Color.teal.opacity(0.15))))
                    Text(step.2)
                        .font(.caption2.weight(active ? .semibold : .regular))
                        .foregroundStyle(active ? .primary : .secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                if i < steps.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - MagSafe LED

struct LEDPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsForm(page: .led, model: model, requiresHelper: true) {
            if model.status != nil, !UICapabilities(model.status).led {
                Section {
                    Label("This Mac has no controllable MagSafe LED.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Picker(selection: Binding(
                    get: { model.config.ledMode },
                    set: { mode in model.updateConfig { $0.ledMode = mode }; model.perform(.setLED(mode)) })) {
                    Text("System default").tag(LEDMode.system)
                    Text("Smart: orange while charging, green at the limit").tag(LEDMode.smart)
                    Text("Always off").tag(LEDMode.alwaysOff)
                    Text("Custom: choose a color for each state").tag(LEDMode.custom)
                } label: { HelpLabel("LED mode", .ledMode) }
                .pickerStyle(.radioGroup)
                SettingToggle("Blink orange during discharge", caption: "Smart mode only.",
                              topic: .blinkDischarge, isOn: model.binding(\.blinkOrangeDuringDischarge))
                    .disabled(model.config.ledMode != .smart)
            } header: {
                Text("Mode")
            } footer: {
                SectionCaption("The LED is lit only while the charger is connected.")
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(LEDPattern.allCases, id: \.self) { p in
                        Button {
                            model.perform(.ledNotify(p, repeats: 3))
                        } label: {
                            Label {
                                Text(p.title)
                            } icon: {
                                Image(systemName: Self.patternSymbol(p)).foregroundStyle(Self.patternTint(p))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .help("Play \"\(p.title)\" three times on the MagSafe LED")
                    }
                }
                .disabled(!model.battery.externalConnected || !UICapabilities(model.status).led)
                LabeledContent {
                    Text("simmerctl led blink heartbeat 3").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                } label: { HelpLabel("From Terminal", .ledBlinkCommand) }
            } header: {
                HelpLabel("Test Notifications", .ledTest)
            } footer: {
                SectionCaption(model.battery.externalConnected
                    ? "The pattern plays three times, then the LED returns to its mode. In Terminal: simmerctl led blink green | orange | alternate | heartbeat | level [repeats 1–10]. Use it in scripts, for example when a long job is done."
                    : "Connect the MagSafe charger to test the LED.")
            }

            if model.config.ledMode == .custom {
                Section {
                    ForEach(LEDCustomColors.editableStates, id: \.0) { state, kp in
                        Picker(selection: model.binding((\SimmerConfig.ledCustom).appending(path: kp))) {
                            ForEach(LEDColor.allCases, id: \.self) { c in
                                Label(c.title, systemImage: Self.symbol(c)).tag(c)
                            }
                        } label: {
                            HStack {
                                Text(state.title)
                                if model.status?.state == state {
                                    Text("Now").font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(.tint.opacity(0.2), in: Capsule())
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        HelpLabel("Custom Colors", .ledCustom)
                        Spacer()
                        Button("Reset to Defaults") { model.updateConfig { $0.ledCustom = LEDCustomColors() } }
                            .buttonStyle(.borderless).controlSize(.small)
                    }
                } footer: {
                    SectionCaption("\"System default\" hands the LED back to macOS for that state.")
                }
            }
        }
    }

    static func patternSymbol(_ p: LEDPattern) -> String {
        switch p {
        case .blinkGreen: return "circle.fill"
        case .blinkOrange: return "circle.fill"
        case .alternate: return "circle.lefthalf.filled"
        case .heartbeat: return "heart.fill"
        case .chargeLevel: return "battery.75percent"
        }
    }

    static func patternTint(_ p: LEDPattern) -> AnyShapeStyle {
        switch p {
        case .blinkGreen: return AnyShapeStyle(Color.green)
        case .blinkOrange: return AnyShapeStyle(Color.orange)
        case .alternate: return AnyShapeStyle(LinearGradient(colors: [.green, .orange], startPoint: .leading, endPoint: .trailing))
        case .heartbeat: return AnyShapeStyle(Color.orange)
        case .chargeLevel: return AnyShapeStyle(Color.green)
        }
    }

    static func symbol(_ c: LEDColor) -> String {
        switch c {
        case .system: return "gearshape"
        case .off: return "circle.slash"
        case .green, .orange: return "circle.fill"
        case .orangeBlinkSlow, .orangeBlinkFast: return "circle.dotted"
        }
    }
}

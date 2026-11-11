import SwiftUI
import SimmerShared

struct SmartChargingPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var insights: InsightsModel = .shared

    var body: some View {
        let c = model.config
        SettingsForm(page: .smartCharging, model: model, requiresHelper: true) {
            if let s = model.status {
                Section {
                    ActiveLimitSummary(status: s, userLimit: c.chargeLimit, limiterOn: c.limiterEnabled)
                }
            }

            // MARK: desk mode
            Section {
                SettingToggle("Desk mode", caption: "Hold a lower level while the Mac lives on the desk.",
                              topic: .deskMode, isOn: model.binding(\.deskModeEnabled))
                Group {
                    StepperRow(value: model.binding(\.deskModeLimit), range: 20...max(20, c.chargeLimit), step: 5,
                               text: "\(min(c.deskModeLimit, c.chargeLimit))%") {
                        HelpLabel("Desk limit", .deskModeLimit)
                    }
                    Picker(selection: model.binding(\.deskModeTrigger)) {
                        Text("Lid closed on the charger").tag(DeskModeTrigger.clamshell)
                        Text("Plugged in for a long time").tag(DeskModeTrigger.pluggedHours)
                        Text("Either of these").tag(DeskModeTrigger.clamshellOrPluggedHours)
                    } label: { HelpLabel("Start when", .deskModeTrigger) }
                    if c.deskModeTrigger != .clamshell {
                        StepperRow(value: model.binding(\.deskModeAfterHours), range: 0.5...24, step: 0.5,
                                   text: DurationText.hours(c.deskModeAfterHours)) {
                            HelpLabel("Plugged in for", .deskModeHours)
                        }
                    }
                }
                .disabled(!c.deskModeEnabled)
            } header: {
                Text("Desk Mode")
            } footer: {
                SectionCaption("Why: a battery that sits full and warm on the charger for weeks ages faster and can swell in rare cases. A lower level while you work at the desk is the gentlest choice. Simmer returns to your \(c.chargeLimit)% limit when you unplug.")
            }

            // MARK: smart top-up
            Section {
                SettingToggle("Smart \"ready by\" top-up", caption: "Charge to 100% just before you usually unplug.",
                              topic: .smartTopUp, isOn: model.binding(\.smartTopUpEnabled))
                Group {
                    StepperRow(value: model.binding(\.smartTopUpLeadMinutes), range: 15...240, step: 15,
                               text: DurationText.hours(Double(c.smartTopUpLeadMinutes) / 60)) {
                        HelpLabel("Start before departure", .smartTopUpLead)
                    }
                    LabeledContent {
                        departureText
                    } label: { HelpLabel("Next departure", .departurePrediction) }
                }
                .disabled(!c.smartTopUpEnabled)
            } header: {
                Text("Ready By")
            } footer: {
                SectionCaption("Simmer learns from the battery history when you unplug on each weekday. It needs at least two similar days before it predicts anything.")
            }

            // MARK: cheap / green windows
            Section {
                SettingToggle("Cheap & green charging", caption: "Charge to the limit only inside your time windows.",
                              topic: .cheapCharging, isOn: model.binding(\.cheapChargingEnabled))
                Group {
                    StepperRow(value: model.binding(\.cheapFloorPercent), range: 20...100, step: 5,
                               text: "\(c.cheapFloorPercent)%") {
                        HelpLabel("Outside windows, charge to", .cheapFloor)
                    }
                    ForEach(Array(c.cheapWindows.enumerated()), id: \.offset) { i, w in
                        TimeWindowRow(window: w, canRemove: c.cheapWindows.count > 1,
                                      update: { nw in model.updateConfig { if $0.cheapWindows.indices.contains(i) { $0.cheapWindows[i] = nw } } },
                                      remove: { model.updateConfig { if $0.cheapWindows.indices.contains(i) { $0.cheapWindows.remove(at: i) } } })
                    }
                    HStack {
                        Spacer()
                        Button {
                            model.updateConfig { $0.cheapWindows.append(TimeWindow(startHour: 11, startMinute: 0, endHour: 15, endMinute: 0)) }
                        } label: { Label("Add Window", systemImage: "plus") }
                        .disabled(c.cheapWindows.count >= 6)
                        .help(.cheapWindows)
                    }
                }
                .disabled(!c.cheapChargingEnabled)
            } header: {
                HelpLabel("Cheap & Green Windows", .cheapWindows)
            } footer: {
                SectionCaption("Why: grid electricity is often cheaper at night and cleaner when solar or wind power is high. Outside the windows Simmer keeps a \(c.cheapFloorPercent)% reserve, so you are never stuck with an empty battery.")
            }
        }
    }

    @ViewBuilder private var departureText: some View {
        if case .smartTopUp(let d)? = model.status?.limitReason {
            Text("\(d.formatted(.dateTime.weekday(.wide).hour().minute())) · charging now").foregroundStyle(.green)
        } else if let d = DeparturePredictor.nextDeparture(samples: insights.history?.samples ?? [], now: Date()) {
            Text(d.formatted(.dateTime.weekday(.wide).hour().minute()))
        } else {
            Text("No pattern yet").foregroundStyle(.secondary)
        }
    }
}

/// The limit the helper applies right now and why.
struct ActiveLimitSummary: View {
    let status: SimmerStatus
    let userLimit: Int
    let limiterOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.limitReasonSymbol)
                .font(.system(size: 22)).foregroundStyle(.tint).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                HelpLabel(limiterOn ? "Active limit: \(status.effectiveLimit)%" : "Limiter is off", .effectiveLimit)
                    .font(.headline)
                Text(status.limitReasonText(userLimit: userLimit) ?? "Your own \(userLimit)% limit applies.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct TimeWindowRow: View {
    let window: TimeWindow
    let canRemove: Bool
    let update: (TimeWindow) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock").foregroundStyle(.secondary)
            DatePicker("From", selection: time(\.startHour, \.startMinute), displayedComponents: .hourAndMinute)
                .labelsHidden().fixedSize()
            Text("to").foregroundStyle(.secondary)
            DatePicker("To", selection: time(\.endHour, \.endMinute), displayedComponents: .hourAndMinute)
                .labelsHidden().fixedSize()
            if wraps {
                Text("next day").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.red)
                .disabled(!canRemove)
                .help("Remove this window")
        }
    }

    private var wraps: Bool {
        window.endHour * 60 + window.endMinute <= window.startHour * 60 + window.startMinute
    }

    private func time(_ h: WritableKeyPath<TimeWindow, Int>, _ m: WritableKeyPath<TimeWindow, Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: window[keyPath: h], minute: window[keyPath: m], second: 0, of: Date()) ?? Date()
        }, set: { d in
            var w = window
            let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
            w[keyPath: h] = comps.hour ?? 0
            w[keyPath: m] = comps.minute ?? 0
            update(w)
        })
    }
}

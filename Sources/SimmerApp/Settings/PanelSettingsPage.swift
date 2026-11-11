import SwiftUI
import SimmerShared

/// Show, hide and reorder the menu bar panel sections, and edit the quick-limit presets.
struct PanelSettingsPage: View {
    @ObservedObject var store: PanelLayoutStore = .shared
    @State private var newPreset = 90

    var body: some View {
        let layout = store.layout
        Form {
            Section { PageHeader(page: .panel) }

            Section {
                Picker(selection: Binding(get: { layout.limitControl ?? .knob }, set: { store.layout.limitControl = $0 })) {
                    ForEach(LimitControlStyle.allCases) { Text($0.title).tag($0) }
                } label: { HelpLabel("Limit control", .limitControl) }
                .pickerStyle(.segmented)
                .fixedSize()
                Toggle(isOn: Binding(get: { layout.showsIllustration }, set: { store.layout.showIllustration = $0 })) {
                    HelpLabel("Show battery illustration", .batteryIllustration)
                }
            } header: {
                Text("Look")
            } footer: {
                SectionCaption("Turn the knob by dragging around it, scrolling over it or with the arrow keys. The jar animates only while the panel is open.")
            }

            Section {
                ForEach(Array(layout.order.enumerated()), id: \.element) { i, section in
                    PanelSectionRow(section: section, index: i, count: layout.order.count,
                                    visible: !layout.hidden.contains(section),
                                    setVisible: { store.setVisible(section, $0) },
                                    move: { store.move(section, by: $0) })
                }
            } header: {
                HStack {
                    HelpLabel("Sections", .panelLayout)
                    Spacer()
                    Button("Reset") { store.reset() }
                        .buttonStyle(.borderless).controlSize(.small)
                        .help("Show all sections in the default order and restore 60 / 80 / 100")
                }
            } footer: {
                SectionCaption("Some sections appear only when they have something to show, for example the charger report while plugged in.")
            }

            Section {
                HStack(spacing: 8) {
                    ForEach(layout.limitPresets, id: \.self) { p in
                        HStack(spacing: 4) {
                            Text("\(p)%").monospacedDigit().font(.callout.weight(.medium))
                            Button {
                                store.layout.limitPresets.removeAll { $0 == p }
                            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.borderless)
                            .disabled(layout.limitPresets.count <= 1)
                            .help("Remove \(p)%")
                        }
                        .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    Spacer()
                }
                LabeledContent {
                    HStack(spacing: 6) {
                        Text("\(newPreset)%").monospacedDigit()
                        Stepper("", value: $newPreset, in: 20...100, step: 5).labelsHidden()
                        Button("Add") { store.layout.limitPresets.append(newPreset) }
                            .disabled(layout.limitPresets.contains(newPreset) || layout.limitPresets.count >= PanelLayout.maxPresets)
                    }
                } label: { Text("New quick limit") }
            } header: {
                HelpLabel("Quick Limits", .limitPresets)
            } footer: {
                SectionCaption("Up to \(PanelLayout.maxPresets) buttons under the limit control in the panel. Click one to set that limit.")
            }
        }
        .formStyle(.grouped)
    }
}

struct PanelSectionRow: View {
    let section: PanelSection
    let index: Int
    let count: Int
    let visible: Bool
    let setVisible: (Bool) -> Void
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { visible }, set: setVisible))
                .labelsHidden().toggleStyle(.checkbox)
                .help(visible ? "Hide this section" : "Show this section")
            Image(systemName: section.symbol)
                .foregroundStyle(visible ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(section.title).foregroundStyle(visible ? .primary : .secondary)
                    InfoButton(section.topic)
                }
                Text(section.caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0).help("Move up")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == count - 1).help("Move down")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 1)
    }
}

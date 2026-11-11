import SwiftUI
import AppKit
import SimmerShared

// MARK: - Pages

/// One page of the Settings window. The raw value is stored in UserDefaults (`SettingsPage.storageKey`).
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, panel
    case charging, smartCharging, sleep, calibration
    case led, charger, usb
    case schedule, shortcuts
    case history, batteryHealth, sessions, energy, componentPower, sleepDrain, sleepBlockers
    case conflicts, passport, backup
    case helper

    static let storageKey = "settingsPage"

    /// Sidebar groups, top to bottom. A nil title is a group without a header.
    static let sidebar: [(title: String?, pages: [SettingsPage])] = [
        (nil, [.general, .panel]),
        ("Battery Care", [.charging, .smartCharging, .sleep, .calibration]),
        ("Device", [.led, .charger, .usb]),
        ("Automation", [.schedule, .shortcuts]),
        ("Insights", [.history, .batteryHealth, .sessions, .energy, .componentPower, .sleepDrain, .sleepBlockers]),
        ("Tools", [.conflicts, .passport, .backup]),
        (nil, [.helper]),
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .panel: return "Menu Bar Panel"
        case .charging: return "Charging"
        case .smartCharging: return "Smart Charging"
        case .sleep: return "Sleep"
        case .calibration: return "Calibration"
        case .led: return "MagSafe LED"
        case .charger: return "Charger"
        case .usb: return "USB Devices"
        case .schedule: return "Schedule"
        case .shortcuts: return "Shortcuts"
        case .history: return "Battery History"
        case .batteryHealth: return "Cells & Stress"
        case .sessions: return "Battery Sessions"
        case .energy: return "Energy"
        case .componentPower: return "Chip Power"
        case .sleepDrain: return "Sleep Drain"
        case .sleepBlockers: return "Won’t Sleep?"
        case .conflicts: return "Conflict Doctor"
        case .passport: return "Battery Passport"
        case .backup: return "Backup & Restore"
        case .helper: return "Helper & Updates"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .panel: return "menubar.rectangle"
        case .charging: return "bolt.fill"
        case .smartCharging: return "sparkles"
        case .sleep: return "moon.fill"
        case .calibration: return "gauge.with.dots.needle.67percent"
        case .led: return "light.max"
        case .charger: return "powerplug.fill"
        case .usb: return "cable.connector"
        case .schedule: return "calendar"
        case .shortcuts: return "command"
        case .history: return "chart.xyaxis.line"
        case .batteryHealth: return "stethoscope"
        case .sessions: return "battery.75percent"
        case .energy: return "flame.fill"
        case .componentPower: return "cpu"
        case .sleepDrain: return "moon.zzz.fill"
        case .sleepBlockers: return "eye.fill"
        case .conflicts: return "cross.case.fill"
        case .passport: return "doc.text.fill"
        case .backup: return "externaldrive.fill"
        case .helper: return "wrench.and.screwdriver"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .panel: return .blue
        case .charging: return .green
        case .smartCharging: return .mint
        case .sleep: return .indigo
        case .calibration: return .teal
        case .led: return .orange
        case .charger: return .yellow
        case .usb: return .cyan
        case .schedule: return .red
        case .shortcuts: return .purple
        case .history: return .blue
        case .batteryHealth: return .pink
        case .sessions: return .green
        case .energy: return .orange
        case .componentPower: return .purple
        case .sleepDrain: return .indigo
        case .sleepBlockers: return .brown
        case .conflicts: return .red
        case .passport: return .teal
        case .backup: return .gray
        case .helper: return .gray
        }
    }

    /// One plain-language line under the page title.
    var summary: String {
        switch self {
        case .general: return "The charge limit, the menu bar icon and how Simmer starts."
        case .panel: return "Choose what the menu bar panel shows, in which order, and your quick limits."
        case .charging: return "Fine-tune how Simmer holds the battery at the limit."
        case .smartCharging: return "Let Simmer change the limit by itself: lower at the desk, full before you leave, cheap hours first."
        case .sleep: return "Keep the charge limit working while your Mac sleeps."
        case .calibration: return "Run a full charge cycle so the battery percentage stays accurate."
        case .led: return "Choose what the light on the MagSafe connector shows."
        case .charger: return "Is your charger strong enough for the way you use your Mac?"
        case .usb: return "Devices connected over USB and the power your Mac gives them."
        case .schedule: return "Run actions automatically at set times."
        case .shortcuts: return "Control Simmer from Shortcuts, Terminal and scripts."
        case .history: return "See how your battery charges, heats up and ages over time."
        case .batteryHealth: return "How hard the battery's life has been, and whether its cells are in balance."
        case .sessions: return "Every stretch on battery: how fast it drained and how much power the Mac used."
        case .energy: return "Which apps and processes use the most power right now."
        case .componentPower: return "Live power use of the processor, graphics, Neural Engine and memory."
        case .sleepDrain: return "How much battery your Mac loses while it sleeps, and what wakes it up."
        case .sleepBlockers: return "Apps and processes that keep your Mac from sleeping right now."
        case .conflicts: return "Find other charge limiters that can fight with Simmer, and remove them."
        case .passport: return "A one-page battery report as a PDF, useful when you sell or service your Mac."
        case .backup: return "Save your Simmer settings to a file and restore them later or on another Mac."
        case .helper: return "The background helper that controls charging, updates and app details."
        }
    }
}

// MARK: - Root

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage(SettingsPage.storageKey) private var pageRaw = SettingsPage.general.rawValue
    @State private var refresh: PageRefresh?

    private var page: SettingsPage { SettingsPage(rawValue: pageRaw) ?? .general }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: Binding(get: { page }, set: { if let p = $0 { pageRaw = p.rawValue } }))
                .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetail(page: page, model: model)
                .navigationTitle(page.title)
                .onPreferenceChange(PageRefreshKey.self) { r in
                    MainActor.assumeIsolated { refresh = r }
                }
                .toolbar {
                    if let refresh {
                        ToolbarItem(placement: .primaryAction) { PageRefreshControl(refresh: refresh) }
                    }
                }
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 640)
        .background(ResizableWindow(minSize: NSSize(width: 760, height: 520)))
    }
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsPage?

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsPage.sidebar.indices, id: \.self) { i in
                let group = SettingsPage.sidebar[i]
                if let title = group.title {
                    Section(title) { rows(group.pages) }
                } else {
                    Section { rows(group.pages) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func rows(_ pages: [SettingsPage]) -> some View {
        ForEach(pages) { page in
            SidebarRow(page: page).tag(page)
        }
    }
}

struct SidebarRow: View {
    let page: SettingsPage
    var body: some View {
        Label {
            Text(page.title)
        } icon: {
            PageIcon(page: page, size: 22)
        }
        .padding(.vertical, 1)
    }
}

/// The SF Symbol in a small colored rounded square, as in System Settings.
struct PageIcon: View {
    let page: SettingsPage
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: page.symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(page.tint.gradient))
            .accessibilityHidden(true)
    }
}

struct SettingsDetail: View {
    let page: SettingsPage
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch page {
            case .general: GeneralPage(model: model)
            case .panel: PanelSettingsPage()
            case .charging: ChargingPage(model: model)
            case .smartCharging: SmartChargingPage(model: model)
            case .sleep: SleepPage(model: model)
            case .calibration: CalibrationPage(model: model)
            case .led: LEDPage(model: model)
            case .charger: ChargerPage(model: model)
            case .usb: USBPage()
            case .schedule: SchedulePage(model: model)
            case .shortcuts: ShortcutsPage()
            case .history: HistoryPage(model: model)
            case .batteryHealth: BatteryHealthPage(model: model)
            case .sessions: SessionsPage(model: model)
            case .energy: EnergyPage(model: model)
            case .componentPower: ComponentPowerPage(model: model)
            case .sleepDrain: SleepDrainPage()
            case .sleepBlockers: SleepBlockersPage()
            case .conflicts: ConflictDoctorPage(model: model)
            case .passport: PassportPage(model: model)
            case .backup: BackupPage(model: model)
            case .helper: HelperPage(model: model)
            }
        }
        .id(page)
    }
}

// MARK: - Page building blocks

/// Large icon, title and one-line description at the top of a page.
struct PageHeader: View {
    let page: SettingsPage
    var body: some View {
        HStack(spacing: 14) {
            PageIcon(page: page, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title).font(.title3.weight(.semibold))
                Text(page.summary).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// A grouped Form with the page header on top. When `requiresHelper` is set and the helper is not reachable,
/// a note is shown under the header and the page content is disabled.
struct SettingsForm<Content: View>: View {
    let page: SettingsPage
    @ObservedObject var model: AppModel
    var requiresHelper = false
    @ViewBuilder var content: Content

    private var locked: Bool { requiresHelper && model.reachable != true }

    var body: some View {
        Form {
            Section { PageHeader(page: page) }
            if locked {
                Section { HelperRequiredNote(model: model) }
            }
            Group { content }
                .disabled(locked)
        }
        .formStyle(.grouped)
    }
}

/// Shown on pages whose settings live in the helper (daemon).
struct HelperRequiredNote: View {
    @ObservedObject var model: AppModel
    @AppStorage(SettingsPage.storageKey) private var pageRaw = SettingsPage.general.rawValue

    var body: some View {
        if model.reachable != true {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.reachable == nil ? "Connecting to the helper…" : "The helper is not connected")
                        .font(.callout.weight(.medium))
                    Text("These settings are read-only until the helper runs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Open Helper") { pageRaw = SettingsPage.helper.rawValue }
                    .help(.helper)
            }
        }
    }
}

/// A switch with a title, an optional one-line description, and the ⓘ help button.
struct SettingToggle: View {
    let title: String
    let caption: String?
    let topic: HelpTopic
    @Binding var isOn: Bool

    init(_ title: String, caption: String? = nil, topic: HelpTopic, isOn: Binding<Bool>) {
        self.title = title; self.caption = caption; self.topic = topic; _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                HelpLabel(title, topic)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .help(topic)
    }
}

/// A value with a stepper on the trailing side of the row.
struct StepperRow<V: Strideable, RowLabel: View>: View {
    let value: Binding<V>
    let range: ClosedRange<V>
    let step: V.Stride
    let text: String
    @ViewBuilder var label: RowLabel

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(text).monospacedDigit()
                Stepper("", value: value, in: range, step: step).labelsHidden()
            }
        } label: { label }
    }
}

/// Small caption text used under sections.
struct SectionCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Makes the Settings window resizable and sets its minimum size.
struct ResizableWindow: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView { Probe(minSize: minSize) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        let minSize: NSSize
        init(minSize: NSSize) { self.minSize = minSize; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            w.styleMask.insert(.resizable)
            w.contentMinSize = minSize
        }
    }
}

// MARK: - Status text shared by the panel-like summaries

extension AppModel {
    /// Short state title, for example "Charge Limit Reached".
    var stateTitle: String {
        guard let s = status else { return reachable == nil ? "Connecting…" : "Helper Unavailable" }
        if let p = s.runtime.calibrationPhase { return "Calibration: \(p.title)" }
        return s.state.title
    }

    var stateTint: Color {
        guard let s = status else { return reachable == nil ? .secondary : .orange }
        switch s.state {
        case .charging, .topUp: return .green
        case .limitReached, .sailing: return .blue
        case .discharging, .calibration: return .orange
        case .heatProtection: return .red
        case .limiterOff, .notPluggedIn: return .secondary
        case .unsupported: return .red
        }
    }
}

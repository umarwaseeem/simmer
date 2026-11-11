import SwiftUI
import SimmerShared

/// A block of the menu bar panel that the user can show, hide and reorder.
enum PanelSection: String, CaseIterable, Codable, Identifiable {
    case chargeControls, battery, chargerReport, powerFlow, topApps, powerModes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chargeControls: return "Charge controls"
        case .chargerReport: return "Charger report"
        case .powerFlow: return "Power flow"
        case .battery: return "Battery"
        case .topApps: return "Top energy apps"
        case .powerModes: return "Power mode"
        }
    }

    var symbol: String {
        switch self {
        case .chargeControls: return "slider.horizontal.3"
        case .chargerReport: return "powerplug.fill"
        case .powerFlow: return "bolt.horizontal.fill"
        case .battery: return "battery.75percent"
        case .topApps: return "list.number"
        case .powerModes: return "leaf.fill"
        }
    }

    var caption: String {
        switch self {
        case .chargeControls: return "Limiter switch, limit knob or slider, quick limits and actions"
        case .chargerReport: return "Is the charger strong enough? Shown while plugged in"
        case .powerFlow: return "Watts from the charger, into the Mac and the battery"
        case .battery: return "Temperature, health and cycles at a glance"
        case .topApps: return "The five apps that use the most power"
        case .powerModes: return "Low Power and High Power Mode switches"
        }
    }

    var topic: HelpTopic {
        switch self {
        case .chargeControls: return .chargeLimit
        case .chargerReport: return .chargerReport
        case .powerFlow: return .powerFlow
        case .battery: return .battery
        case .topApps: return .topApps
        case .powerModes: return .lowPowerMode
        }
    }
}

/// How the panel shows the charge limit control.
enum LimitControlStyle: String, Codable, CaseIterable, Identifiable {
    case knob, slider
    var id: String { rawValue }
    var title: String { self == .knob ? "Knob" : "Slider" }
}

/// Order, visibility and quick-limit presets of the menu bar panel. Stored as JSON in UserDefaults.
struct PanelLayout: Codable, Equatable {
    var order: [PanelSection] = PanelLayout.defaultOrder
    /// A calm first look: the limit controls, the power flow and the battery until the user adds more.
    var hidden: Set<PanelSection> = PanelLayout.defaultHidden
    var limitPresets: [Int] = PanelLayout.defaultPresets
    var version: Int? = PanelLayout.currentVersion
    /// Knob or slider for the charge limit. nil (older layouts) = knob.
    var limitControl: LimitControlStyle? = nil
    /// The glowing battery jar in the panel header. nil (older layouts) = shown.
    var showIllustration: Bool? = nil

    var usesKnob: Bool { (limitControl ?? .knob) == .knob }
    var showsIllustration: Bool { showIllustration ?? true }

    static let currentVersion = 3
    static let defaultOrder: [PanelSection] = [.chargeControls, .powerFlow, .battery, .chargerReport, .topApps, .powerModes]
    static let defaultHidden: Set<PanelSection> = [.chargerReport, .topApps, .powerModes]

    static let storageKey = "panelLayout"
    static let defaultPresets = [60, 80, 100]
    static let maxPresets = 5

    var visible: [PanelSection] { order.filter { !hidden.contains($0) } }

    /// Adds sections that a newer version introduced, removes duplicates and cleans the presets.
    mutating func normalize() {
        var seen = Set<PanelSection>()
        order = order.filter { seen.insert($0).inserted }
        for s in Self.defaultOrder where !seen.contains(s) { order.append(s) }
        limitPresets = Array(Set(limitPresets.map { min(100, max(20, $0)) })).sorted().prefix(Self.maxPresets).map { $0 }
        if limitPresets.isEmpty { limitPresets = Self.defaultPresets }
    }

    static func load(_ d: UserDefaults = .standard) -> PanelLayout {
        guard let data = d.data(forKey: storageKey), var l = try? JSONDecoder().decode(PanelLayout.self, from: data) else {
            return PanelLayout()
        }
        let v = l.version ?? 1
        if v < 2 {
            // Version 2 introduced the calm default panel: move older layouts to it once (keep the presets).
            l.order = defaultOrder
            l.hidden = defaultHidden
        } else if v < 3 {
            l.migrateToV3()
        }
        if v < currentVersion {
            l.version = currentVersion
            l.save(d)
        }
        l.normalize()
        return l
    }

    /// Version 3 shows the power flow by default: unhide it once and put it right after the charge controls.
    /// Every other choice (hidden sections, order, presets, look) stays.
    mutating func migrateToV3() {
        hidden.remove(.powerFlow)
        order.removeAll { $0 == .powerFlow }
        let at = order.firstIndex(of: .chargeControls).map { $0 + 1 } ?? 0
        order.insert(.powerFlow, at: at)
    }

    func save(_ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { d.set(data, forKey: Self.storageKey) }
    }
}

/// Shared, observable panel layout. The panel and the Settings page edit the same instance.
@MainActor
final class PanelLayoutStore: ObservableObject {
    static let shared = PanelLayoutStore()
    @Published var layout = PanelLayout.load() {
        didSet {
            var l = layout
            l.normalize()
            if l != layout { layout = l; return }
            if layout != oldValue { layout.save() }
        }
    }

    func move(_ s: PanelSection, by delta: Int) {
        guard let i = layout.order.firstIndex(of: s) else { return }
        let j = i + delta
        guard layout.order.indices.contains(j) else { return }
        layout.order.swapAt(i, j)
    }

    func setVisible(_ s: PanelSection, _ on: Bool) {
        if on { layout.hidden.remove(s) } else { layout.hidden.insert(s) }
    }

    /// Default sections and quick limits. The look choices (knob or slider, illustration) stay.
    func reset() {
        var l = PanelLayout()
        l.limitControl = layout.limitControl
        l.showIllustration = layout.showIllustration
        layout = l
    }
}

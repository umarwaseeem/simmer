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
        case .chargeControls: return "Limiter switch, slider, quick limits and actions"
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

/// Order, visibility and quick-limit presets of the menu bar panel. Stored as JSON in UserDefaults.
struct PanelLayout: Codable, Equatable {
    var order: [PanelSection] = PanelSection.allCases
    /// A calm first look: only the limit controls and the battery are shown until the user adds more.
    var hidden: Set<PanelSection> = PanelLayout.defaultHidden
    var limitPresets: [Int] = PanelLayout.defaultPresets
    var version: Int? = PanelLayout.currentVersion

    static let currentVersion = 2
    static let defaultHidden: Set<PanelSection> = [.chargerReport, .powerFlow, .topApps, .powerModes]

    static let storageKey = "panelLayout"
    static let defaultPresets = [60, 80, 100]
    static let maxPresets = 5

    var visible: [PanelSection] { order.filter { !hidden.contains($0) } }

    /// Adds sections that a newer version introduced, removes duplicates and cleans the presets.
    mutating func normalize() {
        var seen = Set<PanelSection>()
        order = order.filter { seen.insert($0).inserted }
        for s in PanelSection.allCases where !seen.contains(s) { order.append(s) }
        limitPresets = Array(Set(limitPresets.map { min(100, max(20, $0)) })).sorted().prefix(Self.maxPresets).map { $0 }
        if limitPresets.isEmpty { limitPresets = Self.defaultPresets }
    }

    static func load(_ d: UserDefaults = .standard) -> PanelLayout {
        guard let data = d.data(forKey: storageKey), var l = try? JSONDecoder().decode(PanelLayout.self, from: data) else {
            return PanelLayout()
        }
        // Version 2 introduced the calm default panel: move older layouts to it once (keep the presets).
        if (l.version ?? 1) < currentVersion {
            l.order = PanelSection.allCases
            l.hidden = defaultHidden
            l.version = currentVersion
            l.save(d)
        }
        l.normalize()
        return l
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

    func reset() { layout = PanelLayout() }
}

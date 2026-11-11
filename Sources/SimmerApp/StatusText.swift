import SwiftUI
import SimmerShared

/// What the UI may offer on this Mac. Older helpers do not send `capabilities`, so the legacy
/// `supportsDischarge` / `supportsLED` flags still count.
struct UICapabilities: Equatable {
    var discharge: Bool
    var led: Bool
    var limitOnly: Bool
    var limitPersistsWhenOff: Bool

    /// Top Up, sailing and calibration need on-demand charge control (not available with BCLM only).
    var timing: Bool { !limitOnly }

    init(_ s: SimmerStatus?) {
        guard let s else { discharge = true; led = true; limitOnly = false; limitPersistsWhenOff = false; return }
        let c = s.capabilities
        discharge = c.discharge || s.supportsDischarge
        led = c.led || s.supportsLED
        limitOnly = c.limitOnly || s.backend == .bclm
        limitPersistsWhenOff = c.limitPersistsWhenOff || s.backend == .bclm
    }

    static let limitOnlyMessage = "Limit only — this Mac keeps the limit even when off."
}

extension SimmerStatus {
    /// True when the effective limit differs from the user's own limit (desk mode, smart top-up, cheap windows).
    func limitDiffers(from userLimit: Int) -> Bool {
        limitReason != .user || effectiveLimit != userLimit
    }

    /// One plain sentence that explains the effective limit, or nil when the user's limit applies.
    func limitReasonText(userLimit: Int) -> String? {
        switch limitReason {
        case .user:
            return effectiveLimit != userLimit ? "Holding \(effectiveLimit)%" : nil
        case .deskMode:
            return "Desk mode: holding \(effectiveLimit)%"
        case .smartTopUp(let departure):
            return "Smart top-up: charging to \(effectiveLimit)% for \(departure.formatted(date: .omitted, time: .shortened))"
        case .waitingForCheapWindow(let start):
            return "Waiting for cheap window at \(start.formatted(date: .omitted, time: .shortened)) · holding \(effectiveLimit)%"
        }
    }

    var limitReasonSymbol: String {
        switch limitReason {
        case .user: return "target"
        case .deskMode: return "display"
        case .smartTopUp: return "sunrise.fill"
        case .waitingForCheapWindow: return "leaf.fill"
        }
    }

    var limitReasonTopic: HelpTopic {
        switch limitReason {
        case .user: return .effectiveLimit
        case .deskMode: return .deskMode
        case .smartTopUp: return .smartTopUp
        case .waitingForCheapWindow: return .cheapCharging
        }
    }

    /// The helper reports a different version than the one bundled with this app.
    var helperOutdated: Bool { helperVersion != Simmer.helperVersion }
}

extension ChargerReport.Rating {
    var tint: Color {
        switch self {
        case .none: return .secondary
        case .excellent: return .green
        case .good: return .teal
        case .limited: return .orange
        case .insufficient: return .red
        }
    }

    var title: String {
        switch self {
        case .none: return "No charger"
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .limited: return "Limited"
        case .insufficient: return "Too weak"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "powerplug"
        case .excellent: return "checkmark.seal.fill"
        case .good: return "checkmark.circle.fill"
        case .limited: return "exclamationmark.triangle.fill"
        case .insufficient: return "xmark.octagon.fill"
        }
    }
}

extension ChargerReport {
    /// The analyzer headline, or a plain fallback built from the adapter facts.
    func headlineOrFallback(battery b: BatterySnapshot) -> String {
        if !headline.isEmpty { return headline }
        guard b.externalConnected else { return "No charger connected" }
        let name = !adapterName.isEmpty ? adapterName : (b.adapterName.isEmpty ? "Power adapter" : b.adapterName)
        let w = negotiatedWatts > 0 ? negotiatedWatts : b.adapterWatts
        return w > 0 ? "\(name) · \(w) W" : name
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? Simmer.helperVersion
    }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}

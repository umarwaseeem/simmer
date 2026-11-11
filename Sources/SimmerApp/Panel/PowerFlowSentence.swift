import Foundation
import SimmerShared

/// One short sentence that says where the power goes right now, for the Power Flow card.
enum PowerFlowSentence {
    /// Battery power below this (in watts, either way) counts as "resting".
    static let idleW = 0.3

    static func text(status s: SimmerStatus?, battery b: BatterySnapshot) -> String {
        let bw = b.batteryPowerW
        let plugged = b.externalConnected
        if let s {
            if let phase = s.runtime.calibrationPhase { return "Calibrating: \(phase.title.lowercased())" }
            switch s.state {
            case .topUp:
                return bw > idleW ? "Top Up: charging to 100% once" : "Top Up: holding at 100% until you unplug"
            case .heatProtection:
                return "Charging paused to let the battery cool down"
            case .discharging:
                return "On battery while plugged in, down to \(s.effectiveLimit)%"
            default:
                break
            }
            if plugged && s.adapterDisabled {
                return "On battery while plugged in, down to \(s.effectiveLimit)%"
            }
        }
        guard plugged else { return "Running on battery" }
        if bw < -0.5 { return "The charger is too weak — the battery helps" }
        if bw > idleW { return "Charging the battery and powering your Mac" }
        // Plugged in and the battery is resting.
        if b.fullyCharged || b.percent >= 100 { return "On charger power — the battery is full" }
        guard let s else { return "On charger power — the battery is resting" }
        if s.usingNativeLimit && s.state != .limiterOff {
            return "On charger power — the macOS limit holds the battery"
        }
        switch s.state {
        case .limitReached, .sailing:
            return "On charger power — the battery rests at the limit"
        case .limiterOff, .charging:
            // Simmer allows charging, yet no current flows: macOS holds it (Optimized Battery Charging or its own limit).
            let target = s.state == .limiterOff ? 100 : s.effectiveLimit
            if !s.chargingInhibited && b.percent < target - 1 {
                return "macOS paused charging (Optimized Charging)"
            }
            return "On charger power — the battery is resting"
        default:
            return "On charger power — the battery is resting"
        }
    }

    /// "Charger 19.1 W → Mac 18.6 W · battery +0.4 W (charging)".
    static func breakdown(status s: SimmerStatus?, battery b: BatterySnapshot) -> String {
        var parts: [String] = []
        if b.externalConnected {
            parts.append("Charger " + (s?.adapterPowerW.map { String(format: "%.1f W", $0) } ?? "–"))
        }
        if let sys = s?.systemPowerW { parts.append(String(format: "Mac uses %.1f W", sys)) }
        let bw = b.batteryPowerW
        let dir = abs(bw) < idleW ? "resting" : (bw > 0 ? "charging" : "discharging")
        parts.append(String(format: "battery %+.1f W (%@)", bw, dir))
        if b.externalConnected, b.adapterWatts > 0 { parts.append("\(b.adapterWatts) W adapter") }
        return parts.joined(separator: " · ")
    }
}

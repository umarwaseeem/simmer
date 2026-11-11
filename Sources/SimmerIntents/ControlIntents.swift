import AppIntents
import Foundation
import SimmerShared

// Charging intents used by Shortcuts (app target) and by the interactive widget buttons (widget target).

struct SetChargeLimitIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Charge Limit"
    static var description = IntentDescription(
        "Sets the percentage at which Simmer stops charging the battery (20–100%).",
        categoryName: "Charging", searchKeywords: ["percentage", "limit", "battery", "charge"])
    static var openAppWhenRun: Bool = false
    #if SIMMER_WIDGET
    static var isDiscoverable: Bool = false
    #endif

    @Parameter(title: "Charge Limit", description: "The new charge limit in percent (20–100).",
               default: 80, inclusiveRange: (20, 100))
    var percent: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set the charge limit to \(\.$percent)%")
    }

    init() {}
    init(percent: Int) { self.percent = percent }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let v = min(100, max(20, percent))
        try await SimmerHelperAccess.perform(.setLimit(v))
        SimmerHelperAccess.reloadWidgets()
        return .result(value: v, dialog: "Charge limit set to \(v)%.")
    }
}

struct TopUpIntent: AppIntent {
    static var title: LocalizedStringResource = "Top Up"
    static var description = IntentDescription(
        "Charges the battery to 100% once, past the charge limit. Simmer returns to the limit when you unplug or turn Top Up off.",
        categoryName: "Charging", searchKeywords: ["full", "100", "charge"])
    static var openAppWhenRun: Bool = false
    #if SIMMER_WIDGET
    static var isDiscoverable: Bool = false
    #endif

    @Parameter(title: "Top Up", description: "Start or stop the top up.", default: true,
               displayName: Bool.IntentDisplayName(true: "Start", false: "Stop"))
    var enabled: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$enabled) Top Up")
    }

    init() {}
    init(enabled: Bool) { self.enabled = enabled }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SimmerHelperAccess.perform(.topUp(enabled))
        SimmerHelperAccess.reloadWidgets()
        return .result(dialog: enabled ? "Top Up started. The battery charges to 100%." : "Top Up stopped.")
    }
}

struct PauseChargingIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Charging"
    static var description = IntentDescription(
        "Holds the battery at its current level: sets the charge limit to the current percentage and stops Top Up and Discharge.",
        categoryName: "Charging", searchKeywords: ["hold", "pause", "stop"])
    static var openAppWhenRun: Bool = false
    #if SIMMER_WIDGET
    static var isDiscoverable: Bool = false
    #endif

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let b = BatterySnapshot.read()
        guard b.present else { throw SimmerIntentError.noBattery }
        try await SimmerHelperAccess.perform(.pause)
        SimmerHelperAccess.reloadWidgets()
        let v = min(100, max(20, b.percent))
        return .result(value: v, dialog: "Charging paused. The charge limit is now \(v)%.")
    }
}

struct DischargeIntent: AppIntent {
    static var title: LocalizedStringResource = "Discharge"
    static var description = IntentDescription(
        "Runs the Mac from the battery while the charger stays connected, down to the charge limit. Optionally sets a new limit first.",
        categoryName: "Charging", searchKeywords: ["drain", "battery", "discharge"])
    static var openAppWhenRun: Bool = false
    #if SIMMER_WIDGET
    static var isDiscoverable: Bool = false
    #endif

    @Parameter(title: "Discharge", description: "Start or stop discharging.", default: true,
               displayName: Bool.IntentDisplayName(true: "Start", false: "Stop"))
    var enabled: Bool

    @Parameter(title: "Down To", description: "Optional new charge limit (20–100%). Simmer discharges down to it.",
               inclusiveRange: (20, 100))
    var limit: Int?

    static var parameterSummary: some ParameterSummary {
        When(\.$enabled, .equalTo, true) {
            Summary("\(\.$enabled) discharging down to \(\.$limit)%")
        } otherwise: {
            Summary("\(\.$enabled) discharging")
        }
    }

    init() {}
    init(enabled: Bool) { self.enabled = enabled }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard enabled else {
            try await SimmerHelperAccess.perform(.discharge(false))
            SimmerHelperAccess.reloadWidgets()
            return .result(dialog: "Discharge stopped.")
        }
        if let limit {
            try await SimmerHelperAccess.perform(.setLimit(min(100, max(20, limit))))
        }
        try await SimmerHelperAccess.perform(.discharge(true))
        SimmerHelperAccess.reloadWidgets()
        if let limit {
            return .result(dialog: "Discharging down to \(min(100, max(20, limit)))%.")
        }
        return .result(dialog: "Discharging down to the charge limit.")
    }
}

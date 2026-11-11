import AppIntents
import Foundation
import SimmerShared

// Shortcuts actions that change charging or hardware state (app target only).
// Set Charge Limit, Top Up, Pause Charging and Discharge are in Sources/SimmerIntents (shared with the widget).

struct StartChargingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Charging"
    static var description = IntentDescription(
        "Charges the battery now, to 100%, past the charge limit. Stops a running discharge first. Same as Top Up.",
        categoryName: "Charging", searchKeywords: ["charge", "resume", "full"])
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SimmerHelperAccess.perform(.discharge(false))
        try await SimmerHelperAccess.perform(.topUp(true))
        SimmerHelperAccess.reloadWidgets()
        return .result(dialog: "Charging started. Simmer charges the battery to 100%.")
    }
}

struct StopChargingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Charging"
    static var description = IntentDescription(
        "Stops charging now: ends Top Up and holds the battery at the current percentage (the charge limit becomes the current level).",
        categoryName: "Charging", searchKeywords: ["stop", "hold", "inhibit"])
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let b = BatterySnapshot.read()
        guard b.present else { throw SimmerIntentError.noBattery }
        try await SimmerHelperAccess.perform(.topUp(false))
        try await SimmerHelperAccess.perform(.pause)
        SimmerHelperAccess.reloadWidgets()
        let v = min(100, max(20, b.percent))
        return .result(value: v, dialog: "Charging stopped. Simmer holds the battery at \(v)%.")
    }
}

struct CalibrateBatteryIntent: AppIntent {
    static var title: LocalizedStringResource = "Calibrate Battery"
    static var description = IntentDescription(
        "Starts or cancels the calibration cycle: charge to 100%, hold, discharge, charge to 100% again, then return to the charge limit. The charger must be connected.",
        categoryName: "Charging", searchKeywords: ["calibration", "recalibrate"])
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Calibration", default: true, displayName: Bool.IntentDisplayName(true: "Start", false: "Cancel"))
    var start: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$start) battery calibration")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SimmerHelperAccess.perform(.calibrate(start))
        SimmerHelperAccess.reloadWidgets()
        return .result(dialog: start ? "Calibration started. Keep the charger connected." : "Calibration cancelled.")
    }
}

struct SetLimiterIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Charge Limiter On or Off"
    static var description = IntentDescription(
        "Turns the charge limiter on or off. When it is off, the Mac charges to 100% as usual.",
        categoryName: "Charging", searchKeywords: ["enable", "disable", "limiter"])
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Limiter", default: true, displayName: Bool.IntentDisplayName(true: "On", false: "Off"))
    var enabled: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Turn the charge limiter \(\.$enabled)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SimmerHelperAccess.perform(.setLimiterEnabled(enabled))
        SimmerHelperAccess.reloadWidgets()
        return .result(dialog: enabled ? "Charge limiter on." : "Charge limiter off. The Mac charges to 100%.")
    }
}

struct SetMagSafeLEDIntent: AppIntent {
    static var title: LocalizedStringResource = "Set MagSafe LED"
    static var description = IntentDescription(
        "Chooses how the MagSafe LED behaves. Needs a Mac with a MagSafe port.",
        categoryName: "Hardware", searchKeywords: ["led", "light", "magsafe"])
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Mode", default: .smart)
    var mode: LEDModeOption

    static var parameterSummary: some ParameterSummary {
        Summary("Set the MagSafe LED to \(\.$mode)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SimmerHelperAccess.perform(.setLED(mode.mode))
        let name: String
        switch mode {
        case .system: name = "System"
        case .smart: name = "Smart"
        case .alwaysOff: name = "Always Off"
        case .custom: name = "Custom"
        }
        return .result(dialog: "MagSafe LED set to \(name).")
    }
}

struct BlinkMagSafeLEDIntent: AppIntent {
    static var title: LocalizedStringResource = "Blink MagSafe LED"
    static var description = IntentDescription(
        "Blinks the MagSafe LED as a notification. The LED then returns to its normal mode. The charger must be connected.",
        categoryName: "Hardware", searchKeywords: ["led", "notify", "flash", "magsafe"])
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Pattern", default: .blinkGreen)
    var pattern: LEDPatternOption

    @Parameter(title: "Repeats", description: "How many times to play the pattern (1–10).", default: 3, inclusiveRange: (1, 10))
    var repeats: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Blink the MagSafe LED with \(\.$pattern) \(\.$repeats) times")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SimmerHelperAccess.perform(.ledNotify(pattern.pattern, repeats: min(10, max(1, repeats))))
        return .result(dialog: "Blinking the MagSafe LED.")
    }
}

struct SetLowPowerModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Low Power Mode"
    static var description = IntentDescription(
        "Turns macOS Low Power Mode on or off, always or only on battery or on the power adapter.",
        categoryName: "Power Modes", searchKeywords: ["low power", "energy", "save"])
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Low Power Mode", default: true, displayName: Bool.IntentDisplayName(true: "On", false: "Off"))
    var enabled: Bool

    @Parameter(title: "Power Source", default: .all)
    var scope: PowerModeScopeOption

    static var parameterSummary: some ParameterSummary {
        Summary("Turn Low Power Mode \(\.$enabled) for \(\.$scope)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SimmerHelperAccess.perform(.setLowPowerMode(enabled, scope.scope), timeout: 15)
        return .result(dialog: enabled ? "Low Power Mode on." : "Low Power Mode off.")
    }
}

struct SetHighPowerModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set High Power Mode"
    static var description = IntentDescription(
        "Turns macOS High Power Mode on or off. Only some Macs support High Power Mode.",
        categoryName: "Power Modes", searchKeywords: ["high power", "performance", "fans"])
    static var openAppWhenRun: Bool = false

    @Parameter(title: "High Power Mode", default: true, displayName: Bool.IntentDisplayName(true: "On", false: "Off"))
    var enabled: Bool

    @Parameter(title: "Power Source", default: .all)
    var scope: PowerModeScopeOption

    static var parameterSummary: some ParameterSummary {
        Summary("Turn High Power Mode \(\.$enabled) for \(\.$scope)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SimmerHelperAccess.perform(.setHighPowerMode(enabled, scope.scope), timeout: 15)
        return .result(dialog: enabled ? "High Power Mode on." : "High Power Mode off.")
    }
}

struct SleepNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Sleep Now"
    static var description = IntentDescription(
        "Puts the Mac to sleep now. Simmer keeps the charge limit while the Mac sleeps.",
        categoryName: "Power Modes", searchKeywords: ["sleep", "suspend"])
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        do {
            try await SimmerHelperAccess.perform(.sleepNow, timeout: 4)
        } catch SimmerIntentError.helperNotResponding {
            // The Mac can go to sleep before the reply arrives.
        }
        return .result()
    }
}

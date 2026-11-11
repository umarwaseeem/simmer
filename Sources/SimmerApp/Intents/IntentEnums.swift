import AppIntents
import SimmerShared

// App Intents enums. They mirror the SimmerShared enums, so the App Intents metadata stays in this module.

enum LEDModeOption: String, AppEnum {
    case system, smart, alwaysOff, custom

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "MagSafe LED Mode"
    static var caseDisplayRepresentations: [LEDModeOption: DisplayRepresentation] = [
        .system: DisplayRepresentation(title: "System", subtitle: "macOS controls the LED"),
        .smart: DisplayRepresentation(title: "Smart", subtitle: "Orange while charging, green at the limit"),
        .alwaysOff: DisplayRepresentation(title: "Always Off", subtitle: "The LED stays dark"),
        .custom: DisplayRepresentation(title: "Custom", subtitle: "Your colors from Simmer settings"),
    ]

    var mode: LEDMode {
        switch self {
        case .system: return .system
        case .smart: return .smart
        case .alwaysOff: return .alwaysOff
        case .custom: return .custom
        }
    }
}

enum LEDPatternOption: String, AppEnum {
    case blinkGreen, blinkOrange, alternate, heartbeat, chargeLevel

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "LED Pattern"
    static var caseDisplayRepresentations: [LEDPatternOption: DisplayRepresentation] = [
        .blinkGreen: "Blink Green",
        .blinkOrange: "Blink Orange",
        .alternate: "Green and Orange",
        .heartbeat: "Heartbeat",
        .chargeLevel: DisplayRepresentation(title: "Charge Level", subtitle: "One blink per 10%"),
    ]

    var pattern: LEDPattern {
        switch self {
        case .blinkGreen: return .blinkGreen
        case .blinkOrange: return .blinkOrange
        case .alternate: return .alternate
        case .heartbeat: return .heartbeat
        case .chargeLevel: return .chargeLevel
        }
    }
}

enum PowerModeScopeOption: String, AppEnum {
    case all, battery, charger

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Power Source"
    static var caseDisplayRepresentations: [PowerModeScopeOption: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: "Always", subtitle: "On battery and on the charger"),
        .battery: "On Battery",
        .charger: "On Power Adapter",
    ]

    var scope: PowerModeScope {
        switch self {
        case .all: return .all
        case .battery: return .battery
        case .charger: return .charger
        }
    }
}

enum PowerReadingOption: String, AppEnum {
    case system, adapter, battery

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Power Reading"
    static var caseDisplayRepresentations: [PowerReadingOption: DisplayRepresentation] = [
        .system: DisplayRepresentation(title: "Mac", subtitle: "What the whole Mac uses"),
        .adapter: DisplayRepresentation(title: "Power Adapter", subtitle: "What comes in from the charger"),
        .battery: DisplayRepresentation(title: "Battery", subtitle: "Positive while charging, negative while discharging"),
    ]
}

enum PercentKindOption: String, AppEnum {
    case macOS, hardware

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Percentage Source"
    static var caseDisplayRepresentations: [PercentKindOption: DisplayRepresentation] = [
        .macOS: DisplayRepresentation(title: "macOS", subtitle: "The percentage in the menu bar"),
        .hardware: DisplayRepresentation(title: "Hardware", subtitle: "Raw charge / raw full capacity"),
    ]
}

enum TemperatureUnitOption: String, AppEnum {
    case celsius, fahrenheit

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Temperature Unit"
    static var caseDisplayRepresentations: [TemperatureUnitOption: DisplayRepresentation] = [
        .celsius: "Celsius",
        .fahrenheit: "Fahrenheit",
    ]
}

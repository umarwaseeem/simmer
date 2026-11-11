import AppIntents
import WidgetKit

// Options for the configurable widgets (Edit Widget). Hidden from Shortcuts.

enum PercentSourceOption: String, AppEnum {
    case macOS, hardware
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Percentage"
    static var caseDisplayRepresentations: [PercentSourceOption: DisplayRepresentation] = [
        .macOS: DisplayRepresentation(title: "macOS", subtitle: "The percentage in the menu bar"),
        .hardware: DisplayRepresentation(title: "Hardware", subtitle: "Raw charge / raw full capacity"),
    ]
}

struct BatteryStatusConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Battery Status"
    static var description = IntentDescription("Choose what the battery widget shows.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Show Limit Marker", default: true)
    var showLimitMarker: Bool

    @Parameter(title: "Show Time Remaining", default: true)
    var showTimeRemaining: Bool

    @Parameter(title: "Percentage", default: .macOS)
    var percentSource: PercentSourceOption

    init() {}
}

enum HistoryMetricOption: String, AppEnum {
    case charge, temperature, power, health
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    static var caseDisplayRepresentations: [HistoryMetricOption: DisplayRepresentation] = [
        .charge: "Charge",
        .temperature: "Temperature",
        .power: DisplayRepresentation(title: "Power", subtitle: "What the Mac uses"),
        .health: DisplayRepresentation(title: "Health", subtitle: "One value per day"),
    ]
}

enum HistoryRangeOption: String, AppEnum {
    case day, week, twoWeeks
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Range"
    static var caseDisplayRepresentations: [HistoryRangeOption: DisplayRepresentation] = [
        .day: "24 Hours",
        .week: "7 Days",
        .twoWeeks: "14 Days",
    ]

    var seconds: TimeInterval {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .twoWeeks: return 14 * 86_400
        }
    }

    var shortTitle: String {
        switch self {
        case .day: return "24 h"
        case .week: return "7 d"
        case .twoWeeks: return "14 d"
        }
    }
}

struct HistoryChartConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Battery History"
    static var description = IntentDescription("Choose the metric and the time range.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Metric", default: .charge)
    var metric: HistoryMetricOption

    @Parameter(title: "Range", default: .day)
    var range: HistoryRangeOption

    init() {}
}

enum TopAppsCountOption: String, AppEnum {
    case three, five, eight
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Number of Apps"
    static var caseDisplayRepresentations: [TopAppsCountOption: DisplayRepresentation] = [
        .three: "3", .five: "5", .eight: "8",
    ]
    var count: Int {
        switch self {
        case .three: return 3
        case .five: return 5
        case .eight: return 8
        }
    }
}

struct TopAppsConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Top Energy Apps"
    static var description = IntentDescription("Choose how many apps to list.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Apps", default: .five)
    var count: TopAppsCountOption

    init() {}
}

struct ControlsConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Charging Controls"
    static var description = IntentDescription("Choose the charge limit buttons.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "First Limit", default: 60, inclusiveRange: (20, 100))
    var limitA: Int

    @Parameter(title: "Second Limit", default: 80, inclusiveRange: (20, 100))
    var limitB: Int

    @Parameter(title: "Third Limit", default: 100, inclusiveRange: (20, 100))
    var limitC: Int

    init() {}

    var limits: [Int] { [limitA, limitB, limitC].map { min(100, max(20, $0)) } }
}

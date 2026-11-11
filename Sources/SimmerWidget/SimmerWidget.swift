import SwiftUI
import WidgetKit

/// Desktop widgets for Simmer. They read the world-readable files that simmerd writes; only the
/// Charging Controls buttons talk to the helper (App Intents over XPC).
@main
struct SimmerWidgets: WidgetBundle {
    var body: some Widget {
        SimmerBatteryWidget()
        PowerFlowWidget()
        BatteryHistoryWidget()
        TopEnergyAppsWidget()
        ChargerHealthWidget()
        ChargingControlsWidget()
    }
}

struct SimmerBatteryWidget: Widget {
    static let kind = "com.umarwaseem.simmer.widget.battery"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: BatteryStatusConfig.self,
                               provider: ConfiguredProvider<BatteryStatusConfig>(parts: [.history])) { entry in
            FamilyReader { family in
                SimmerWidgetView(entry: entry.data, options: BatteryOptions(showLimitMarker: entry.config.showLimitMarker,
                                                                          showTimeRemaining: entry.config.showTimeRemaining,
                                                                          hardwarePercent: entry.config.percentSource == .hardware),
                                 family: family)
            }
        }
        .configurationDisplayName("Battery")
        .description("Charge level, charge limit, power flow and battery health.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PowerFlowWidget: Widget {
    static let kind = "com.umarwaseem.simmer.widget.powerflow"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StaticProvider(parts: [.history])) { entry in
            FamilyReader { PowerFlowWidgetView(entry: entry, family: $0) }
        }
        .configurationDisplayName("Power Flow")
        .description("Watts from the power adapter to the Mac and the battery, and the Mac's power use over the last hour.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BatteryHistoryWidget: Widget {
    static let kind = "com.umarwaseem.simmer.widget.history"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: HistoryChartConfig.self,
                               provider: ConfiguredProvider<HistoryChartConfig>(parts: [.history, .config], refresh: 15 * 60)) { entry in
            FamilyReader { HistoryWidgetView(entry: entry.data, metric: entry.config.metric, range: entry.config.range, family: $0) }
        }
        .configurationDisplayName("Battery History")
        .description("Charge, temperature, power or health over 24 hours, 7 days or 14 days.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TopEnergyAppsWidget: Widget {
    static let kind = "com.umarwaseem.simmer.widget.topapps"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: TopAppsConfig.self,
                               provider: ConfiguredProvider<TopAppsConfig>(parts: [.energy])) { entry in
            FamilyReader { TopAppsWidgetView(entry: entry.data, count: entry.config.count.count, family: $0) }
        }
        .configurationDisplayName("Top Energy Apps")
        .description("The apps that use the most power right now.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ChargerHealthWidget: Widget {
    static let kind = "com.umarwaseem.simmer.widget.charger"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StaticProvider(parts: [.history, .details], refresh: 15 * 60)) { entry in
            FamilyReader { ChargerHealthWidgetView(entry: entry, family: $0) }
        }
        .configurationDisplayName("Charger & Health")
        .description("Whether your charger keeps up, plus battery health, cycle count and cell balance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ChargingControlsWidget: Widget {
    static let kind = "com.umarwaseem.simmer.widget.controls"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: ControlsConfig.self,
                               provider: ConfiguredProvider<ControlsConfig>(parts: [.config])) { entry in
            FamilyReader { ControlsWidgetView(entry: entry.data, limits: entry.config.limits, family: $0) }
        }
        .configurationDisplayName("Charging Controls")
        .description("Buttons for Top Up, Pause, Discharge and your favorite charge limits.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Passes the widget family to a view, so the views can also be rendered outside WidgetKit (previews, tests).
struct FamilyReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder var content: (WidgetFamily) -> Content
    var body: some View { content(family) }
}

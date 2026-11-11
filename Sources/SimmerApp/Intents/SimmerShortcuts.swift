import AppIntents

/// App Shortcuts: ready-made actions in Shortcuts, Spotlight and Siri, with no setup. At most 10.
struct SimmerShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetChargeLimitIntent(), phrases: [
            "Set \(.applicationName) charge limit",
            "Change the charge limit in \(.applicationName)",
            "Set battery limit with \(.applicationName)",
        ], shortTitle: "Set Charge Limit", systemImageName: "battery.75percent")

        AppShortcut(intent: TopUpIntent(), phrases: [
            "Top up with \(.applicationName)",
            "Charge to full with \(.applicationName)",
            "\(.applicationName) top up",
        ], shortTitle: "Top Up", systemImageName: "bolt.fill")

        AppShortcut(intent: PauseChargingIntent(), phrases: [
            "Pause charging with \(.applicationName)",
            "Hold the battery level with \(.applicationName)",
        ], shortTitle: "Pause Charging", systemImageName: "pause.fill")

        AppShortcut(intent: DischargeIntent(), phrases: [
            "Discharge with \(.applicationName)",
            "Drain the battery with \(.applicationName)",
        ], shortTitle: "Discharge", systemImageName: "arrow.down.circle")

        AppShortcut(intent: GetChargingStateIntent(), phrases: [
            "What is \(.applicationName) doing",
            "Get the charging state from \(.applicationName)",
            "\(.applicationName) status",
        ], shortTitle: "Charging State", systemImageName: "info.circle")

        AppShortcut(intent: GetBatteryPercentageIntent(), phrases: [
            "Get battery percentage from \(.applicationName)",
            "\(.applicationName) battery level",
        ], shortTitle: "Battery Percentage", systemImageName: "percent")

        AppShortcut(intent: GetBatteryHealthIntent(), phrases: [
            "Get battery health from \(.applicationName)",
            "\(.applicationName) battery health",
        ], shortTitle: "Battery Health", systemImageName: "heart.fill")

        AppShortcut(intent: GetPowerDrawIntent(), phrases: [
            "Get power draw from \(.applicationName)",
            "How many watts with \(.applicationName)",
        ], shortTitle: "Power Draw", systemImageName: "bolt.horizontal")

        AppShortcut(intent: GetChargerReportIntent(), phrases: [
            "Check my charger with \(.applicationName)",
            "Get the charger report from \(.applicationName)",
        ], shortTitle: "Charger Report", systemImageName: "powerplug.fill")

        AppShortcut(intent: CalibrateBatteryIntent(), phrases: [
            "Calibrate the battery with \(.applicationName)",
            "Start \(.applicationName) calibration",
        ], shortTitle: "Calibrate", systemImageName: "arrow.triangle.2.circlepath")
    }
}

import SwiftUI

/// Plain-language help for every feature. `tooltip` is the hover text; the popover shows all three parts.
enum HelpTopic: String, CaseIterable {
    // charging
    case limiter, chargeLimit, pause, topUp, discharge, calibration
    case sailing, heatProtection, automaticDischarge, keepLimit
    // sleep
    case stopChargingWhenSleeping, disableSleepUntilLimit, clamshellAwake, sleepNow
    // panel sections
    case powerFlow, battery, temperature, health, cycleCount, hardwareCharge, capacity, timeRemaining
    case lowPowerMode, highPowerMode
    // LED, calibration settings, automation
    case ledMode, ledCustom, blinkDischarge, calibrationHold, calibrationDischargeTo
    case schedule, catchUp, shortcuts, helper, launchAtLogin, hardwarePercentInMenuBar, menuBarExtras, notifications
    // battery history
    case history, chargeHistory, temperatureHistory, powerHistory, healthHistory, capacityHistory, cycleHistory, averageTemperature
    // menu bar panel
    case panelLayout, limitPresets, effectiveLimit, chargerReport, topApps, capabilityLimitOnly
    case limitControl, batteryIllustration, chargeControl
    // smart charging
    case deskMode, deskModeLimit, deskModeTrigger, deskModeHours, smartTopUp, smartTopUpLead, departurePrediction
    case cheapCharging, cheapFloor, cheapWindows
    // insights
    case energy, energyNow, energyHour, cpuPercent, wakeups, sinceUnplug
    case sleepDrain, darkWakes, sleepBlockers, sessions, componentPower, usbPower, usbAllocation
    case stressMeter, timeAtHighCharge, dailyChargeRange, cellBalance, lifetimeTemperature
    // charger and tools
    case charger, pdOptions, peakUse, conflicts, nativeChargeLimit, ledTest, ledBlinkCommand
    case backup, autoBackup, importBackup, passport, updates, autoUpdates, helperUpdate

    var title: String {
        switch self {
        case .limiter: return "Charge Limiter"
        case .chargeLimit: return "Charge Limit"
        case .pause: return "Pause"
        case .topUp: return "Top Up"
        case .discharge: return "Discharge"
        case .calibration: return "Calibration"
        case .sailing: return "Sailing Mode"
        case .heatProtection: return "Heat Protection"
        case .automaticDischarge: return "Automatic Discharge"
        case .keepLimit: return "Keep Limit When Simmer Quits"
        case .stopChargingWhenSleeping: return "Stop Charging When Sleeping"
        case .disableSleepUntilLimit: return "Disable Sleep Until Limit"
        case .clamshellAwake: return "Stay Awake With Lid Closed"
        case .sleepNow: return "Sleep Now"
        case .powerFlow: return "Power Flow"
        case .battery: return "Battery"
        case .temperature: return "Temperature"
        case .health: return "Health"
        case .cycleCount: return "Cycle Count"
        case .hardwareCharge: return "Hardware Charge"
        case .capacity: return "Capacity"
        case .timeRemaining: return "Time Remaining"
        case .lowPowerMode: return "Low Power Mode"
        case .highPowerMode: return "High Power Mode"
        case .ledMode: return "MagSafe LED"
        case .ledCustom: return "Custom LED Colors"
        case .blinkDischarge: return "Blink During Discharge"
        case .calibrationHold: return "Hold Time"
        case .calibrationDischargeTo: return "Discharge To"
        case .schedule: return "Schedule"
        case .catchUp: return "Catch Up Missed Tasks"
        case .shortcuts: return "Shortcuts & Terminal"
        case .helper: return "Helper"
        case .launchAtLogin: return "Launch at Login"
        case .hardwarePercentInMenuBar: return "Show Hardware Percentage"
        case .menuBarExtras: return "Menu Bar Extras"
        case .notifications: return "Notifications"
        case .history: return "Battery History"
        case .chargeHistory: return "Charge Level"
        case .temperatureHistory: return "Temperature History"
        case .powerHistory: return "Battery Power"
        case .healthHistory: return "Health Over Time"
        case .capacityHistory: return "Capacity Over Time"
        case .cycleHistory: return "Cycle Count Over Time"
        case .averageTemperature: return "Average Temperature"
        default: return Self.extra[self]?.title ?? rawValue
        }
    }

    /// What it does, in one or two short sentences.
    var what: String {
        switch self {
        case .limiter: return "Turns Simmer's charge control on or off. When it is off, your Mac charges the normal Apple way, up to 100%."
        case .chargeLimit: return "Charging stops at this percentage. The charger still powers your Mac, so the battery just rests."
        case .pause: return "Stops charging right now by setting the limit to the current percentage."
        case .topUp: return "Charges to 100% one time. It turns itself off when you unplug."
        case .discharge: return "Runs your Mac from the battery while the charger stays plugged in, until the battery drops to your limit."
        case .calibration: return "Runs one full cycle: charge to 100%, wait, drain low, charge to 100%, wait, then go back to your limit. It takes several hours."
        case .sailing: return "When the battery reaches the limit, Simmer lets it drift down a few percent before it charges again."
        case .heatProtection: return "Pauses charging when the battery gets too hot and continues when it cools down."
        case .automaticDischarge: return "If the battery is above your limit while plugged in, Simmer drains it down to the limit by itself."
        case .keepLimit: return "When the helper stops (for example when you quit or uninstall), charging stays blocked instead of jumping to 100%."
        case .stopChargingWhenSleeping: return "Blocks charging just before your Mac sleeps."
        case .disableSleepUntilLimit: return "Keeps your Mac awake while it charges toward the limit, then lets it sleep normally."
        case .clamshellAwake: return "Keeps your Mac awake with the lid closed while a discharge runs."
        case .sleepNow: return "Puts your Mac to sleep immediately."
        case .powerFlow: return "Shows where the electricity goes right now: from the charger, into your Mac, and into or out of the battery, in watts."
        case .battery: return "Live facts about your battery's condition."
        case .temperature: return "The battery temperature, read from the battery sensor."
        case .health: return "How much charge your battery can hold today compared to when it was new."
        case .cycleCount: return "How many full charges your battery has used. Two half charges count as one cycle."
        case .hardwareCharge: return "The real charge level reported by the battery chip. macOS rounds and smooths the number it shows you."
        case .capacity: return "The charge your battery can hold today, next to what it held when new, in milliamp-hours (mAh)."
        case .timeRemaining: return "macOS's estimate of the time until the battery is full or empty, based on current use."
        case .lowPowerMode: return "The macOS mode that slows the Mac a little to use less energy and run cooler. You can set it separately for battery and charger."
        case .highPowerMode: return "The macOS mode that lets the fans spin harder so the chip can stay at full speed during heavy work."
        case .ledMode: return "Controls the small light on the MagSafe connector."
        case .ledCustom: return "Choose the LED color for each state, for example green while charging and off at the limit."
        case .blinkDischarge: return "In Smart mode, the LED blinks orange while a discharge runs."
        case .calibrationHold: return "How long calibration waits at 100% before the next step."
        case .calibrationDischargeTo: return "How low calibration drains the battery before charging it back to 100%."
        case .schedule: return "Runs actions automatically at set times, for example a Top Up every Monday morning."
        case .catchUp: return "If your Mac was asleep or off when a task was due, the task runs as soon as the Mac wakes."
        case .shortcuts: return "Control Simmer from the Shortcuts app, Terminal, or scripts with simmer:// links or the simmerctl command."
        case .helper: return "A small background program that runs with admin rights and talks to the Mac's power controller (SMC)."
        case .launchAtLogin: return "Opens the Simmer menu bar app automatically when you log in."
        case .hardwarePercentInMenuBar: return "Shows the real battery-chip percentage in the menu bar instead of the macOS number."
        case .menuBarExtras: return "Adds the battery temperature or the Mac's power use next to the menu bar icon."
        case .notifications: return "Shows a notification when something important happens, like the limit being reached or heat protection starting."
        case .history: return "The helper saves a battery reading every 5 minutes for 14 days, and a health summary every day for as long as Simmer runs."
        case .chargeHistory: return "The battery percentage over time. Shaded areas show when the charger was connected; the dashed line is your charge limit."
        case .temperatureHistory: return "The battery temperature over time. The dashed line marks 35 °C."
        case .powerHistory: return "Power going into the battery (above zero, charging) or out of it (below zero, discharging)."
        case .healthHistory: return "The battery health for each day: the charge it can hold compared to when it was new."
        case .capacityHistory: return "The charge the battery can hold each day in mAh, next to its design capacity."
        case .cycleHistory: return "The total number of charge cycles, day by day."
        case .averageTemperature: return "The average battery temperature over the last 7 days."
        default: return Self.extra[self]?.what ?? ""
        }
    }

    /// Why it helps / when to use it.
    var why: String {
        switch self {
        case .limiter: return "Leave it on for battery care. Turn it off only if you want Apple's default charging."
        case .chargeLimit: return "Lithium batteries wear fastest when they sit full. Keeping a desk Mac at 60–80% can make the battery last years longer. Use 100% (or Top Up) before a long day away from a charger."
        case .pause: return "Useful when you plug in at, say, 72% and are happy to stay there."
        case .topUp: return "Use it before a trip or a long meeting when you need every bit of battery, without changing your normal limit."
        case .discharge: return "Plugged in at 100% but want 80%? Discharge brings it down without unplugging. macOS will think it is on battery during this time."
        case .calibration: return "Over time the battery's percentage display drifts and becomes less accurate. Calibrating about once a month keeps the number honest. Keep the charger connected."
        case .sailing: return "Without it the battery gets many tiny top-ups (80 → 79 → 80 …), and each one adds a little wear. Sailing lets it float, for example between 75% and 80%, so it charges less often."
        case .heatProtection: return "Heat plus charging is the worst combination for a battery. Turn this on if your Mac gets warm, for example during gaming, video exports or summer days."
        case .automaticDischarge: return "Handy if you often plug in with a full battery. The battery ends up at your limit without you doing anything."
        case .keepLimit: return "Protects the battery if Simmer is not running. Turn it off if you want normal charging whenever Simmer is closed."
        case .stopChargingWhenSleeping: return "Simmer cannot act while the Mac sleeps, so without this the battery could charge past your limit overnight."
        case .disableSleepUntilLimit: return "Makes sure the limit is applied exactly. The other option is to stop charging when sleeping."
        case .clamshellAwake: return "During a discharge macOS thinks it runs on battery, and on battery a closed lid means sleep, so external displays go dark. This prevents that."
        case .sleepNow: return "A quick shortcut when you walk away."
        case .powerFlow: return "Tells you if your charger is strong enough, how hungry your apps are, and whether the battery is charging (+), resting (0) or draining (−)."
        case .battery: return "Watch these over months to see how well your battery is aging."
        case .temperature: return "Below about 35 °C is comfortable for a battery. Higher temperatures while charging age it faster."
        case .health: return "Below about 80% you will notice shorter battery life, and Apple may suggest service."
        case .cycleCount: return "Apple rates MacBook batteries for about 1000 cycles. Lower is better for the same age."
        case .hardwareCharge: return "Useful to see small changes that the macOS number hides, for example during a discharge."
        case .capacity: return "This is where health comes from. The first number falls slowly as the battery ages."
        case .timeRemaining: return "Changes quickly with what you do. Treat it as a rough guide."
        case .lowPowerMode: return "Great on battery for longer runtime, or on the charger for a quieter, cooler Mac."
        case .highPowerMode: return "Use it on the charger for long renders or compiles. It is louder and uses more power."
        case .ledMode: return "Smart mode shows Simmer's state at a glance. Off is nice in a dark bedroom."
        case .ledCustom: return "Make the light mean what you want. The hardware has only a green and an orange light, plus blinking."
        case .blinkDischarge: return "Reminds you that the Mac is running on its battery even though it is plugged in."
        case .calibrationHold: return "60 minutes lets the battery chip settle at full. Shorter is faster but less accurate."
        case .calibrationDischargeTo: return "Lower gives a more complete calibration but takes longer. 10% is a good balance."
        case .schedule: return "Set and forget: for example Top Up on weekday mornings, or calibrate on the 1st of each month."
        case .catchUp: return "Keep it on so a task is not lost just because the lid was closed at that time."
        case .shortcuts: return "Build automations, for example \"When I start Focus mode for travel, set the limit to 100%\"."
        case .helper: return "Charge control needs admin rights. The helper keeps your limit working even when the menu bar app is closed."
        case .launchAtLogin: return "The helper always runs, but the app gives you the icon, controls and notifications."
        case .hardwarePercentInMenuBar: return "For people who like exact numbers."
        case .menuBarExtras: return "See at a glance if your Mac is running hot or using a lot of power."
        case .notifications: return "Lets Simmer work in the background without you having to check it."
        case .history: return "Check back over weeks and months to see how well your battery care works."
        case .chargeHistory: return "A flat line at the limit while plugged in means Simmer holds the battery where it should be."
        case .temperatureHistory: return "Time above 35 °C, mostly while charging, ages the battery faster. Heat protection can help."
        case .powerHistory: return "Long periods near zero while plugged in mean the battery rests and the charger powers the Mac directly."
        case .healthHistory: return "Health falls slowly with age and use. Day-to-day changes of about 1% are normal measurement noise; watch the long-term trend."
        case .capacityHistory: return "This is where the health number comes from. The line should fall slowly over months, not weeks."
        case .cycleHistory: return "A steep line means many charge cycles. Apple rates MacBook batteries for about 1000 cycles."
        case .averageTemperature: return "Below about 30 °C on average is comfortable for a battery."
        default: return Self.extra[self]?.why ?? ""
        }
    }

    var tooltip: String { "\(what) \(why)" }

    /// Texts for the newer features: title, what it does, why it helps.
    private static let extra: [HelpTopic: (title: String, what: String, why: String)] = [
        // menu bar panel
        .panelLayout: ("Menu Bar Panel",
                       "Choose which sections the menu bar panel shows and in which order.",
                       "Hide what you never look at, so the panel stays short and the important parts are on top."),
        .limitControl: ("Limit Control",
                         "Choose how the panel sets the charge limit: a stove knob or a plain slider. Turn the knob by dragging around it, drag up or down on its centre, scroll over it, click a number on the scale, or use the arrow keys (Shift for steps of 5).",
                         "The knob shows the limit at a glance and is easy to set with a trackpad. The slider takes less room."),
        .chargeControl: ("Charge Control",
                         "How Simmer stops charging. Simmer direct writes the Mac's charging switch (all features). macOS Charge Limit uses the limit in System Settings → Battery, which Simmer sets for you in steps such as 80, 85, 90, 95 and 100%. Automatic uses direct control and switches to the macOS limit if macOS blocks it.",
                         "Keep Automatic. Newer macOS versions (macOS 27) can block direct control; then Simmer keeps working with the macOS limit, with fewer features."),
        .batteryIllustration: ("Battery Illustration",
                               "Shows the battery as a glowing jar at the top of the panel. The liquid is the current charge and the dashed line is the limit. It steams while charging, glows green while holding and pulses while discharging.",
                               "Shows the state at a glance. The animation runs only while the panel is open, and stops when Reduce Motion is on."),
        .limitPresets: ("Quick Limits",
                        "Buttons in the panel that set the charge limit with one click, for example 60%, 80% and 100%.",
                        "Faster than the knob or the slider when you switch between a desk limit and a full charge for a trip."),
        .effectiveLimit: ("Active Limit",
                          "The limit the helper applies right now. Desk mode, smart top-up or cheap charging windows can change it for a while.",
                          "Your own limit stays saved. Simmer goes back to it by itself when the reason ends."),
        .chargerReport: ("Charger Check",
                         "Compares what your charger can deliver with what your Mac uses now and at its recent peak.",
                         "A weak charger or cable can make the battery drain even while plugged in, mostly during heavy work."),
        .topApps: ("Top Energy Apps",
                   "The apps that use the most power right now, measured by the helper every minute.",
                   "If the battery drains fast, the app at the top is usually the reason. Quit it or check its settings."),
        .capabilityLimitOnly: ("Limit Only",
                               "This Mac supports only a fixed maximum charge level. Top Up, discharge and sailing are not available.",
                               "The good news: the Mac keeps the limit by itself, even while it sleeps or is turned off."),
        // smart charging
        .deskMode: ("Desk Mode",
                    "Lowers the limit while your Mac sits at a desk: with the lid closed on an external display, or after many hours on the charger.",
                    "A battery that sits full and warm for weeks can age faster and, in rare cases, swell. A lower level at the desk is gentler."),
        .deskModeLimit: ("Desk Limit",
                         "The charge level Simmer holds while desk mode is active. It is never higher than your normal limit.",
                         "50–60% is the gentlest level for a battery that stays plugged in all day."),
        .deskModeTrigger: ("Start Desk Mode When",
                           "Choose what counts as \"at the desk\": the lid closed while plugged in, many hours on the charger, or either.",
                           "Clamshell use with an external display is the most common desk setup."),
        .deskModeHours: ("Hours on the Charger",
                         "Desk mode starts after the Mac has been plugged in for this long without a break.",
                         "Short charging stops do not trigger it, so your normal limit applies when you just top up."),
        .smartTopUp: ("Smart Top-Up",
                      "Learns when you usually unplug and charges to 100% just before that time.",
                      "You get a full battery when you leave, but the battery does not sit at 100% all night."),
        .smartTopUpLead: ("Start Before Departure",
                          "How long before your usual departure Simmer starts charging to 100%.",
                          "90 minutes is enough for most Macs to charge fully. Use more if your charger is weak."),
        .departurePrediction: ("Predicted Departure",
                               "Simmer looks at the history: when you unplugged on the same weekday at a similar time at least twice, it expects you to do so again.",
                               "No prediction means no clear pattern yet. Then smart top-up does nothing and your normal limit applies."),
        .cheapCharging: ("Cheap & Green Charging",
                         "Outside the time windows you set, Simmer charges only up to a low floor. Inside a window, it charges to your limit.",
                         "Electricity is often cheaper and cleaner at night or around midday solar hours. Shift the charging there."),
        .cheapFloor: ("Charge Floor",
                      "Outside the windows, Simmer charges only up to this level, so you always have a reserve.",
                      "40% is enough for a short trip. Raise it if you often leave at short notice."),
        .cheapWindows: ("Charging Windows",
                        "The hours when charging to your full limit is allowed. A window may wrap past midnight, for example 22:00–06:00.",
                        "Match them to your electricity tariff or to the hours of the most solar or wind power in your area."),
        // insights
        .energy: ("Energy",
                  "The helper estimates how much power each app and process uses, from its processor and graphics time.",
                  "The numbers are estimates. Use them to compare apps, not as exact meter readings."),
        .energyNow: ("Power Now",
                     "Average power over the last minute.",
                     "Shows what is busy at this moment."),
        .energyHour: ("1-Hour Average",
                      "Average power over the last hour.",
                      "Better than \"now\" to find apps that drain the battery slowly in the background."),
        .cpuPercent: ("CPU",
                      "Processor use over the last minute. 100% means one full core.",
                      "High CPU for an app you are not using is a sign that it is stuck or busy in the background."),
        .wakeups: ("Wakeups",
                   "How often per second the process wakes the processor from idle.",
                   "Many wakeups keep the chip from resting, which costs battery even when the CPU number is low."),
        .sinceUnplug: ("Since Unplug",
                       "Energy the app used since you last unplugged the charger, in watt-hours.",
                       "Answers the question \"where did my battery go today?\""),
        .sleepDrain: ("Sleep Drain",
                      "Reads the macOS power log and shows each sleep: how long it lasted, how much charge it lost and how often the Mac woke up.",
                      "A sleeping Mac should lose about 1% per hour or less. More than that usually means something keeps waking it."),
        .darkWakes: ("Dark Wakes",
                     "Short wakes with the screen off, for mail, backups, Find My or network devices.",
                     "A few are normal. Dozens per night drain the battery. Power Nap and \"Wake for network access\" cause many of them."),
        .sleepBlockers: ("Won’t Sleep?",
                         "Lists the apps and processes that hold a power assertion: a request to macOS to stay awake.",
                         "If your Mac never sleeps, one of these is the reason. Quit the app or finish its task."),
        .sessions: ("Battery Sessions",
                    "Each time on battery, from unplug to plug-in: how long, how many percent, how fast it drained and the average power.",
                    "Compare days to see which kind of work drains the battery fastest."),
        .componentPower: ("Chip Power",
                          "Live power of the processor (CPU), graphics (GPU), Neural Engine (ANE) and memory (DRAM), read from the chip's energy counters.",
                          "Shows which part of the chip works hard. The rest of the Mac's power goes to the screen, SSD, ports and other parts."),
        .usbPower: ("USB Power",
                    "Power your Mac sends out of its ports to connected devices, as reported by the power controller.",
                    "Bus-powered drives, hubs and phones charging from your Mac all draw from the same budget as the battery."),
        .usbAllocation: ("Power Allocation",
                         "The current macOS reserved for each USB device, in milliamps at 5 V.",
                         "This is the maximum a device may draw, not its live use. Many devices use much less."),
        .stressMeter: ("Battery Stress",
                       "How much of its life the battery spent at a high charge level, from the battery's own lifetime counters.",
                       "Time at a high charge, mostly when warm, is the main cause of battery aging. Lower is better."),
        .timeAtHighCharge: ("Time at High Charge",
                            "Hours the battery spent near full, counted by the battery itself.",
                            "A charge limit reduces this number from the day you start using it."),
        .dailyChargeRange: ("Daily Charge Range",
                            "The lowest and highest charge level of the day, as recorded by the battery.",
                            "A narrow range in the middle (for example 40–80%) is the gentlest daily pattern."),
        .cellBalance: ("Cell Balance",
                       "Your battery has several cells in series. This compares their voltages. A difference below 30 mV is normal.",
                       "A large, growing difference means one cell ages faster. Above 80 mV, plan a battery check with Apple."),
        .lifetimeTemperature: ("Lifetime Temperature",
                               "The highest, lowest and average temperature the battery has seen, recorded by the battery.",
                               "Batteries age faster when hot. A high maximum is normal after heavy use or a hot car."),
        // charger and tools
        .charger: ("Charger",
                   "What your charger offers, what it negotiated with the Mac, and whether that is enough for how you use the Mac.",
                   "A charger that is too weak charges slowly and can even let the battery drain during heavy work."),
        .pdOptions: ("Charger Voltage Options",
                     "USB-C chargers offer several voltage and current levels. The Mac picks one. The active option is marked.",
                     "If the highest option is missing, the cable or a hub may limit the power."),
        .peakUse: ("Peak Use",
                   "The highest power your Mac used in the last 7 days, from the 5-minute history.",
                   "A charger should cover your peak use plus a few watts for charging."),
        .conflicts: ("Conflict Doctor",
                     "Finds other charge-limit tools and their background helpers, and the macOS charge limit setting.",
                     "Two tools that control charging at the same time fight each other. The limit then jumps or does not work."),
        .nativeChargeLimit: ("macOS Charge Limit",
                             "Newer macOS versions have their own charge limit in System Settings → Battery.",
                             "Use either the macOS limit or Simmer, not both. Turn the macOS one off to let Simmer control charging."),
        .ledTest: ("Test the LED",
                   "Plays a short blink pattern on the MagSafe light, then returns to the normal LED mode.",
                   "Check that the LED works, or try the patterns before you use them in Shortcuts or scripts."),
        .ledBlinkCommand: ("LED Notifications From Scripts",
                           "The simmerctl led blink command plays the same patterns from Terminal, scripts or Shortcuts.",
                           "For example: blink green when a long build is done, so you see it from across the room."),
        .backup: ("Backup & Restore",
                  "Saves all Simmer settings, panel layout and app preferences to a .simmerbackup file.",
                  "Move your setup to a new Mac, or go back to a setup that worked."),
        .autoBackup: ("Automatic Backups",
                      "Once a week Simmer saves a backup to ~/Library/Application Support/Simmer/Backups and keeps the last 8.",
                      "You can always go back a few weeks, without having to remember to save."),
        .importBackup: ("Import",
                        "Reads a .simmerbackup file, shows every setting that would change, and applies it only after you confirm.",
                        "Nothing changes until you click Apply."),
        .passport: ("Battery Passport",
                    "A one-page PDF with the battery's health, capacity, cycles, cell balance and serial number.",
                    "Buyers trust a clear report. It also helps when you talk to a repair shop."),
        .updates: ("Updates",
                   "Checks for a new version of Simmer.",
                   "Updates bring fixes and support for new Macs and macOS versions."),
        .autoUpdates: ("Automatic Update Checks",
                       "Simmer checks for updates in the background about once a day.",
                       "You still decide when to install."),
        .helperUpdate: ("Update the Helper",
                        "The app was updated, but the background helper still runs the old version.",
                        "New features need the new helper. Updating takes a few seconds and asks for an administrator password."),
    ]
}

/// A small ⓘ button that opens a popover with the full help text.
struct InfoButton: View {
    let topic: HelpTopic
    @State private var shown = false
    init(_ topic: HelpTopic) { self.topic = topic }

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(topic.tooltip)
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(topic.title).font(.headline)
                Text(topic.what).fixedSize(horizontal: false, vertical: true)
                Label {
                    Text(topic.why).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb").foregroundStyle(.yellow)
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 290)
        }
        .accessibilityLabel("About \(topic.title)")
    }
}

/// Label text followed by an ⓘ button; also sets the hover tooltip.
struct HelpLabel: View {
    let text: String, topic: HelpTopic
    init(_ text: String, _ topic: HelpTopic) { self.text = text; self.topic = topic }
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            InfoButton(topic)
        }
        .help(topic.tooltip)
    }
}

extension View {
    /// Hover tooltip from a help topic.
    func help(_ topic: HelpTopic) -> some View { help(topic.tooltip) }
}

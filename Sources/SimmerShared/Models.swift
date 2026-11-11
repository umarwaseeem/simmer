import Foundation

public enum Simmer {
    public static let appBundleID = "com.umarwaseem.simmer"
    public static let ctlIdentifier = "com.umarwaseem.simmer.ctl"
    public static let helperLabel = "com.umarwaseem.simmer.helper"
    public static let machService = "com.umarwaseem.simmer.helper"
    public static let helperVersion = "1.0.0"
    public static let configPath = "/Library/Application Support/Simmer/config.json"
    public static let statePath = "/Library/Application Support/Simmer/state.json"
    public static let helperInstallPath = "/Library/PrivilegedHelperTools/com.umarwaseem.simmer.helper"
    public static let launchDaemonPlist = "/Library/LaunchDaemons/com.umarwaseem.simmer.helper.plist"
    public static let statusNotification = "com.umarwaseem.simmer.status"   // Darwin notification on state change
}

public enum LEDMode: String, Codable, CaseIterable, Sendable {
    case system      // macOS controls the MagSafe LED
    case smart       // orange = charging, green = holding at limit / full
    case alwaysOff
    case custom      // user-chosen color per charge state (LEDCustomColors)
}

/// Per-state MagSafe LED colors for LEDMode.custom. The LED is only lit while the charger is connected.
public struct LEDCustomColors: Codable, Equatable, Sendable {
    public var charging: LEDColor = .orange
    public var limitReached: LEDColor = .green
    public var sailing: LEDColor = .green
    public var discharging: LEDColor = .orangeBlinkSlow
    public var heatProtection: LEDColor = .orangeBlinkFast
    public var topUp: LEDColor = .orange
    public var calibration: LEDColor = .orangeBlinkSlow
    public var limiterOff: LEDColor = .system
    public init() {}

    public static let editableStates: [(ChargeState, WritableKeyPath<LEDCustomColors, LEDColor>)] = [
        (.charging, \.charging), (.limitReached, \.limitReached), (.sailing, \.sailing), (.discharging, \.discharging),
        (.heatProtection, \.heatProtection), (.topUp, \.topUp), (.calibration, \.calibration), (.limiterOff, \.limiterOff),
    ]

    public func color(for state: ChargeState) -> LEDColor {
        switch state {
        case .charging: return charging
        case .limitReached: return limitReached
        case .sailing: return sailing
        case .discharging: return discharging
        case .heatProtection: return heatProtection
        case .topUp: return topUp
        case .calibration: return calibration
        case .limiterOff: return limiterOff
        case .notPluggedIn, .unsupported: return .system
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LEDCustomColors()
        charging = try c.decodeIfPresent(LEDColor.self, forKey: .charging) ?? d.charging
        limitReached = try c.decodeIfPresent(LEDColor.self, forKey: .limitReached) ?? d.limitReached
        sailing = try c.decodeIfPresent(LEDColor.self, forKey: .sailing) ?? d.sailing
        discharging = try c.decodeIfPresent(LEDColor.self, forKey: .discharging) ?? d.discharging
        heatProtection = try c.decodeIfPresent(LEDColor.self, forKey: .heatProtection) ?? d.heatProtection
        topUp = try c.decodeIfPresent(LEDColor.self, forKey: .topUp) ?? d.topUp
        calibration = try c.decodeIfPresent(LEDColor.self, forKey: .calibration) ?? d.calibration
        limiterOff = try c.decodeIfPresent(LEDColor.self, forKey: .limiterOff) ?? d.limiterOff
    }
}

public enum PowerModeScope: String, Codable, CaseIterable, Sendable { case all, battery, charger }

public enum Weekday: Int, Codable, CaseIterable, Sendable { case sun = 1, mon, tue, wed, thu, fri, sat }

public enum TaskAction: Codable, Equatable, Sendable {
    case setLimit(Int)
    case topUp
    case discharge(Int)            // discharge down to this limit
    case calibrate
    case lowPowerMode(Bool)
    case highPowerMode(Bool)
    case limiter(Bool)             // enable / disable limiter
}

public enum TaskRecurrence: Codable, Equatable, Sendable {
    case once(Date)
    case daily
    case weekly([Weekday])
    case biweekly(Weekday)
    case monthly(day: Int)
}

public struct ScheduledTask: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var enabled = true
    public var action: TaskAction
    public var recurrence: TaskRecurrence
    public var hour: Int
    public var minute: Int
    public var lastRun: Date? = nil
    public init(name: String, action: TaskAction, recurrence: TaskRecurrence, hour: Int, minute: Int, enabled: Bool = true) {
        self.name = name; self.action = action; self.recurrence = recurrence; self.hour = hour; self.minute = minute; self.enabled = enabled
    }

    public static let mondayMorningTopUp = ScheduledTask(name: "Monday Morning Top-Up", action: .topUp, recurrence: .weekly([.mon]), hour: 5, minute: 0, enabled: false)
    public static let monthlyCalibration = ScheduledTask(name: "Monthly Calibration", action: .calibrate, recurrence: .monthly(day: 1), hour: 10, minute: 0, enabled: false)
}

/// Persistent user settings, owned by the daemon.
public struct SimmerConfig: Codable, Equatable, Sendable {
    public var limiterEnabled = true
    public var chargeLimit = 80                    // 20...100
    public var sailingEnabled = false
    public var sailingLevel = 5                    // allowed drift below limit, 1...20
    public var automaticDischarge = false          // discharge to limit when plugged in above it
    public var heatProtectionEnabled = false
    public var heatThresholdC = 35.0
    public var heatResumeDeltaC = 2.0              // resume when temp < threshold - delta
    public var stopChargingWhenSleeping = false
    public var disableSleepUntilLimit = false
    public var keepLimitWhenQuit = true            // keep charging inhibited when daemon stops
    public var ledMode: LEDMode = .system
    public var blinkOrangeDuringDischarge = true
    public var ledCustom = LEDCustomColors()
    /// While the adapter is disabled macOS sees battery power, and closing the lid forces clamshell sleep
    /// (external displays go dark). When true, simmerd sets `pmset disablesleep 1` for that time.
    public var preventClamshellSleepWhileDischarging = true
    public var calibrationHoldMinutes = 60
    public var calibrationDischargeTo = 10
    public var catchUpMissedTasks = true
    public var schedule: [ScheduledTask] = [.mondayMorningTopUp, .monthlyCalibration]
    // Desk mode: lower the limit during long desk / clamshell use (battery swelling risk).
    public var deskModeEnabled = false
    public var deskModeLimit = 55
    public var deskModeTrigger: DeskModeTrigger = .clamshellOrPluggedHours
    public var deskModeAfterHours = 3.0
    // Smart "ready by": learn when the Mac is usually unplugged and top up to 100% just before.
    public var smartTopUpEnabled = false
    public var smartTopUpLeadMinutes = 90
    // Cheap / green charging: outside the windows, charge only up to the floor.
    public var cheapChargingEnabled = false
    public var cheapWindows: [TimeWindow] = [TimeWindow(startHour: 0, startMinute: 0, endHour: 6, endMinute: 0)]
    public var cheapFloorPercent = 40
    /// Older Intel Macs (BCLM backend): added to the limit before it is written to BCLM. See ChargeControl.bclmValue.
    public var intelBCLMOffset = ChargeControl.defaultBCLMOffset
    public init() {}

    /// Tolerant decoding: fields added in later versions fall back to defaults, so old config files still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SimmerConfig()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) throws -> T { try c.decodeIfPresent(T.self, forKey: k) ?? def }
        limiterEnabled = try v(.limiterEnabled, d.limiterEnabled)
        chargeLimit = try v(.chargeLimit, d.chargeLimit)
        sailingEnabled = try v(.sailingEnabled, d.sailingEnabled)
        sailingLevel = try v(.sailingLevel, d.sailingLevel)
        automaticDischarge = try v(.automaticDischarge, d.automaticDischarge)
        heatProtectionEnabled = try v(.heatProtectionEnabled, d.heatProtectionEnabled)
        heatThresholdC = try v(.heatThresholdC, d.heatThresholdC)
        heatResumeDeltaC = try v(.heatResumeDeltaC, d.heatResumeDeltaC)
        stopChargingWhenSleeping = try v(.stopChargingWhenSleeping, d.stopChargingWhenSleeping)
        disableSleepUntilLimit = try v(.disableSleepUntilLimit, d.disableSleepUntilLimit)
        keepLimitWhenQuit = try v(.keepLimitWhenQuit, d.keepLimitWhenQuit)
        ledMode = try v(.ledMode, d.ledMode)
        blinkOrangeDuringDischarge = try v(.blinkOrangeDuringDischarge, d.blinkOrangeDuringDischarge)
        ledCustom = try v(.ledCustom, d.ledCustom)
        preventClamshellSleepWhileDischarging = try v(.preventClamshellSleepWhileDischarging, d.preventClamshellSleepWhileDischarging)
        calibrationHoldMinutes = try v(.calibrationHoldMinutes, d.calibrationHoldMinutes)
        calibrationDischargeTo = try v(.calibrationDischargeTo, d.calibrationDischargeTo)
        catchUpMissedTasks = try v(.catchUpMissedTasks, d.catchUpMissedTasks)
        schedule = try v(.schedule, d.schedule)
        deskModeEnabled = try v(.deskModeEnabled, d.deskModeEnabled)
        deskModeLimit = try v(.deskModeLimit, d.deskModeLimit)
        deskModeTrigger = try v(.deskModeTrigger, d.deskModeTrigger)
        deskModeAfterHours = try v(.deskModeAfterHours, d.deskModeAfterHours)
        smartTopUpEnabled = try v(.smartTopUpEnabled, d.smartTopUpEnabled)
        smartTopUpLeadMinutes = try v(.smartTopUpLeadMinutes, d.smartTopUpLeadMinutes)
        cheapChargingEnabled = try v(.cheapChargingEnabled, d.cheapChargingEnabled)
        cheapWindows = try v(.cheapWindows, d.cheapWindows)
        cheapFloorPercent = try v(.cheapFloorPercent, d.cheapFloorPercent)
        intelBCLMOffset = try v(.intelBCLMOffset, d.intelBCLMOffset)
    }

    public mutating func clamp() {
        chargeLimit = min(100, max(20, chargeLimit))
        sailingLevel = min(20, max(1, sailingLevel))
        heatThresholdC = min(50, max(25, heatThresholdC))
        calibrationHoldMinutes = min(240, max(0, calibrationHoldMinutes))
        calibrationDischargeTo = min(50, max(5, calibrationDischargeTo))
        deskModeLimit = min(100, max(20, deskModeLimit))
        deskModeAfterHours = min(24, max(0.5, deskModeAfterHours))
        smartTopUpLeadMinutes = min(240, max(15, smartTopUpLeadMinutes))
        cheapFloorPercent = min(100, max(20, cheapFloorPercent))
        intelBCLMOffset = min(0, max(-10, intelBCLMOffset))
        cheapWindows = cheapWindows.map { w in
            TimeWindow(startHour: min(23, max(0, w.startHour)), startMinute: min(59, max(0, w.startMinute)),
                       endHour: min(23, max(0, w.endHour)), endMinute: min(59, max(0, w.endMinute)))
        }
    }
}

public enum CalibrationPhase: String, Codable, Sendable {
    case chargeToFull, holdFull, dischargeLow, chargeToFullAgain, holdFullAgain, returnToLimit
    public var title: String {
        switch self {
        case .chargeToFull: return "Charging to 100%"
        case .holdFull: return "Holding at 100%"
        case .dischargeLow: return "Discharging"
        case .chargeToFullAgain: return "Charging to 100% again"
        case .holdFullAgain: return "Holding at 100% again"
        case .returnToLimit: return "Returning to charge limit"
        }
    }
}

/// Transient runtime overrides, persisted so they survive a daemon restart.
public struct RuntimeState: Codable, Equatable, Sendable {
    public var topUp = false
    public var manualDischarge = false
    public var calibrationPhase: CalibrationPhase? = nil
    public var phaseStartedAt: Date? = nil
    public var lastCalibration: Date? = nil
    public var sailingLatched = false              // limit reached; drifting until limit - sailingLevel
    public var heatPaused = false
    public init() {}
}

public enum ChargeState: String, Codable, Sendable {
    case notPluggedIn, charging, limitReached, sailing, discharging, heatProtection, topUp, calibration, limiterOff, unsupported
    public var title: String {
        switch self {
        case .notPluggedIn: return "On Battery"
        case .charging: return "Charging"
        case .limitReached: return "Charge Limit Reached"
        case .sailing: return "Sailing"
        case .discharging: return "Discharging"
        case .heatProtection: return "Heat Protection"
        case .topUp: return "Top Up"
        case .calibration: return "Calibration"
        case .limiterOff: return "Limiter Off"
        case .unsupported: return "Unsupported Hardware"
        }
    }
}

public struct PowerModeStatus: Codable, Equatable, Sendable {
    public var lowPowerBattery = false
    public var lowPowerCharger = false
    public var highPowerBattery = false
    public var highPowerCharger = false
    public var highPowerSupported = false
    public init() {}
}

public struct SimmerStatus: Codable, Equatable, Sendable {
    public var helperVersion = Simmer.helperVersion
    public var backend: ChargeBackend = .none
    public var supportsDischarge = false
    public var supportsLED = false
    public var state: ChargeState = .notPluggedIn
    public var targetPercent = 80
    public var chargingInhibited = false
    public var adapterDisabled = false
    public var battery = BatterySnapshot()
    public var smcTemperatureC: Double? = nil
    public var systemPowerW: Double? = nil
    public var adapterPowerW: Double? = nil
    public var lidClosed = false
    public var sleepPrevented = false
    public var runtime = RuntimeState()
    public var calibrationPhaseEndsAt: Date? = nil
    public var powerModes = PowerModeStatus()
    public var lastError: String? = nil
    public var updatedAt = Date()
    /// The limit the daemon actually applies after desk mode / smart top-up / cheap windows.
    public var effectiveLimit = 80
    public var limitReason: LimitReason = .user
    public var capabilities = Capabilities()
    public init() {}

    public var temperatureC: Double { smcTemperatureC ?? battery.temperatureC }

    /// Tolerant decoding: the widget and app may read a status.json written by an older or newer daemon.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SimmerStatus()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) throws -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        helperVersion = try v(.helperVersion, d.helperVersion)
        backend = try v(.backend, d.backend)
        supportsDischarge = try v(.supportsDischarge, d.supportsDischarge)
        supportsLED = try v(.supportsLED, d.supportsLED)
        state = try v(.state, d.state)
        targetPercent = try v(.targetPercent, d.targetPercent)
        chargingInhibited = try v(.chargingInhibited, d.chargingInhibited)
        adapterDisabled = try v(.adapterDisabled, d.adapterDisabled)
        battery = try v(.battery, d.battery)
        smcTemperatureC = try v(.smcTemperatureC, d.smcTemperatureC)
        systemPowerW = try v(.systemPowerW, d.systemPowerW)
        adapterPowerW = try v(.adapterPowerW, d.adapterPowerW)
        lidClosed = try v(.lidClosed, d.lidClosed)
        sleepPrevented = try v(.sleepPrevented, d.sleepPrevented)
        runtime = try v(.runtime, d.runtime)
        calibrationPhaseEndsAt = try v(.calibrationPhaseEndsAt, d.calibrationPhaseEndsAt)
        powerModes = try v(.powerModes, d.powerModes)
        lastError = try v(.lastError, d.lastError)
        updatedAt = try v(.updatedAt, d.updatedAt)
        effectiveLimit = try v(.effectiveLimit, targetPercent)
        limitReason = try v(.limitReason, d.limitReason)
        capabilities = try v(.capabilities, d.capabilities)
    }
}

/// What this Mac's charge-control hardware can do (Apple silicon vs Intel T2 vs older Intel).
public struct Capabilities: Codable, Equatable, Sendable {
    public var chargeInhibit = true        // can stop/start charging on demand (CHTE / CH0B)
    public var discharge = false           // can run from battery while plugged in (CHIE / CH0I / CH0J)
    public var led = false                 // MagSafe LED (ACLC)
    public var limitOnly = false           // BCLM-only Intel: a fixed max level; no sailing/top-up timing control
    public var limitPersistsWhenOff = false // BCLM: the SMC keeps the limit during sleep / shutdown
    public var isIntel = false
    public init() {}
}

public enum DeskModeTrigger: String, Codable, CaseIterable, Sendable {
    case clamshell                 // lid closed while plugged in (external display setup)
    case pluggedHours              // plugged in continuously for deskModeAfterHours
    case clamshellOrPluggedHours
}

public struct TimeWindow: Codable, Equatable, Hashable, Sendable {
    public var startHour: Int, startMinute: Int, endHour: Int, endMinute: Int   // may wrap past midnight
    public init(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.startHour = startHour; self.startMinute = startMinute; self.endHour = endHour; self.endMinute = endMinute
    }
}

/// Why the effective limit differs from the user's limit.
public enum LimitReason: Codable, Equatable, Sendable {
    case user
    case deskMode
    case smartTopUp(departure: Date)
    case waitingForCheapWindow(start: Date)
}

/// One-shot commands from the app or CLI.
public enum SimmerCommand: Codable, Equatable, Sendable {
    case setLimit(Int)
    case setLimiterEnabled(Bool)
    case topUp(Bool)
    case discharge(Bool)
    case calibrate(Bool)
    case pause                       // limit = current percent
    case setLED(LEDMode)
    case setLowPowerMode(Bool, PowerModeScope)
    case setHighPowerMode(Bool, PowerModeScope)
    case runTask(UUID)
    case sleepNow
    /// Temporary MagSafe LED notification; the LED returns to its normal mode afterwards.
    case ledNotify(LEDPattern, repeats: Int)
    /// Remove a leftover helper of another charge-limiter tool (id from ConflictScanner). Root work.
    case removeConflict(String)
}

public enum SimmerJSON {
    public static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    public static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    public static func encode<T: Encodable>(_ v: T) -> Data { (try? encoder.encode(v)) ?? Data() }
    public static func decode<T: Decodable>(_ t: T.Type, _ d: Data) throws -> T { try decoder.decode(t, from: d) }
}

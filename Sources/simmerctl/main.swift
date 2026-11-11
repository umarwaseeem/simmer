import Foundation
import SimmerShared

// simmerctl — command-line front end for the Simmer helper (also usable from Shortcuts "Run Shell Script").

setvbuf(stdout, nil, _IOLBF, 0)
let args = Array(CommandLine.arguments.dropFirst())

let usage = """
usage: simmerctl <command> [arguments]

Status
  status [--json]                     battery, charging state and power flow
  config [--json]                     current settings
  version                             helper and CLI version

Charging
  limit <20-100>                      set the charge limit
  limiter on|off                      enable or disable the charge limiter
  topup on|off                        charge to 100% once
  discharge on|off                    run from battery down to the limit while plugged in
  calibrate start|stop                run or cancel the calibration cycle
  pause                               set the limit to the current percentage

Hardware
  led system|smart|off|custom         MagSafe LED mode
  led <state> <color>                 custom color for one state (switches to custom)
      states: charging limit sailing discharging heat topup calibration limiter-off
      colors: system off green orange blink-slow blink-fast
  lpm on|off [all|battery|charger]    Low Power Mode (default scope: all)
  hpm on|off [all|battery|charger]    High Power Mode (default scope: all)
  led blink <pattern> [repeats]       play a MagSafe LED notification (repeats 1-10, default 3)
      patterns: green orange alternate heartbeat level
  sleep                               put the Mac to sleep now

Insights (work without the helper unless noted)
  energy [--json]                     apps using the most energy (full list needs the helper)
  sleep-report [--days N] [--json]    battery drain and wakes during sleep (default 7 days)
  blockers [--json]                   processes that keep the Mac awake
  sessions [--json]                   recent on-battery sessions from Simmer's history
  charger [--json]                    can the charger keep up? cable and hub limits
  details [--json]                    cell voltages, lifetime temperatures, operating hours
  conflicts [--json]                  other charge limiters, leftover helpers, macOS Charge Limit
  fix-conflict <id>                   remove a leftover helper listed by 'conflicts' (helper)

Settings
  set <key> <value>
      sailing on|off            sailing-level 1-20         heat on|off
      heat-threshold <25-50>    auto-discharge on|off      sleep-inhibit on|off
      disable-sleep on|off      keep-limit on|off          blink-discharge on|off
      catch-up on|off           calibration-hold <0-240>   calibration-discharge <5-50>
      limit <20-100>            limiter on|off             clamshell-awake on|off
      desk-mode on|off          desk-limit <20-100>        desk-trigger clamshell|hours|either
      desk-hours <0.5-24>       smart-topup on|off         smart-lead <15-240> (minutes)
      cheap-charging on|off     cheap-floor <20-100>       cheap-window HH:MM-HH:MM[,HH:MM-HH:MM]
      bclm-offset <-10-0>       (older Intel Macs only)
      charge-control auto|smc|native   auto falls back to the macOS Charge Limit when macOS blocks SMC

Exit status: 0 on success, 1 on error, 2 on a usage error.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("simmerctl: " + message + "\n").utf8))
    exit(code)
}

func usageError(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("simmerctl: " + message + "\n\n" + usage + "\n").utf8))
    exit(2)
}

final class ReplyBox<T>: @unchecked Sendable {
    private var value: T?
    private let lock = NSLock()
    func set(_ v: T) { lock.lock(); if value == nil { value = v }; lock.unlock() }
    func get() -> T? { lock.lock(); defer { lock.unlock() }; return value }
}

let client = HelperClient()

/// Runs one XPC call and blocks until the reply arrives or 5 s pass.
func call<T>(_ op: (@escaping (Result<T, Error>) -> Void) -> Void) -> T {
    let sem = DispatchSemaphore(value: 0)
    let box = ReplyBox<Result<T, Error>>()
    op { r in box.set(r); sem.signal() }
    if sem.wait(timeout: .now() + 5) == .timedOut {
        fail("\(HelperError.timeout.localizedDescription) within 5 s. Is the Simmer helper installed and running?")
    }
    switch box.get()! {
    case .success(let v): return v
    case .failure(let e):
        var msg = e.localizedDescription
        if case HelperError.connection = e, !FileManager.default.fileExists(atPath: Simmer.helperInstallPath) {
            msg += " (helper not installed at \(Simmer.helperInstallPath); install it from the Simmer app)"
        }
        fail(msg)
    }
}

func perform(_ cmd: SimmerCommand, _ ok: String) {
    call { client.perform(cmd, $0) }
    print(ok)
}

func parseBool(_ s: String?) -> Bool {
    switch s?.lowercased() {
    case "on", "true", "yes", "1", "enable", "enabled", "start": return true
    case "off", "false", "no", "0", "disable", "disabled", "stop": return false
    default: usageError("expected on|off, got '\(s ?? "")'")
    }
}

func parseInt(_ s: String?, _ range: ClosedRange<Int>, _ what: String) -> Int {
    guard let s, let v = Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "%+"))), range.contains(v) else {
        usageError("\(what) must be an integer in \(range.lowerBound)...\(range.upperBound)")
    }
    return v
}

func parseDouble(_ s: String?, _ range: ClosedRange<Double>, _ what: String) -> Double {
    guard let s, let v = Double(s), range.contains(v) else {
        usageError("\(what) must be a number in \(Int(range.lowerBound))...\(Int(range.upperBound))")
    }
    return v
}

func parseScope(_ s: String?) -> PowerModeScope {
    guard let s else { return .all }
    guard let scope = PowerModeScope(rawValue: s.lowercased()) else { usageError("scope must be all, battery or charger") }
    return scope
}

let prettyEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
}()

func printJSON<T: Encodable>(_ v: T) {
    guard let data = try? prettyEncoder.encode(v), let s = String(data: data, encoding: .utf8) else { fail("could not encode JSON") }
    print(s)
}

func fmtW(_ w: Double?) -> String { w.map { String(format: "%.1f W", $0) } ?? "n/a" }
func onOff(_ b: Bool) -> String { b ? "on" : "off" }

func row(_ k: String, _ v: String) { print(k.padding(toLength: max(12, k.count + 2), withPad: " ", startingAt: 0) + v) }

func printStatus(_ s: SimmerStatus) {
    let b = s.battery
    row("Battery:", "\(b.percent)% (hardware \(String(format: "%.1f", b.hardwarePercent))%)")
    var state = s.state.title
    if let p = s.runtime.calibrationPhase {
        state += " - \(p.title)"
        if let end = s.calibrationPhaseEndsAt {
            let m = max(0, Int(end.timeIntervalSinceNow / 60))
            state += String(format: " (%d:%02d left)", m / 60, m % 60)
        }
    }
    row("State:", state)
    row("Limit:", "\(s.targetPercent)%" + (s.runtime.topUp ? " (top up)" : "") + limitReasonText(s))
    row("Temp:", String(format: "%.1f °C", s.temperatureC))
    let battW = b.batteryPowerW
    let battDesc = abs(battW) < 0.05 ? "0.0 W (idle)" : String(format: "%+.1f W (%@)", battW, battW > 0 ? "charging" : "discharging")
    row("Power:", "adapter \(fmtW(s.adapterPowerW)), system \(fmtW(s.systemPowerW)), battery \(battDesc)")
    if b.externalConnected {
        let name = b.adapterName.isEmpty ? "Power adapter" : b.adapterName
        row("Adapter:", "\(name)" + (b.adapterWatts > 0 ? ", \(b.adapterWatts) W" : ""))
    }
    row("Health:", String(format: "%.1f%%", b.healthPercent) + " (\(b.rawMaxCapacity) / \(b.designCapacity) mAh)")
    row("Cycles:", "\(b.cycleCount)")
    if let t = b.timeRemainingMin { row("Remaining:", String(format: "%d:%02d %@", t / 60, t % 60, b.isCharging ? "to full" : "to empty")) }
    let target = s.runtime.topUp ? 100 : s.effectiveLimit
    if b.externalConnected, let m = ChargeEstimate.minutes(to: target, battery: b) {
        row("Estimate:", "\(target)% in about \(ChargeEstimate.format(minutes: m))")
    }
    row("Flags:", "charging \(s.chargingInhibited ? "inhibited" : "allowed"), adapter \(s.adapterDisabled ? "disabled" : "enabled")" + (s.sleepPrevented ? ", sleep prevented" : ""))
    row("Backend:", "\(s.backend.rawValue), helper \(s.helperVersion)")
    if s.usingNativeLimit || s.chargeControlBlocked {
        row("Control:", s.usingNativeLimit
            ? "macOS Charge Limit" + (s.chargeControlBlocked ? " (macOS blocks direct SMC control)" : " (chosen in settings)")
            : "SMC (blocked; set charge-control auto to fall back)")
    }
    if let e = s.lastError { row("Error:", e) }
}

func limitReasonText(_ s: SimmerStatus) -> String {
    switch s.limitReason {
    case .user: return ""
    case .deskMode: return " (desk mode)"
    case .smartTopUp(let d): return " (charging to 100% before \(timeText(d)))"
    case .waitingForCheapWindow(let d): return " (cheap charging from \(timeText(d)))"
    }
}

func timeText(_ d: Date) -> String { DateFormatter.localizedString(from: d, dateStyle: .none, timeStyle: .short) }
func dateTimeText(_ d: Date) -> String { DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short) }

func describe(_ a: TaskAction) -> String {
    switch a {
    case .setLimit(let v): return "set limit \(v)%"
    case .topUp: return "top up"
    case .discharge(let v): return "discharge to \(v)%"
    case .calibrate: return "calibrate"
    case .lowPowerMode(let b): return "low power mode \(onOff(b))"
    case .highPowerMode(let b): return "high power mode \(onOff(b))"
    case .limiter(let b): return "limiter \(onOff(b))"
    }
}

func describe(_ r: TaskRecurrence) -> String {
    let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    switch r {
    case .once(let d): return "once on \(DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none))"
    case .daily: return "daily"
    case .weekly(let days): return "weekly on " + days.map { names[$0.rawValue] }.joined(separator: ",")
    case .biweekly(let d): return "every 2 weeks on \(names[d.rawValue])"
    case .monthly(let day): return "monthly on day \(day)"
    }
}

func printConfig(_ c: SimmerConfig) {
    row("limiter", onOff(c.limiterEnabled))
    row("limit", "\(c.chargeLimit)%")
    row("sailing", "\(onOff(c.sailingEnabled)) (level \(c.sailingLevel))")
    row("heat", "\(onOff(c.heatProtectionEnabled)) (threshold \(c.heatThresholdC) °C)")
    row("auto-dis.", onOff(c.automaticDischarge))
    row("sleep-inh.", onOff(c.stopChargingWhenSleeping))
    row("disable-sl.", onOff(c.disableSleepUntilLimit))
    row("keep-limit", onOff(c.keepLimitWhenQuit))
    row("led", c.ledMode.rawValue + " (blink during discharge \(onOff(c.blinkOrangeDuringDischarge)))")
    if c.ledMode == .custom {
        for (name, kp) in ledStates.sorted(by: { $0.key < $1.key }) { row("  led \(name)".padding(toLength: 18, withPad: " ", startingAt: 0), c.ledCustom[keyPath: kp].cliName) }
    }
    row("clamshell-awake", onOff(c.preventClamshellSleepWhileDischarging))
    row("calibration", "hold \(c.calibrationHoldMinutes) min, discharge to \(c.calibrationDischargeTo)%")
    row("catch-up", onOff(c.catchUpMissedTasks))
    row("desk-mode", "\(onOff(c.deskModeEnabled)) (limit \(c.deskModeLimit)%, trigger \(deskTriggerName(c.deskModeTrigger)), after \(c.deskModeAfterHours) h)")
    row("smart-topup", "\(onOff(c.smartTopUpEnabled)) (lead \(c.smartTopUpLeadMinutes) min)")
    row("cheap-charging", "\(onOff(c.cheapChargingEnabled)) (floor \(c.cheapFloorPercent)%, windows \(c.cheapWindows.map(\.cliString).joined(separator: ",")))")
    row("bclm-offset", "\(c.intelBCLMOffset) (older Intel Macs only)")
    row("charge-control", c.chargeControl.rawValue)
    print("schedule:")
    if c.schedule.isEmpty { print("  (none)") }
    for t in c.schedule {
        print(String(format: "  [%@] %@ - %@, %@ at %02d:%02d  id=%@", t.enabled ? "x" : " ", t.name, describe(t.action), describe(t.recurrence), t.hour, t.minute, t.id.uuidString))
    }
}

let ledStates: [String: WritableKeyPath<LEDCustomColors, LEDColor>] = [
    "charging": \.charging, "limit": \.limitReached, "sailing": \.sailing, "discharging": \.discharging,
    "heat": \.heatProtection, "topup": \.topUp, "calibration": \.calibration, "limiter-off": \.limiterOff,
]

func setKey(_ key: String, _ value: String?) {
    // Validate the value first (usage errors exit before the helper is contacted), then apply it.
    var probe = SimmerConfig()
    apply(key, value, to: &probe)
    var c: SimmerConfig = call { client.config($0) }
    apply(key, value, to: &c)
    c.clamp()
    call { client.setConfig(c, $0) }
    print("\(key) = \(value ?? "")")
}

func apply(_ key: String, _ value: String?, to c: inout SimmerConfig) {
    switch key.lowercased() {
    case "sailing": c.sailingEnabled = parseBool(value)
    case "sailing-level": c.sailingLevel = parseInt(value, 1...20, "sailing-level")
    case "heat": c.heatProtectionEnabled = parseBool(value)
    case "heat-threshold": c.heatThresholdC = parseDouble(value, 25...50, "heat-threshold")
    case "auto-discharge": c.automaticDischarge = parseBool(value)
    case "sleep-inhibit": c.stopChargingWhenSleeping = parseBool(value)
    case "disable-sleep": c.disableSleepUntilLimit = parseBool(value)
    case "keep-limit": c.keepLimitWhenQuit = parseBool(value)
    case "blink-discharge": c.blinkOrangeDuringDischarge = parseBool(value)
    case "catch-up": c.catchUpMissedTasks = parseBool(value)
    case "calibration-hold": c.calibrationHoldMinutes = parseInt(value, 0...240, "calibration-hold")
    case "calibration-discharge": c.calibrationDischargeTo = parseInt(value, 5...50, "calibration-discharge")
    case "limit": c.chargeLimit = parseInt(value, 20...100, "limit")
    case "limiter": c.limiterEnabled = parseBool(value)
    case "clamshell-awake": c.preventClamshellSleepWhileDischarging = parseBool(value)
    case "desk-mode": c.deskModeEnabled = parseBool(value)
    case "desk-limit": c.deskModeLimit = parseInt(value, 20...100, "desk-limit")
    case "desk-trigger":
        switch value?.lowercased() {
        case "clamshell", "lid": c.deskModeTrigger = .clamshell
        case "hours", "plugged", "plugged-hours": c.deskModeTrigger = .pluggedHours
        case "either", "both", "any", "clamshell-or-hours": c.deskModeTrigger = .clamshellOrPluggedHours
        default: usageError("desk-trigger must be clamshell, hours or either")
        }
    case "desk-hours": c.deskModeAfterHours = parseDouble(value, 0.5...24, "desk-hours")
    case "smart-topup": c.smartTopUpEnabled = parseBool(value)
    case "smart-lead": c.smartTopUpLeadMinutes = parseInt(value, 15...240, "smart-lead")
    case "cheap-charging": c.cheapChargingEnabled = parseBool(value)
    case "cheap-floor": c.cheapFloorPercent = parseInt(value, 20...100, "cheap-floor")
    case "cheap-window", "cheap-windows":
        let windows = (value ?? "").split(separator: ",").map { TimeWindow(cliString: String($0).trimmingCharacters(in: .whitespaces)) }
        guard !windows.isEmpty, windows.allSatisfy({ $0 != nil }) else { usageError("cheap-window must be HH:MM-HH:MM (24 h), comma-separated for several") }
        c.cheapWindows = windows.compactMap { $0 }
    case "bclm-offset": c.intelBCLMOffset = parseInt(value, -10...0, "bclm-offset")
    case "charge-control":
        switch value?.lowercased() {
        case "auto", "automatic": c.chargeControl = .automatic
        case "smc", "direct": c.chargeControl = .smc
        case "native", "macos": c.chargeControl = .native
        default: usageError("charge-control must be auto, smc or native")
        }
    default: usageError("unknown key '\(key)'")
    }
}

// MARK: - dispatch

guard let command = args.first?.lowercased() else { print(usage); exit(0) }
let rest = Array(args.dropFirst())
let json = rest.contains("--json")

switch command {
case "help", "-h", "--help":
    print(usage)

case "status":
    let s: SimmerStatus = call { client.status($0) }
    if json { printJSON(s) } else { printStatus(s) }

case "config":
    let c: SimmerConfig = call { client.config($0) }
    if json { printJSON(c) } else { printConfig(c) }

case "version", "--version":
    print("simmerctl \(Simmer.helperVersion)")
    let v: String = call { client.version($0) }
    print("helper \(v)")

case "limit":
    let v = parseInt(rest.first, 20...100, "limit")
    perform(.setLimit(v), "Charge limit set to \(v)%")

case "limiter":
    let on = parseBool(rest.first)
    perform(.setLimiterEnabled(on), "Limiter \(onOff(on))")

case "topup", "top-up":
    let on = rest.first.map { parseBool($0) } ?? true
    perform(.topUp(on), on ? "Top up started" : "Top up stopped")

case "discharge":
    let on = rest.first.map { parseBool($0) } ?? true
    perform(.discharge(on), on ? "Discharge started" : "Discharge stopped")

case "calibrate", "calibration":
    let on = rest.first.map { parseBool($0) } ?? true
    perform(.calibrate(on), on ? "Calibration started" : "Calibration stopped")

case "pause":
    perform(.pause, "Charge limit set to the current percentage")

case "led":
    let mode: LEDMode
    switch rest.first?.lowercased() {
    case "system": mode = .system
    case "smart": mode = .smart
    case "off", "alwaysoff", "always-off": mode = .alwaysOff
    case "custom": mode = .custom
    case "blink", "notify":
        guard let name = rest.dropFirst().first, let pattern = ledPattern(name) else {
            usageError("pattern must be one of: green, orange, alternate, heartbeat, level")
        }
        let repeats = rest.count > 2 ? parseInt(rest[2], 1...10, "repeats") : 3
        perform(.ledNotify(pattern, repeats: repeats), "MagSafe LED: \(pattern.title) x\(repeats)")
        exit(0)
    case let st? where ledStates[st] != nil:
        // led <state> <color>: set one custom color and switch to custom mode
        guard let name = rest.dropFirst().first, let color = LEDColor(cliName: name) else {
            usageError("color must be one of: " + LEDColor.allCases.map(\.cliName).joined(separator: ", "))
        }
        var c: SimmerConfig = call { client.config($0) }
        c.ledCustom[keyPath: ledStates[st]!] = color
        c.ledMode = .custom
        call { client.setConfig(c, $0) }
        print("MagSafe LED (custom): \(st) = \(color.cliName)")
        exit(0)
    default: usageError("led mode must be system, smart, off, custom, or <state> <color>")
    }
    perform(.setLED(mode), "MagSafe LED: \(mode.rawValue)")

case "lpm":
    let on = parseBool(rest.first)
    let scope = parseScope(rest.dropFirst().first)
    perform(.setLowPowerMode(on, scope), "Low Power Mode \(onOff(on)) (\(scope.rawValue))")

case "hpm":
    let on = parseBool(rest.first)
    let scope = parseScope(rest.dropFirst().first)
    perform(.setHighPowerMode(on, scope), "High Power Mode \(onOff(on)) (\(scope.rawValue))")

case "sleep":
    perform(.sleepNow, "Sleeping")

case "run", "run-task":
    guard let s = rest.first, let id = UUID(uuidString: s) else { usageError("run <task id> (see 'simmerctl config')") }
    perform(.runTask(id), "Task started")

case "set":
    guard rest.count >= 2 else { usageError("set <key> <value>") }
    setKey(rest[0], rest[1])

case "energy":
    energyCommand(json: json)

case "sleep-report", "sleepreport":
    var days = 7
    if let i = rest.firstIndex(of: "--days") { days = parseInt(rest.dropFirst(i + 1).first, 1...30, "--days") }
    sleepReport(days: days, json: json)

case "blockers":
    let b = SleepBlocker.current()
    if json { printJSON(b) } else { printBlockers(b) }

case "sessions":
    let s = BatterySession.sessions(from: BatteryHistory.load()?.samples ?? [])
    if json { printJSON(s) } else { printSessions(s) }

case "charger":
    let r = chargerReport()
    if json { printJSON(r) } else { printCharger(r) }

case "details":
    let d = BatteryDetails.read()
    if json { printJSON(d) } else { printDetails(d) }

case "conflicts":
    let c = ConflictScanner.scan()
    if json { printJSON(c) } else { printConflicts(c) }

case "fix-conflict":
    guard let id = rest.first else { usageError("fix-conflict <id> (see 'simmerctl conflicts')") }
    guard let c = ConflictScanner.scan().first(where: { $0.id == id }) else { fail("no conflict with id '\(id)' (see 'simmerctl conflicts')") }
    guard c.fixableBySimmer else { fail("Simmer cannot fix '\(c.name)'. \(c.detail)") }
    perform(.removeConflict(id), "Removed \(c.name): " + c.paths.joined(separator: ", "))

default:
    usageError("unknown command '\(command)'")
}

exit(0)

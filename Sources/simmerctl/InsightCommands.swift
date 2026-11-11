import Darwin
import Foundation
import SimmerShared

// Insight commands. They read local data (IORegistry, pmset log, history.json, energy.json) and do not
// need the helper, except `fix-conflict` and `led blink`.

func deskTriggerName(_ t: DeskModeTrigger) -> String {
    switch t { case .clamshell: return "clamshell"; case .pluggedHours: return "hours"; case .clamshellOrPluggedHours: return "either" }
}

func ledPattern(_ name: String) -> LEDPattern? {
    switch name.lowercased() {
    case "green", "blink-green", "blinkgreen": return .blinkGreen
    case "orange", "blink-orange", "blinkorange": return .blinkOrange
    case "alternate", "green-orange": return .alternate
    case "heartbeat": return .heartbeat
    case "level", "charge-level", "chargelevel": return .chargeLevel
    default: return LEDPattern(rawValue: name)
    }
}

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
func lpad(_ s: String, _ n: Int) -> String { s.count >= n ? s : String(repeating: " ", count: n - s.count) + s }

func hoursText(_ h: Double) -> String {
    let m = Int((h * 60).rounded())
    return m >= 60 ? String(format: "%dh %02dm", m / 60, m % 60) : "\(m)m"
}

// MARK: energy

func energyCommand(json: Bool) {
    var report = EnergyReport.load()
    var note: String?
    if let r = report, Date().timeIntervalSince(r.generatedAt) > 15 * 60 {
        note = "energy.json is \(Int(Date().timeIntervalSince(r.generatedAt) / 60)) min old"
    }
    if report == nil {
        // Old or missing helper: sample this user's processes for 3 s.
        let acc = EnergyAccumulator()
        let onBattery = !BatterySnapshot.read().externalConnected
        _ = acc.ingest(ProcessList.sampleAll(), time: Date(), abs: mach_absolute_time(), onBattery: onBattery)
        Thread.sleep(forTimeInterval: 3)
        report = acc.ingest(ProcessList.sampleAll(), time: Date(), abs: mach_absolute_time(), onBattery: onBattery)
        note = "the helper has not written \(Simmer.energyPath) yet; showing a 3 s sample of your own processes only"
    }
    guard let r = report else { fail("no energy data") }
    if json { printJSON(r); return }
    if let note { print("Note: \(note).") }
    print(String(format: "Energy use (last %.0f s, total %.1f W)  updated %@", r.windowSeconds, r.totalWatts1m, timeText(r.generatedAt)))
    let since = r.entries.contains { $0.energySinceUnplugWh != nil }
    print(pad("APP", 32) + lpad("NOW", 8) + lpad("1 H", 8) + lpad("CPU", 7) + lpad("WAKE/s", 8) + (since ? lpad("UNPLUG", 9) : ""))
    for e in r.entries.prefix(20) {
        var line = pad(String(e.name.prefix(31)), 32) + lpad(String(format: "%.2f W", e.watts1m), 8)
            + lpad(String(format: "%.2f W", e.watts1h), 8) + lpad(String(format: "%.0f%%", e.cpuPercent1m), 7)
            + lpad(String(format: "%.0f", e.wakeupsPerSec1m), 8)
        if since { line += lpad(e.energySinceUnplugWh.map { String(format: "%.2f Wh", $0) } ?? "", 9) }
        print(line)
    }
    if let me = r.entries.first(where: { $0.id == Simmer.helperLabel }) {
        print(String(format: "Simmer's own helper: %.3f W, %.1f%% CPU.", me.watts1m, me.cpuPercent1m))
    }
}

// MARK: sleep

func sleepReport(days: Int, json: Bool) {
    let sessions = SleepLogParser.recentSessions(days: days)
    if json { printJSON(sessions); return }
    guard !sessions.isEmpty else { print("No sleep in the last \(days) days (or pmset log is empty)."); return }
    print("Sleep in the last \(days) days (newest last)")
    print(pad("START", 18) + lpad("LENGTH", 9) + lpad("CHARGE", 12) + lpad("%/H", 6) + "  POWER  WAKES  REASON")
    for s in sessions {
        let charge = [s.percentStart, s.percentEnd].map { $0.map { "\($0)%" } ?? "?" }.joined(separator: "→")
        let rate = s.percentPerHour.map { String(format: "%.1f", $0) } ?? "-"
        let dark = s.wakes.filter(\.isDarkWake).count
        print(pad(dateTimeText(s.start), 18) + lpad(hoursText(s.hours), 9) + lpad(charge, 12) + lpad(rate, 6)
              + "  " + pad(s.onBattery ? "batt" : "AC", 5) + lpad("\(dark)", 6) + "  " + s.reason)
    }
    let batt = sessions.filter { $0.onBattery && $0.end != nil && $0.hours >= 0.5 }
    let hours = batt.reduce(0) { $0 + $1.hours }
    let lost = batt.compactMap(\.percentLost).reduce(0, +)
    if hours > 0 {
        print(String(format: "On battery: %@ asleep, %d%% used (%.2f%%/h).", hoursText(hours), lost, Double(lost) / hours))
    }
    var reasons: [String: Int] = [:]
    for s in sessions { for w in s.wakes where w.isDarkWake { reasons[w.reason, default: 0] += 1 } }
    if !reasons.isEmpty {
        print("Most common wake reasons:")
        for (r, n) in reasons.sorted(by: { $0.value > $1.value }).prefix(5) { print("  \(lpad("\(n)", 5))  \(r)") }
    }
}

func printBlockers(_ list: [SleepBlocker]) {
    guard !list.isEmpty else { print("Nothing keeps the Mac awake right now."); return }
    for b in list {
        let since = b.since.map { " since " + timeText($0) } ?? ""
        print("\(b.processName) (pid \(b.pid)): \(b.assertionType) \"\(b.name)\"\(since)")
    }
}

func printSessions(_ list: [BatterySession]) {
    guard !list.isEmpty else { print("No on-battery sessions in Simmer's history (needs the helper's history.json)."); return }
    print(pad("START", 18) + lpad("LENGTH", 9) + lpad("CHARGE", 12) + lpad("%/H", 7) + lpad("AVG W", 8))
    for s in list {
        print(pad(dateTimeText(s.start), 18) + lpad(hoursText(s.hours), 9) + lpad("\(s.percentStart)%→\(s.percentEnd)%", 12)
              + lpad(String(format: "%.1f", s.percentPerHour), 7) + lpad(String(format: "%.1f", s.averageWatts), 8))
    }
}

// MARK: charger

func chargerReport() -> ChargerReport {
    var battery = BatterySnapshot.read()
    var systemW: Double?, adapterW: Double?
    if let status = (FileManager.default.contents(atPath: Simmer.statusSnapshotPath)).flatMap({ try? SimmerJSON.decode(SimmerStatus.self, $0) }),
       Date().timeIntervalSince(status.updatedAt) < 300 {
        // While Simmer disables the adapter, macOS reports "not connected"; the daemon's flag is right.
        battery.externalConnected = battery.externalConnected || status.battery.externalConnected
    }
    if let smc = try? SMC() {
        let cc = ChargeControl(smc: smc)
        systemW = cc.systemPowerW
        adapterW = cc.adapterInputPowerW
    }
    let peak = BatteryHistory.load()?.samples.compactMap(\.systemW).max()
    return ChargerAnalyzer.report(battery: battery, systemW: systemW, adapterW: adapterW, recentPeakSystemW: peak)
}

func printCharger(_ r: ChargerReport) {
    print(r.headline)
    if !r.adapterName.isEmpty { row("Charger:", r.adapterName + (r.isUSBPD ? " (USB-C PD)" : "")) }
    row("Rating:", r.rating.rawValue)
    for d in r.details { print("  - " + d) }
}

// MARK: details

func printDetails(_ d: BatteryDetails) {
    if !d.cellVoltagesMV.isEmpty {
        row("Cells:", d.cellVoltagesMV.map { "\($0) mV" }.joined(separator: ", ") + "  (imbalance \(d.cellImbalanceMV) mV, \(d.cellBalance.rawValue))")
    }
    if !d.qmaxMAh.isEmpty { row("Qmax:", d.qmaxMAh.map { "\($0) mAh" }.joined(separator: ", ")) }
    if let t = d.lifetimeMaxTempC { row("Max temp:", String(format: "%.1f °C (lifetime)", t)) }
    if let t = d.lifetimeMinTempC { row("Min temp:", String(format: "%.1f °C (lifetime)", t)) }
    if let t = d.lifetimeAvgTempC { row("Avg temp:", String(format: "%.1f °C (lifetime)", t)) }
    if let h = d.totalOperatingHours { row("Operating:", String(format: "%.0f h (%.0f days)", h, h / 24)) }
    if let h = d.hoursAtHighCharge { row("High SoC:", String(format: "%.0f h", h)) }
    if let a = d.dailyMinSoc, let b = d.dailyMaxSoc { row("Today:", "\(a)% – \(b)%") }
    if let c = d.chemistryID { row("Chem ID:", "\(c)") }
    if let m = d.manufactureDate { row("Made:", DateFormatter.localizedString(from: m, dateStyle: .medium, timeStyle: .none)) }
    if !d.serial.isEmpty { row("Serial:", d.serial) }
}

// MARK: conflicts

func printConflicts(_ list: [Conflict]) {
    guard !list.isEmpty else { print("No conflicts: no other charge limiter, leftover helper or macOS Charge Limit found."); return }
    for c in list {
        print("\(c.name)  [id: \(c.id)]")
        print("  " + c.detail)
        if c.fixableBySimmer { print("  Fix: simmerctl fix-conflict \(c.id)") }
    }
}

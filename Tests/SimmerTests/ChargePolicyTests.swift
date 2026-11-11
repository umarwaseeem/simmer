import XCTest
@testable import SimmerShared

final class ChargePolicyTests: XCTestCase {
    func input(_ pct: Int, plugged: Bool = true, temp: Double = 30, cfg: SimmerConfig = SimmerConfig(), rt: RuntimeState = RuntimeState(), now: Date = Date()) -> PolicyInput {
        PolicyInput(config: cfg, runtime: rt, percent: pct, pluggedIn: plugged, temperatureC: temp, backend: .chte, supportsDischarge: true, now: now)
    }

    func testChargesBelowLimitAndHoldsAtLimit() {
        XCTAssertEqual(ChargePolicy.decide(input(70)).state, .charging)
        XCTAssertFalse(ChargePolicy.decide(input(70)).inhibitCharging)
        let at = ChargePolicy.decide(input(80))
        XCTAssertEqual(at.state, .limitReached); XCTAssertTrue(at.inhibitCharging); XCTAssertFalse(at.disableAdapter)
    }

    func testUnsupportedBackendDoesNothing() {
        var i = input(90); i.backend = .none
        let d = ChargePolicy.decide(i)
        XCTAssertEqual(d.state, .unsupported); XCTAssertFalse(d.inhibitCharging); XCTAssertFalse(d.disableAdapter)
    }

    func testSailingDriftsThenRecharges() {
        var cfg = SimmerConfig(); cfg.sailingEnabled = true; cfg.sailingLevel = 5
        var d = ChargePolicy.decide(input(80, cfg: cfg))
        XCTAssertTrue(d.runtime.sailingLatched)
        d = ChargePolicy.decide(input(77, cfg: cfg, rt: d.runtime))
        XCTAssertEqual(d.state, .sailing); XCTAssertTrue(d.inhibitCharging)
        d = ChargePolicy.decide(input(75, cfg: cfg, rt: d.runtime))
        XCTAssertEqual(d.state, .charging); XCTAssertFalse(d.inhibitCharging); XCTAssertFalse(d.runtime.sailingLatched)
        d = ChargePolicy.decide(input(78, cfg: cfg, rt: d.runtime))
        XCTAssertEqual(d.state, .charging, "keeps charging until the limit after unlatching")
    }

    func testHeatProtectionHysteresis() {
        var cfg = SimmerConfig(); cfg.heatProtectionEnabled = true; cfg.heatThresholdC = 35
        var d = ChargePolicy.decide(input(50, temp: 36, cfg: cfg))
        XCTAssertEqual(d.state, .heatProtection); XCTAssertTrue(d.inhibitCharging); XCTAssertEqual(d.events, [.heatProtectionStarted])
        d = ChargePolicy.decide(input(50, temp: 33.5, cfg: cfg, rt: d.runtime))
        XCTAssertEqual(d.state, .heatProtection, "still within the 2°C resume band")
        d = ChargePolicy.decide(input(50, temp: 32.9, cfg: cfg, rt: d.runtime))
        XCTAssertEqual(d.state, .charging); XCTAssertEqual(d.events, [.heatProtectionEnded])
    }

    func testManualDischargeRunsToLimitThenStops() {
        var rt = RuntimeState(); rt.manualDischarge = true
        var d = ChargePolicy.decide(input(90, rt: rt))
        XCTAssertEqual(d.state, .discharging); XCTAssertTrue(d.disableAdapter); XCTAssertTrue(d.inhibitCharging)
        d = ChargePolicy.decide(input(80, rt: d.runtime))
        XCTAssertFalse(d.disableAdapter); XCTAssertFalse(d.runtime.manualDischarge); XCTAssertEqual(d.events, [.dischargeFinished])
        XCTAssertEqual(d.state, .limitReached)
    }

    func testAutomaticDischarge() {
        var cfg = SimmerConfig(); cfg.automaticDischarge = true
        XCTAssertTrue(ChargePolicy.decide(input(85, cfg: cfg)).disableAdapter)
        XCTAssertFalse(ChargePolicy.decide(input(85, plugged: false, cfg: cfg)).disableAdapter)
    }

    func testTopUpChargesTo100AndEndsOnUnplug() {
        var rt = RuntimeState(); rt.topUp = true
        var d = ChargePolicy.decide(input(85, rt: rt))
        XCTAssertEqual(d.state, .topUp); XCTAssertFalse(d.inhibitCharging); XCTAssertEqual(d.targetPercent, 100)
        d = ChargePolicy.decide(input(100, rt: d.runtime))
        XCTAssertEqual(d.state, .topUp, "holds at 100 until unplugged")
        d = ChargePolicy.decide(input(100, plugged: false, rt: d.runtime))
        XCTAssertFalse(d.runtime.topUp); XCTAssertEqual(d.events, [.topUpEnded])
    }

    func testTopUpIgnoresHeatProtection() {
        var cfg = SimmerConfig(); cfg.heatProtectionEnabled = true
        var rt = RuntimeState(); rt.topUp = true
        XCTAssertEqual(ChargePolicy.decide(input(85, temp: 45, cfg: cfg, rt: rt)).state, .topUp)
    }

    func testLimiterOffAllowsCharging() {
        var cfg = SimmerConfig(); cfg.limiterEnabled = false
        let d = ChargePolicy.decide(input(95, cfg: cfg))
        XCTAssertEqual(d.state, .limiterOff); XCTAssertFalse(d.inhibitCharging)
    }

    func testUnpluggedPreArmsInhibit() {
        let d = ChargePolicy.decide(input(85, plugged: false))
        XCTAssertEqual(d.state, .notPluggedIn); XCTAssertTrue(d.inhibitCharging); XCTAssertFalse(d.disableAdapter)
    }

    func testDisableSleepUntilLimit() {
        var cfg = SimmerConfig(); cfg.disableSleepUntilLimit = true
        XCTAssertTrue(ChargePolicy.decide(input(60, cfg: cfg)).preventSleep)
        XCTAssertFalse(ChargePolicy.decide(input(80, cfg: cfg)).preventSleep)
    }

    func testFullCalibrationCycle() {
        var cfg = SimmerConfig(); cfg.calibrationHoldMinutes = 60; cfg.calibrationDischargeTo = 10
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var rt = RuntimeState(); rt.calibrationPhase = .chargeToFull; rt.phaseStartedAt = t0
        var d = ChargePolicy.decide(input(80, cfg: cfg, rt: rt, now: t0))
        XCTAssertEqual(d.state, .calibration); XCTAssertFalse(d.inhibitCharging); XCTAssertTrue(d.preventSleep)
        d = ChargePolicy.decide(input(100, cfg: cfg, rt: d.runtime, now: t0 + 100))
        XCTAssertEqual(d.runtime.calibrationPhase, .holdFull)
        XCTAssertEqual(d.phaseEndsAt, t0 + 100 + 3600)
        d = ChargePolicy.decide(input(100, cfg: cfg, rt: d.runtime, now: t0 + 100 + 3599))
        XCTAssertEqual(d.runtime.calibrationPhase, .holdFull)
        d = ChargePolicy.decide(input(100, cfg: cfg, rt: d.runtime, now: t0 + 100 + 3600))
        XCTAssertEqual(d.runtime.calibrationPhase, .dischargeLow); XCTAssertTrue(d.disableAdapter)
        d = ChargePolicy.decide(input(10, cfg: cfg, rt: d.runtime, now: t0 + 20000))
        XCTAssertEqual(d.runtime.calibrationPhase, .chargeToFullAgain); XCTAssertFalse(d.disableAdapter)
        d = ChargePolicy.decide(input(100, cfg: cfg, rt: d.runtime, now: t0 + 30000))
        XCTAssertEqual(d.runtime.calibrationPhase, .holdFullAgain)
        d = ChargePolicy.decide(input(100, cfg: cfg, rt: d.runtime, now: t0 + 30000 + 3600))
        XCTAssertEqual(d.runtime.calibrationPhase, .returnToLimit); XCTAssertTrue(d.disableAdapter)
        d = ChargePolicy.decide(input(80, cfg: cfg, rt: d.runtime, now: t0 + 50000))
        XCTAssertNil(d.runtime.calibrationPhase); XCTAssertEqual(d.runtime.lastCalibration, t0 + 50000)
        XCTAssertEqual(d.state, .limitReached); XCTAssertTrue(d.events.contains(.calibrationFinished))
    }

    func testSmartLED() {
        var cfg = SimmerConfig(); cfg.ledMode = .smart
        XCTAssertEqual(ChargePolicy.decide(input(60, cfg: cfg)).led, .orange)
        XCTAssertEqual(ChargePolicy.decide(input(80, cfg: cfg)).led, .green)
        var rt = RuntimeState(); rt.manualDischarge = true
        XCTAssertEqual(ChargePolicy.decide(input(90, cfg: cfg, rt: rt)).led, .orangeBlinkSlow)
        cfg.ledMode = .alwaysOff
        XCTAssertEqual(ChargePolicy.decide(input(60, cfg: cfg)).led, .off)
    }
}

final class TaskSchedulerTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func date(_ s: String) -> Date { let f = ISO8601DateFormatter(); return f.date(from: s)! }

    func testWeeklyMondayDueInWindowOnly() {
        let t = ScheduledTask(name: "x", action: .topUp, recurrence: .weekly([.mon]), hour: 5, minute: 0)
        // 2026-11-09 is a Monday
        XCTAssertNotNil(TaskScheduler.isDue(t, now: date("2026-11-09T05:01:00Z"), catchUp: false, calendar: cal))
        XCTAssertNil(TaskScheduler.isDue(t, now: date("2026-11-09T07:00:00Z"), catchUp: false, calendar: cal))
        XCTAssertNil(TaskScheduler.isDue(t, now: date("2026-11-10T05:01:00Z"), catchUp: false, calendar: cal))
    }

    func testCatchUpAfterMissedRun() {
        var t = ScheduledTask(name: "x", action: .topUp, recurrence: .daily, hour: 5, minute: 0)
        t.lastRun = date("2026-11-08T05:00:30Z")
        XCTAssertNotNil(TaskScheduler.isDue(t, now: date("2026-11-09T09:00:00Z"), catchUp: true, calendar: cal))
        XCTAssertNil(TaskScheduler.isDue(t, now: date("2026-11-09T09:00:00Z"), catchUp: false, calendar: cal))
        t.lastRun = date("2026-11-09T05:00:10Z")
        XCTAssertNil(TaskScheduler.isDue(t, now: date("2026-11-09T09:00:00Z"), catchUp: true, calendar: cal))
    }

    func testMonthlyClampsToMonthEnd() {
        let t = ScheduledTask(name: "x", action: .calibrate, recurrence: .monthly(day: 31), hour: 10, minute: 0)
        XCTAssertEqual(TaskScheduler.lastOccurrence(of: t, before: date("2026-11-30T11:00:00Z"), calendar: cal), date("2026-11-30T10:00:00Z"))
    }

    func testDisabledTaskNeverDue() {
        let t = ScheduledTask(name: "x", action: .topUp, recurrence: .daily, hour: 5, minute: 0, enabled: false)
        XCTAssertNil(TaskScheduler.isDue(t, now: date("2026-11-09T05:00:30Z"), catchUp: true, calendar: cal))
    }

    func testCommandRoundTrip() throws {
        for c: SimmerCommand in [.setLimit(70), .topUp(true), .setLowPowerMode(true, .battery), .setLED(.smart), .runTask(UUID())] {
            XCTAssertEqual(try SimmerJSON.decode(SimmerCommand.self, SimmerJSON.encode(c)), c)
        }
    }
}

final class LEDCustomTests: XCTestCase {
    func input(_ pct: Int, plugged: Bool = true, temp: Double = 30, cfg: SimmerConfig, rt: RuntimeState = RuntimeState()) -> PolicyInput {
        PolicyInput(config: cfg, runtime: rt, percent: pct, pluggedIn: plugged, temperatureC: temp, backend: .chte, supportsDischarge: true)
    }

    func testCustomColorsFollowState() {
        var cfg = SimmerConfig(); cfg.ledMode = .custom
        cfg.ledCustom.charging = .green; cfg.ledCustom.limitReached = .off; cfg.ledCustom.heatProtection = .orangeBlinkFast
        cfg.heatProtectionEnabled = true
        XCTAssertEqual(ChargePolicy.decide(input(60, cfg: cfg)).led, .green)
        XCTAssertEqual(ChargePolicy.decide(input(80, cfg: cfg)).led, .off)
        XCTAssertEqual(ChargePolicy.decide(input(60, temp: 40, cfg: cfg)).led, .orangeBlinkFast)
        XCTAssertEqual(ChargePolicy.decide(input(60, plugged: false, cfg: cfg)).led, .system)
        var rt = RuntimeState(); rt.manualDischarge = true
        XCTAssertEqual(ChargePolicy.decide(input(90, cfg: cfg, rt: rt)).led, .orangeBlinkSlow)
    }

    func testOldConfigWithoutNewKeysStillDecodes() throws {
        var old = try JSONSerialization.jsonObject(with: SimmerJSON.encode(SimmerConfig())) as! [String: Any]
        old.removeValue(forKey: "ledCustom"); old.removeValue(forKey: "preventClamshellSleepWhileDischarging")
        old["chargeLimit"] = 72
        let cfg = try SimmerJSON.decode(SimmerConfig.self, JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(cfg.chargeLimit, 72)
        XCTAssertEqual(cfg.ledCustom, LEDCustomColors())
        XCTAssertTrue(cfg.preventClamshellSleepWhileDischarging)
    }

    func testLEDColorCLINames() {
        for c in LEDColor.allCases { XCTAssertEqual(LEDColor(cliName: c.cliName), c) }
    }
}

final class HistoryRecorderTests: XCTestCase {
    func battery(_ pct: Int, maxCap: Int = 5800) -> BatterySnapshot {
        var b = BatterySnapshot(); b.present = true; b.percent = pct; b.designCapacity = 6249; b.rawMaxCapacity = maxCap
        b.rawCurrentCapacity = maxCap * pct / 100; b.hardwarePercent = Double(pct); b.cycleCount = 110
        b.voltageV = 12.4; b.amperageA = -0.5
        return b
    }

    func testSamplesRespectIntervalAndAggregateDaily() {
        var h = BatteryHistory()
        let t0 = DailyBatteryRecord.dayFormatter.date(from: "2026-11-11")!.addingTimeInterval(3600)
        XCTAssertTrue(HistoryRecorder.record(&h, battery: battery(80), tempC: 30, systemW: 8, plugged: true, now: t0))
        XCTAssertFalse(HistoryRecorder.record(&h, battery: battery(79), tempC: 40, systemW: 8, plugged: true, now: t0 + 60))
        XCTAssertTrue(HistoryRecorder.record(&h, battery: battery(70), tempC: 40, systemW: 8, plugged: false, now: t0 + 300))
        XCTAssertEqual(h.samples.count, 2)
        XCTAssertEqual(h.daily.count, 1)
        let r = h.daily[0]
        XCTAssertEqual(r.day, "2026-11-11"); XCTAssertEqual(r.samples, 2)
        XCTAssertEqual(r.avgTempC, 35); XCTAssertEqual(r.maxTempC, 40)
        XCTAssertEqual(r.minPct, 70); XCTAssertEqual(r.maxPct, 80)
        XCTAssertEqual(r.healthPercent, 92.8)
    }

    func testNewDayAndPruning() {
        var h = BatteryHistory()
        let t0 = DailyBatteryRecord.dayFormatter.date(from: "2026-11-01")!.addingTimeInterval(3600)
        HistoryRecorder.record(&h, battery: battery(80), tempC: 30, systemW: nil, plugged: true, now: t0)
        HistoryRecorder.record(&h, battery: battery(80, maxCap: 5790), tempC: 30, systemW: nil, plugged: true, now: t0 + 15 * 86_400)
        XCTAssertEqual(h.samples.count, 1, "samples older than 14 days are pruned")
        XCTAssertEqual(h.daily.map(\.day), ["2026-11-01", "2026-11-16"], "daily records are kept")
    }

    func testRoundTrip() throws {
        var h = BatteryHistory()
        HistoryRecorder.record(&h, battery: battery(80), tempC: 30.26, systemW: 7.77, plugged: true, now: Date())
        XCTAssertEqual(try SimmerJSON.decode(BatteryHistory.self, SimmerJSON.encode(h)), h)
    }
}

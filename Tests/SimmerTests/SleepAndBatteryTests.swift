import XCTest
@testable import SimmerShared

final class SleepLogParserTests: XCTestCase {
    func date(_ s: String) -> Date { SleepLogParser.timestampFormatter.date(from: s)! }

    func testParsesRealLogIntoSessions() {
        let s = SleepLogParser.parse(Fixtures.pmsetLog)
        XCTAssertEqual(s.count, 2, "the 1 s notification sleep is dropped")

        let ac = s[0]
        XCTAssertEqual(ac.start, date("2026-11-10 05:03:08 +0500"))
        XCTAssertEqual(ac.end, date("2026-11-10 13:24:08 +0500"))
        XCTAssertEqual(ac.reason, "Software Sleep", "pid suffix removed")
        XCTAssertFalse(ac.onBattery)
        XCTAssertEqual(ac.percentStart, 80); XCTAssertEqual(ac.percentEnd, 80)
        XCTAssertEqual(ac.wakes.filter(\.isDarkWake).count, 4)
        XCTAssertEqual(ac.percentLost, 0)

        let clam = s[1]
        XCTAssertEqual(clam.start, date("2026-11-11 13:20:44 +0500"))
        XCTAssertEqual(clam.end, date("2026-11-11 17:37:52 +0500"), "ends at the HID wake, not at the plug-in notification wakes")
        XCTAssertEqual(clam.reason, "Clamshell Sleep")
        XCTAssertTrue(clam.onBattery)
        XCTAssertEqual(clam.percentStart, 86); XCTAssertEqual(clam.percentEnd, 82)
        XCTAssertEqual(clam.percentLost, 4)
        XCTAssertEqual(clam.wakes.filter { !$0.isDarkWake }.map(\.reason), ["Notification", "Notification", "Notification"])
        XCTAssertEqual(clam.wakes.filter(\.isDarkWake).count, 10)
        XCTAssertEqual(clam.hours, 4.285, accuracy: 0.01)
        XCTAssertEqual(clam.percentPerHour!, 4 / clam.hours, accuracy: 0.001)
    }

    func testKeepsShortSessionsWhenAsked() {
        let all = SleepLogParser.parse(Fixtures.pmsetLog, minimumSeconds: 0)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[1].reason, "Notification Wake Back to Sleep")
        XCTAssertEqual(all[1].end!.timeIntervalSince(all[1].start), 1)
    }

    func testWakeReasonsAndDurations() {
        let s = SleepLogParser.parse(Fixtures.pmsetLog)[1]
        let dark = s.wakes.filter(\.isDarkWake)
        XCTAssertEqual(dark.first?.reason, "smc.sysState.Wake (USB-C plug)")
        XCTAssertEqual(dark.first?.durationSeconds, 0)
        XCTAssertTrue(dark.contains { $0.reason == "smc.sysState.Wake (network)" && $0.durationSeconds == 45 })
        XCTAssertTrue(dark.contains { $0.reason == "rtc/SleepService" })
        XCTAssertEqual(SleepLogParser.wakeReason("DarkWake from Deep Idle [CDNP] : due to NUB.SPMI0Sw3IRQ nub-spmi-a0.0x0B nub-spmi0.0x02 rtc/Maintenance Using BATT (Charge:85%) 45 secs"), "rtc/Maintenance")
        XCTAssertEqual(SleepLogParser.wakeReason("Wake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) USB2_wake SMC.OutboxNotEmpty nub-spmi-a0.0x0B/HID Activity Using AC (Charge:86%)"), "HID Activity")
    }

    func testUserWakeIsNeverResumed() {
        let log = """
        2026-11-11 10:00:00 +0500 Sleep               \tEntering Sleep state due to 'Idle Sleep':TCPKeepAlive=active Using Batt (Charge:90%) 600 secs
        2026-11-11 11:00:00 +0500 Wake                \tWake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) nub/HID Activity Using Batt (Charge:88%)
        2026-11-11 11:01:00 +0500 Sleep               \tEntering Sleep state due to 'Notification Wake Back to Sleep':TCPKeepAlive=active Using Batt (Charge:88%) 600 secs
        2026-11-11 12:01:00 +0500 Wake                \tWake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) nub/HID Activity Using Batt (Charge:87%)
        """
        let s = SleepLogParser.parse(log)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].percentEnd, 88)
        XCTAssertTrue(s[0].wakes.isEmpty)
    }

    func testOpenSessionAtEndOfLogAndGarbage() {
        let log = "garbage\n\n2026-11-11 10:00:00 +0500 Sleep               \tEntering Sleep state due to 'Idle Sleep' Using AC (Charge:50%)\nmore garbage"
        let s = SleepLogParser.parse(log)
        XCTAssertEqual(s.count, 1)
        XCTAssertNil(s[0].end); XCTAssertNil(s[0].percentEnd); XCTAssertFalse(s[0].onBattery)
        XCTAssertTrue(SleepLogParser.parse("").isEmpty)
    }
}

final class SleepBlockerTests: XCTestCase {
    func testFiltersAndMapsAssertions() {
        let t1 = Date(timeIntervalSince1970: 1_000), t2 = Date(timeIntervalSince1970: 2_000)
        let input: [Int32: [[String: Any]]] = [
            112: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Powerd - Prevent sleep while display is on",
                   "Process Name": "powerd", "AssertLevel": 255, "AssertStartWhen": t1],
                  ["AssertType": "InternalPreventDisplaySleep", "AssertName": "com.apple.powermanagement.delayDisplayOff",
                   "Process Name": "powerd", "AssertLevel": 255]],
            38267: [["AssertType": "NoIdleSleepAssertion", "AssertionTrueType": "PreventUserIdleSystemSleep",
                     "AssertName": "Xcode build operation", "Process Name": "xcodebuild", "AssertLevel": 255, "AssertStartWhen": t2]],
            36542: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "caffeinate command-line tool",
                     "Process Name": "caffeinate", "AssertLevel": 255, "AssertStartWhen": t1]],
            170: [["AssertType": "UserIsActive", "AssertName": "tickle", "Process Name": "WindowServer", "AssertLevel": 255]],
            9: [["AssertType": "PreventSystemSleep", "AssertName": "off", "Process Name": "x", "AssertLevel": 0]],
        ]
        let b = SleepBlocker.parse(input)
        XCTAssertEqual(b.map(\.processName), ["caffeinate", "xcodebuild"], "oldest first; powerd display and UserIsActive left out")
        XCTAssertEqual(b[1].assertionType, "PreventUserIdleSystemSleep", "true type preferred")
        XCTAssertEqual(b[1].pid, 38267)
        XCTAssertEqual(b[0].since, t1)
    }

    func testLiveReadDoesNotCrash() {
        _ = SleepBlocker.current()
    }
}

final class BatterySessionTests: XCTestCase {
    func sample(_ minutes: Double, _ pct: Int, plugged: Bool, w: Double = -10) -> HistorySample {
        HistorySample(t: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60), pct: pct, hwPct: Double(pct), tempC: 30,
                      batteryW: plugged ? 0 : w, systemW: 10, plugged: plugged, charging: false)
    }

    func testSplitsOnPluggedRunsNewestFirst() {
        var s: [HistorySample] = []
        for i in 0..<6 { s.append(sample(Double(i) * 5, 90 - i, plugged: false)) }      // session 1: 0..25 min
        s.append(sample(30, 85, plugged: true)); s.append(sample(35, 86, plugged: true))
        for i in 0..<4 { s.append(sample(40 + Double(i) * 5, 86 - i, plugged: false, w: -6)) } // session 2
        let out = BatterySession.sessions(from: s.shuffled())
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].percentStart, 86); XCTAssertEqual(out[0].percentEnd, 83)
        XCTAssertEqual(out[0].averageWatts, 6)
        XCTAssertEqual(out[1].percentStart, 90); XCTAssertEqual(out[1].percentEnd, 85)
        XCTAssertEqual(out[1].hours, 25.0 / 60, accuracy: 0.001)
        XCTAssertEqual(out[1].percentPerHour, 5 / (25.0 / 60), accuracy: 0.01)
    }

    func testGapSplitsOnlyWhenChargedInBetween() {
        // Sleep on battery: 2 h gap, level fell → same session.
        let a = [sample(0, 80, plugged: false), sample(5, 79, plugged: false), sample(125, 77, plugged: false), sample(130, 76, plugged: false)]
        XCTAssertEqual(BatterySession.sessions(from: a).count, 1)
        // Gap with a level rise → charged in between → two sessions.
        let b = [sample(0, 60, plugged: false), sample(5, 59, plugged: false), sample(125, 80, plugged: false), sample(130, 79, plugged: false)]
        let out = BatterySession.sessions(from: b)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].percentStart, 80)
    }

    func testIgnoresSingleSamples() {
        XCTAssertTrue(BatterySession.sessions(from: [sample(0, 50, plugged: false)]).isEmpty)
        XCTAssertTrue(BatterySession.sessions(from: []).isEmpty)
    }
}

final class BatteryDetailsTests: XCTestCase {
    /// Values from `ioreg -rn AppleSmartBattery -a` on the reference M5 Pro.
    static let registry: [String: Any] = [
        "Serial": "TESTSERIAL0000000A",
        "BatteryData": [
            "CellVoltage": [4116, 4115, 4113], "Qmax": [6263, 6245, 6214], "ChemID": 29795, "AlgoChemID": 29795,
            "DailyMaxSoc": 84, "DailyMinSoc": 76, "ManufactureDate": 58_481_116_722_227, "Serial": "TESTSERIAL0000000A",
            "LifetimeData": ["AverageTemperature": 263, "MaximumTemperature": 43, "MinimumTemperature": 16,
                             "TotalOperatingTime": 6620, "CycleCountLastQmax": 108,
                             "TimeAtHighSoc": Data(count: 112)] as [String: Any],
        ] as [String: Any],
    ]

    func testParsesRealValues() {
        let d = BatteryDetails.parse(Self.registry)
        XCTAssertEqual(d.cellVoltagesMV, [4116, 4115, 4113])
        XCTAssertEqual(d.cellImbalanceMV, 3)
        XCTAssertEqual(d.cellBalance, .good)
        XCTAssertEqual(d.qmaxMAh, [6263, 6245, 6214])
        XCTAssertEqual(d.chemistryID, 29795)
        XCTAssertEqual(d.lifetimeMaxTempC, 43)
        XCTAssertEqual(d.lifetimeMinTempC, 16)
        XCTAssertEqual(d.lifetimeAvgTempC, 26.3)
        XCTAssertEqual(d.totalOperatingHours, 6620)
        XCTAssertNil(d.hoursAtHighCharge, "TimeAtHighSoc layout is not documented")
        XCTAssertNil(d.manufactureDate, "Apple silicon ASCII date is not decoded")
        XCTAssertEqual(d.dailyMinSoc, 76); XCTAssertEqual(d.dailyMaxSoc, 84)
        XCTAssertEqual(d.serial, "TESTSERIAL0000000A")
    }

    func testSmartBatteryDateAndTemperatureUnits() {
        // 2019-03-15: (39 << 9) | (3 << 5) | 15
        let raw = (39 << 9) | (3 << 5) | 15
        let date = BatteryDetails.decodeManufactureDate(NSNumber(value: raw))!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: date), DateComponents(year: 2019, month: 3, day: 15))
        XCTAssertNil(BatteryDetails.decodeManufactureDate(NSNumber(value: 0)))
        XCTAssertNil(BatteryDetails.decodeManufactureDate(NSNumber(value: (5 << 9) | (13 << 5) | 1)), "month 13")
        XCTAssertEqual(BatteryDetails.temperature(430), 43)
        XCTAssertEqual(BatteryDetails.temperature(43), 43)
        XCTAssertNil(BatteryDetails.temperature(5000))
        XCTAssertNil(BatteryDetails.temperature(nil))
    }

    func testEmptyRegistryAndImbalanceLevels() {
        let d = BatteryDetails.parse([:])
        XCTAssertTrue(d.cellVoltagesMV.isEmpty); XCTAssertNil(d.lifetimeMaxTempC)
        var x = BatteryDetails(); x.cellVoltagesMV = [3900, 3950]
        XCTAssertEqual(x.cellBalance, .watch)
        x.cellVoltagesMV = [3800, 3900]
        XCTAssertEqual(x.cellBalance, .poor)
    }

    func testLiveReadIsSane() {
        let d = BatteryDetails.read()
        for v in d.cellVoltagesMV { XCTAssertTrue((2500...4600).contains(v)) }
        if let t = d.lifetimeMaxTempC { XCTAssertTrue((20...80).contains(t)) }
    }
}

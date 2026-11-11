import XCTest
@testable import SimmerShared

final class ChargerAnalyzerTests: XCTestCase {
    /// AdapterDetails of the reference Mac's Apple 96 W adapter.
    static let apple96: [String: Any] = [
        "Watts": 94, "Name": "96W USB-C Power Adapter", "Description": "pd charger", "AdapterVoltage": 20000, "Current": 4690,
        "UsbHvcHvcIndex": 3,
        "UsbHvcMenu": [["Index": 0, "MaxCurrent": 2960, "MaxVoltage": 5000], ["Index": 1, "MaxCurrent": 2970, "MaxVoltage": 9000],
                       ["Index": 3, "MaxCurrent": 4690, "MaxVoltage": 20000], ["Index": 2, "MaxCurrent": 2980, "MaxVoltage": 15000]],
    ]

    func battery(_ details: [String: Any]?, connected: Bool = true) -> BatterySnapshot {
        var b = BatterySnapshot(); b.present = true; b.externalConnected = connected
        if let details { b.applyAdapterDetails(details) }
        return b
    }

    func testParsesPDMenuSorted() {
        let b = battery(Self.apple96)
        XCTAssertEqual(b.adapterPDOptions.map(\.voltageV), [5, 9, 15, 20])
        XCTAssertEqual(b.adapterPDOptions.last!.watts, 93.8, accuracy: 0.01)
        XCTAssertEqual(b.adapterPDIndex, 3)
        XCTAssertEqual(b.adapterDescription, "pd charger")
        XCTAssertEqual(b.adapterWatts, 94)
    }

    func testExcellentWithPlentyOfHeadroom() {
        let r = ChargerAnalyzer.report(battery: battery(Self.apple96), systemW: 22, adapterW: 25, recentPeakSystemW: 60)
        XCTAssertEqual(r.rating, .excellent)
        XCTAssertEqual(r.headline, "Your 96 W charger has plenty of power")
        XCTAssertTrue(r.isUSBPD)
        XCTAssertEqual(r.negotiatedWatts, 94); XCTAssertEqual(r.voltageV, 20); XCTAssertEqual(r.currentA, 4.69, accuracy: 0.001)
        XCTAssertEqual(r.peakSystemWatts, 60)
        XCTAssertTrue(r.details.contains { $0.contains("5 V, 9 V, 15 V, 20 V") })
    }

    func testCableLimitAt60W() {
        let d: [String: Any] = ["Watts": 60, "Name": "96W USB-C Power Adapter", "Description": "pd charger", "AdapterVoltage": 20000,
                                "Current": 3000, "UsbHvcMenu": [["Index": 0, "MaxCurrent": 3000, "MaxVoltage": 5000],
                                                                ["Index": 1, "MaxCurrent": 3000, "MaxVoltage": 20000]]]
        let r = ChargerAnalyzer.report(battery: battery(d), systemW: 30, adapterW: 58, recentPeakSystemW: 50)
        XCTAssertEqual(r.headline, "Your cable limits charging to 60 W")
        XCTAssertEqual(r.rating, .good, "covers the peak, but a cable limit is never excellent")
        XCTAssertTrue(r.details.contains { $0.contains("5 A") })
        XCTAssertTrue(r.details.contains { $0.contains("almost all of its power") })
    }

    func testFiveVoltHubOrUSBA() {
        let d: [String: Any] = ["Watts": 15, "Name": "", "Description": "usb host", "AdapterVoltage": 5000, "Current": 3000]
        let r = ChargerAnalyzer.report(battery: battery(d), systemW: 18, adapterW: 15, recentPeakSystemW: 40)
        XCTAssertEqual(r.rating, .insufficient)
        XCTAssertEqual(r.headline, "Your Mac gets only 15 W from this charger")
        XCTAssertTrue(r.details.contains { $0.contains("5 V") })
    }

    func testLimitedUnderPeak() {
        let d: [String: Any] = ["Watts": 30, "Name": "30W USB-C Power Adapter", "AdapterVoltage": 20000, "Current": 1500]
        let r = ChargerAnalyzer.report(battery: battery(d), systemW: 12, adapterW: 14, recentPeakSystemW: 55)
        XCTAssertEqual(r.rating, .limited)
        XCTAssertEqual(r.headline, "Your 30 W charger can't keep up under heavy load")
        XCTAssertTrue(r.details.contains { $0.contains("67 W") }, "suggests 55 × 1.2 → 67 W")
    }

    func testInsufficientNow() {
        let d: [String: Any] = ["Watts": 30, "Name": "30W USB-C Power Adapter", "AdapterVoltage": 20000, "Current": 1500]
        let r = ChargerAnalyzer.report(battery: battery(d), systemW: 45, adapterW: 30, recentPeakSystemW: nil)
        XCTAssertEqual(r.rating, .insufficient)
        XCTAssertEqual(r.headline, "Your 30 W charger can't keep up")
    }

    func testNoCharger() {
        let r = ChargerAnalyzer.report(battery: battery(nil, connected: false), systemW: 10, adapterW: nil, recentPeakSystemW: 40)
        XCTAssertEqual(r.rating, .none)
        XCTAssertEqual(r.headline, "No charger connected")
        XCTAssertEqual(ChargerAnalyzer.ratedWatts(fromName: "Anker 65 W charger"), 65)
        XCTAssertNil(ChargerAnalyzer.ratedWatts(fromName: "pd charger"))
    }

    func testAdapterDisabledStillCountsAsConnected() {
        // With CHIE = 0x08 macOS reports ExternalConnected = No but AdapterDetails.Watts stays.
        let r = ChargerAnalyzer.report(battery: battery(Self.apple96, connected: false), systemW: 20, adapterW: 0, recentPeakSystemW: 30)
        XCTAssertNotEqual(r.rating, .none)
    }
}

final class BatterySnapshotCodingTests: XCTestCase {
    func testOldStatusWithoutNewFieldsDecodes() throws {
        let old = #"{"present":true,"percent":81,"hardwarePercent":79.5,"externalConnected":true,"isCharging":false,"fullyCharged":false,"voltageV":12.3,"amperageA":0,"temperatureC":30,"cycleCount":111,"designCapacity":6249,"rawMaxCapacity":5763,"rawCurrentCapacity":4400,"nominalCapacity":5900,"adapterWatts":94,"adapterName":"96W","adapterVoltageV":20,"adapterCurrentA":4.69,"serial":"X"}"#
        let b = try SimmerJSON.decode(BatterySnapshot.self, Data(old.utf8))
        XCTAssertEqual(b.percent, 81); XCTAssertEqual(b.adapterWatts, 94)
        XCTAssertTrue(b.adapterPDOptions.isEmpty); XCTAssertNil(b.adapterPDIndex)
    }

    func testRoundTripWithPDOptions() throws {
        var b = BatterySnapshot(); b.applyAdapterDetails(ChargerAnalyzerTests.apple96)
        let back = try SimmerJSON.decode(BatterySnapshot.self, SimmerJSON.encode(b))
        XCTAssertEqual(back, b)
        var s = SimmerStatus(); s.updatedAt = Date(timeIntervalSince1970: 1_800_000_000); s.battery = b; s.effectiveLimit = 55; s.limitReason = .deskMode; s.capabilities.limitOnly = true
        let sb = try SimmerJSON.decode(SimmerStatus.self, SimmerJSON.encode(s))
        XCTAssertEqual(sb, s)
    }

    func testEnergyReportOptionalFieldsAreTolerant() throws {
        var r = EnergyReport(); r.sampleMillis = 3.2; r.processCount = 700
        let back = try SimmerJSON.decode(EnergyReport.self, SimmerJSON.encode(r))
        XCTAssertEqual(back.sampleMillis, 3.2)
        let old = #"{"generatedAt":"2026-11-11T10:00:00Z","windowSeconds":60,"totalWatts1m":3,"entries":[]}"#
        XCTAssertNil(try SimmerJSON.decode(EnergyReport.self, Data(old.utf8)).sampleMillis)
    }
}

final class ConflictScannerTests: XCTestCase {
    func env(files: Set<String> = [], processes: [String] = [], prefs: Data? = nil, os: (Int, Int) = (26, 4)) -> ConflictEnvironment {
        ConflictEnvironment(fileExists: { files.contains($0) }, plistLabel: { _ in nil }, processPaths: { processes },
                            powerdChargingPrefs: { prefs }, osVersion: OperatingSystemVersion(majorVersion: os.0, minorVersion: os.1, patchVersion: 0))
    }

    /// Builds powerd's prefs file the way PowerUIAgent stores it (NSKeyedArchiver array of ChargeCtrlPolicy).
    func powerdPrefs(limit: Int, reason: String = "manualChargeLimit", terminated: Bool = false) throws -> Data {
        let a = NSKeyedArchiver(requiringSecureCoding: true)
        a.setClassName("ChargeCtrlPolicy", for: ChargeCtrlPolicyStandIn.self)
        a.encode(NSMutableArray(array: [ChargeCtrlPolicyStandIn(socLimit: limit, reason: reason, terminated: terminated)]),
                 forKey: NSKeyedArchiveRootObjectKey)
        a.finishEncoding()
        let prefs: [String: Any] = ["bootSessionUUID": "723F879F-DCE7-470A-B094-B0A38339A6EA", "policies": a.encodedData]
        return try PropertyListSerialization.data(fromPropertyList: prefs, format: .binary, options: 0)
    }

    func testNothingFound() {
        XCTAssertTrue(ConflictScanner.scan(environment: env()).isEmpty)
    }

    func testLeftoverCommercialHelperListsExactFiles() {
        let files: Set<String> = ["/Library/LaunchDaemons/com.apphousekitchen.aldente-pro.helper.plist",
                                  "/Library/PrivilegedHelperTools/com.apphousekitchen.aldente-pro.helper",
                                  "/Library/LaunchDaemons/com.umarwaseem.simmer.helper.plist",
                                  "/Library/PrivilegedHelperTools/com.umarwaseem.simmer.helper"]
        let c = ConflictScanner.scan(environment: env(files: files))
        XCTAssertEqual(c.count, 1, "never lists Simmer itself")
        XCTAssertEqual(c[0].id, "com.apphousekitchen.aldente-pro.helper")
        XCTAssertEqual(c[0].kind, .leftoverHelper)
        XCTAssertTrue(c[0].fixableBySimmer)
        XCTAssertEqual(c[0].paths, ["/Library/LaunchDaemons/com.apphousekitchen.aldente-pro.helper.plist",
                                    "/Library/PrivilegedHelperTools/com.apphousekitchen.aldente-pro.helper"])
    }

    func testOtherToolsAndPartialInstalls() {
        let files: Set<String> = ["/Library/LaunchDaemons/cc.chlc.batt.plist", "/Library/PrivilegedHelperTools/me.mhaeuser.batterytoolkitd",
                                  "/Library/LaunchDaemons/com.zackelia.bclm.plist"]
        let ids = Set(ConflictScanner.scan(environment: env(files: files)).map(\.id))
        XCTAssertEqual(ids, ["cc.chlc.batt", "me.mhaeuser.batterytoolkitd", "com.zackelia.bclm"])
        let batt = ConflictScanner.scan(environment: env(files: files)).first { $0.id == "cc.chlc.batt" }!
        XCTAssertEqual(batt.paths, ["/Library/LaunchDaemons/cc.chlc.batt.plist"])
        XCTAssertTrue(batt.detail.contains("/usr/local/bin/batt"))
    }

    func testRunningApps() {
        let procs = ["/Applications/AlDente.app/Contents/MacOS/AlDente", "/Applications/BatFi.app/Contents/Library/LaunchServices/software.micropixels.BatFi.Helper",
                     "/Applications/Simmer.app/Contents/MacOS/Simmer", "/usr/local/bin/battery-unrelated"]
        let c = ConflictScanner.scan(environment: env(processes: procs))
        XCTAssertEqual(Set(c.map(\.id)), ["app:commercial-limiter", "app:batfi"])
        XCTAssertTrue(c.allSatisfy { $0.kind == .runningApp && !$0.fixableBySimmer && $0.paths.isEmpty })
        XCTAssertEqual(ConflictScanner.scan(environment: env(processes: ["/opt/homebrew/bin/batt"])).map(\.id), ["app:batt"])
        XCTAssertTrue(ConflictScanner.scan(environment: env(processes: ["/usr/local/bin/battery"])).isEmpty)
    }

    func testNativeChargeLimit() throws {
        // As observed: soclimit 100 = native limit off → no conflict.
        XCTAssertTrue(ConflictScanner.scan(environment: env(prefs: try powerdPrefs(limit: 100))).isEmpty)
        let c = ConflictScanner.scan(environment: env(prefs: try powerdPrefs(limit: 80)))
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].kind, .nativeChargeLimit)
        XCTAssertEqual(c[0].name, "macOS Charge Limit (80 %)")
        XCTAssertFalse(c[0].fixableBySimmer)
        XCTAssertTrue(ConflictScanner.scan(environment: env(prefs: try powerdPrefs(limit: 80, terminated: true))).isEmpty)
        XCTAssertTrue(ConflictScanner.scan(environment: env(prefs: try powerdPrefs(limit: 80, reason: "optimizedCharging"))).isEmpty)
        XCTAssertEqual(try ConflictScanner.nativeChargeLimit(fromPrefs: try powerdPrefs(limit: 85)), .init(limit: 85, terminated: false))
    }

    func testUnreadableNativeSettingIsReportedAsUnknownOnlyOn26_4() {
        let junk = Data("not a plist".utf8)
        let c = ConflictScanner.scan(environment: env(prefs: junk))
        XCTAssertEqual(c.first?.name, "macOS Charge Limit (unknown)")
        XCTAssertTrue(c.first?.detail.contains("System Settings") ?? false)
        XCTAssertTrue(ConflictScanner.scan(environment: env(prefs: junk, os: (26, 3))).isEmpty)
    }

    func testRemovablePathRules() {
        XCTAssertTrue(ConflictScanner.isRemovablePath("/Library/LaunchDaemons/cc.chlc.batt.plist"))
        XCTAssertTrue(ConflictScanner.isRemovablePath("/Library/PrivilegedHelperTools/me.mhaeuser.batterytoolkitd"))
        XCTAssertFalse(ConflictScanner.isRemovablePath("/Library/LaunchDaemons/"))
        XCTAssertFalse(ConflictScanner.isRemovablePath("/Library/LaunchDaemons/../Preferences/x.plist"))
        XCTAssertFalse(ConflictScanner.isRemovablePath("/Library/LaunchDaemons/sub/x.plist"))
        XCTAssertFalse(ConflictScanner.isRemovablePath("/usr/local/bin/batt"))
        XCTAssertFalse(ConflictScanner.isRemovablePath("/Library/LaunchAgents/x.plist"))
        for h in ConflictScanner.knownHelperDetails {
            XCTAssertTrue(h.files.allSatisfy(ConflictScanner.isRemovablePath), h.label)
            XCTAssertNotNil(ConflictScanner.knownHelpers[h.label], "knownHelpers lists \(h.label)")
        }
    }

    func testLiveScanReadsThisMacsPowerdFile() throws {
        // Read-only; on the reference Mac the native limit is 100 % (no conflict).
        if let d = FileManager.default.contents(atPath: ConflictScanner.powerdChargingPrefsPath) {
            XCTAssertNoThrow(try ConflictScanner.nativeChargeLimit(fromPrefs: d))
        }
        _ = ConflictScanner.scan()
    }
}

final class EffectiveLimitTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Karachi")!; return c }()
    func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))! }
    func ctx(_ now: Date, plugged: Bool = true, since: Date? = nil, lid: Bool = false, dep: Date? = nil) -> LimitContext {
        LimitContext(now: now, pluggedIn: plugged, pluggedSince: since, lidClosed: lid, predictedDeparture: dep)
    }

    func testUserLimitByDefault() {
        let r = EffectiveLimit.evaluate(SimmerConfig(), ctx(at(11, 12)), calendar: cal)
        XCTAssertEqual(r.limit, 80); XCTAssertEqual(r.reason, .user)
    }

    func testSmartTopUpWithinLeadTime() {
        var c = SimmerConfig(); c.smartTopUpEnabled = true; c.smartTopUpLeadMinutes = 90
        let dep = at(12, 8, 30)
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(at(12, 7, 0), dep: dep), calendar: cal).limit, 100)
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(at(12, 7, 0), dep: dep), calendar: cal).reason, .smartTopUp(departure: dep))
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(at(12, 6, 59), dep: dep), calendar: cal).limit, 80, "before the lead time")
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(at(12, 8, 30), dep: dep), calendar: cal).limit, 80, "departure passed")
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(at(12, 7, 0), plugged: false, dep: dep), calendar: cal).limit, 80)
    }

    func testDeskModeTriggers() {
        var c = SimmerConfig(); c.deskModeEnabled = true; c.deskModeLimit = 55; c.deskModeAfterHours = 3
        let now = at(11, 15)
        c.deskModeTrigger = .clamshell
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(now, lid: true), calendar: cal).limit, 55)
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(now, since: at(11, 10)), calendar: cal).limit, 80)
        c.deskModeTrigger = .pluggedHours
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(now, since: at(11, 12)), calendar: cal).reason, .deskMode)
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(now, since: at(11, 12, 1)), calendar: cal).limit, 80)
        c.deskModeTrigger = .clamshellOrPluggedHours
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(now, lid: true), calendar: cal).limit, 55)
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(now, plugged: false, lid: true), calendar: cal).limit, 80)
        c.deskModeLimit = 90
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(now, lid: true), calendar: cal).reason, .user, "never above the user limit")
    }

    func testSmartTopUpBeatsDeskMode() {
        var c = SimmerConfig(); c.deskModeEnabled = true; c.deskModeTrigger = .clamshell; c.smartTopUpEnabled = true
        let dep = at(12, 9)
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(at(12, 8), lid: true, dep: dep), calendar: cal).limit, 100)
    }

    func testCheapWindows() {
        var c = SimmerConfig(); c.cheapChargingEnabled = true; c.cheapFloorPercent = 40
        c.cheapWindows = [TimeWindow(startHour: 23, startMinute: 0, endHour: 6, endMinute: 0)]
        let r = EffectiveLimit.evaluate(c, ctx(at(11, 15)), calendar: cal)
        XCTAssertEqual(r.limit, 40)
        XCTAssertEqual(r.reason, .waitingForCheapWindow(start: at(11, 23)))
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(at(11, 23, 30)), calendar: cal).limit, 80)
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(at(12, 5, 59)), calendar: cal).limit, 80)
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(at(12, 6, 0)), calendar: cal).limit, 40)
        // Desk mode wins over cheap windows.
        c.deskModeEnabled = true; c.deskModeTrigger = .clamshell; c.deskModeLimit = 55
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(at(11, 15), lid: true), calendar: cal).limit, 55)
        // Floor above the limit → user.
        c.deskModeEnabled = false; c.cheapFloorPercent = 90
        XCTAssertEqual(EffectiveLimit.evaluate(c, ctx(at(11, 15)), calendar: cal).reason, .user)
    }

    func testTimeWindowParsingAndContains() {
        let w = TimeWindow(cliString: "22:30-06:15")!
        XCTAssertEqual(w.cliString, "22:30-06:15")
        XCTAssertTrue(w.contains(minuteOfDay: 23 * 60)); XCTAssertTrue(w.contains(minuteOfDay: 6 * 60 + 14))
        XCTAssertFalse(w.contains(minuteOfDay: 6 * 60 + 15)); XCTAssertFalse(w.contains(minuteOfDay: 12 * 60))
        XCTAssertTrue(TimeWindow(cliString: "00:00-00:00")!.contains(minuteOfDay: 700), "start == end = all day")
        XCTAssertNil(TimeWindow(cliString: "25:00-06:00")); XCTAssertNil(TimeWindow(cliString: "1-2")); XCTAssertNil(TimeWindow(cliString: "x"))
        XCTAssertEqual(w.nextStart(after: at(11, 23), calendar: cal), at(12, 22, 30))
    }
}

final class DeparturePredictorTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Karachi")!; return c }()
    func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))! }

    /// Plugged overnight from 22:00, unplugged at `h:m` the next morning, 5-minute samples.
    func night(_ day: Int, unplugH h: Int, _ m: Int) -> [HistorySample] {
        var out: [HistorySample] = []
        var t = at(day - 1, 22)
        let end = at(day, h, m)
        while t < end { out.append(HistorySample(t: t, pct: 80, hwPct: 80, tempC: 30, batteryW: 0, systemW: 5, plugged: true, charging: false)); t += 300 }
        for i in 0..<6 { out.append(HistorySample(t: end + Double(i) * 300, pct: 79 - i, hwPct: 79, tempC: 30, batteryW: -8, systemW: 8, plugged: false, charging: false)) }
        return out
    }

    func testPredictsSameWeekdayCluster() {
        // Mondays 2 and 9 November 2026 (and the Wednesday in between, which is ignored for Monday).
        let samples = night(2, unplugH: 8, 20) + night(9, unplugH: 8, 50) + night(4, unplugH: 13, 0)
        XCTAssertEqual(DeparturePredictor.unplugEvents(samples: samples).count, 3)
        let now = at(15, 20)   // Sunday evening
        XCTAssertEqual(DeparturePredictor.nextDeparture(samples: samples, now: now, calendar: cal), at(16, 8, 35), "median of 08:20 and 08:50")
    }

    func testNoPatternWhenTooFarApartOrSingle() {
        let apart = night(2, unplugH: 8, 0) + night(9, unplugH: 9, 0)
        XCTAssertNil(DeparturePredictor.nextDeparture(samples: apart, now: at(15, 20), calendar: cal))
        XCTAssertNil(DeparturePredictor.nextDeparture(samples: night(2, unplugH: 8, 0), now: at(15, 20), calendar: cal))
        XCTAssertNil(DeparturePredictor.nextDeparture(samples: [], now: at(15, 20), calendar: cal))
    }

    func testShortPluggedRunsAreNotDepartures() {
        var s: [HistorySample] = []
        for d in [2, 9] {
            let start = at(d, 8)
            for i in 0..<5 { s.append(HistorySample(t: start + Double(i) * 300, pct: 50, hwPct: 50, tempC: 30, batteryW: 0, systemW: 5, plugged: true, charging: true)) }
            s.append(HistorySample(t: start + 1500, pct: 50, hwPct: 50, tempC: 30, batteryW: -5, systemW: 5, plugged: false, charging: false))
        }
        XCTAssertTrue(DeparturePredictor.unplugEvents(samples: s).isEmpty, "25 min plugged < 30 min")
    }

    func testTodayLaterStillCounts() {
        let samples = night(2, unplugH: 18, 0) + night(9, unplugH: 18, 10)
        XCTAssertEqual(DeparturePredictor.nextDeparture(samples: samples, now: at(16, 12), calendar: cal), at(16, 18, 5))
        XCTAssertEqual(DeparturePredictor.nextDeparture(samples: samples, now: at(16, 19), calendar: cal), at(23, 18, 5))
    }

    func testPluggedSince() {
        let s = night(9, unplugH: 8, 0).filter(\.plugged)
        XCTAssertEqual(DeparturePredictor.pluggedSince(samples: s, now: s.last!.t + 60), at(8, 22))
        XCTAssertNil(DeparturePredictor.pluggedSince(samples: s, now: s.last!.t + 3600), "stale history")
        XCTAssertNil(DeparturePredictor.pluggedSince(samples: night(9, unplugH: 8, 0), now: at(9, 8, 30)), "newest sample unplugged")
    }
}

final class LEDPatternTests: XCTestCase {
    func testPatternsStayWithinRateAndTime() {
        for p in LEDPattern.allCases {
            for r in [0, 1, 3, 50] {
                let steps = LEDPatternPlayer.steps(p, repeats: r, percent: 80)
                XCTAssertFalse(steps.isEmpty)
                XCTAssertLessThanOrEqual(steps.reduce(0) { $0 + $1.seconds }, LEDPatternPlayer.maxSeconds + 0.001)
                XCTAssertTrue(steps.allSatisfy { $0.seconds >= 0.25 }, "at most 4 writes per second")
                XCTAssertFalse(steps.contains { $0.color == .system }, "restoring the LED is the engine's job")
            }
        }
    }

    func testShapes() {
        XCTAssertEqual(LEDPatternPlayer.steps(.blinkGreen, repeats: 2, percent: 0),
                       [.init(.green, 0.4), .init(.off, 0.4), .init(.green, 0.4), .init(.off, 0.4)])
        XCTAssertEqual(LEDPatternPlayer.steps(.alternate, repeats: 1, percent: 0).map(\.color), [.green, .orange])
        let level = LEDPatternPlayer.steps(.chargeLevel, repeats: 1, percent: 74)
        XCTAssertEqual(level.filter { $0.color == .green }.count, 7)
        XCTAssertEqual(level.last, .init(.off, 1.0))
        XCTAssertEqual(LEDPatternPlayer.steps(.chargeLevel, repeats: 1, percent: 2).filter { $0.color == .green }.count, 1)
    }
}

import XCTest
@testable import SimmerShared

/// In-memory SMC with the key sets of the three hardware families.
final class FakeSMC: SMCAccess {
    var keys: [String: (type: String, bytes: [UInt8])]
    var writes: [(String, [UInt8])] = []
    let byteOrder: SMCByteOrder
    init(_ keys: [String: (String, [UInt8])], byteOrder: SMCByteOrder) {
        self.keys = keys.mapValues { (type: $0.0, bytes: $0.1) }
        self.byteOrder = byteOrder
    }
    func keyInfo(_ key: String) throws -> SMCKeyInfo {
        guard let k = keys[key] else { throw SMCError.keyNotFound(key) }
        return SMCKeyInfo(size: k.bytes.count, type: k.type)
    }
    func read(_ key: String) throws -> [UInt8] {
        guard let k = keys[key] else { throw SMCError.keyNotFound(key) }
        return k.bytes
    }
    func write(_ key: String, _ bytes: [UInt8]) throws {
        guard let k = keys[key] else { throw SMCError.keyNotFound(key) }
        guard k.bytes.count == bytes.count else { throw SMCError.badSize(key, k.bytes.count, bytes.count) }
        keys[key] = (k.type, bytes); writes.append((key, bytes))
    }

    /// M5 Pro, macOS 26.4 (verified keys).
    static func appleSiliconCHTE() -> FakeSMC {
        FakeSMC(["CHTE": ("ui32", [0, 0, 0, 0]), "CHIE": ("hex_", [0]), "ACLC": ("ui8 ", [0]), "MSLD": ("ui8 ", [0]),
                 "TB0T": ("flt ", Array(withUnsafeBytes(of: Float(31.5).bitPattern.littleEndian, Array.init))),
                 "PSTR": ("flt ", Array(withUnsafeBytes(of: Float(22.25).bitPattern.littleEndian, Array.init)))], byteOrder: .little)
    }
    /// Intel MacBook Pro with T2 (CH0B family, CH0I adapter control, MagSafe-less).
    static func intelT2() -> FakeSMC {
        FakeSMC(["CH0B": ("hex_", [0]), "CH0C": ("hex_", [0]), "CH0I": ("hex_", [0]), "BCLM": ("ui8 ", [100]),
                 "TB0T": ("sp78", [0x1F, 0x80]), "PSTR": ("sp96", [0x05, 0x40])], byteOrder: .big)
    }
    /// Older Intel MacBook (BCLM only, MagSafe 2 LED).
    static func intelBCLM() -> FakeSMC {
        FakeSMC(["BCLM": ("ui8 ", [100]), "ACLC": ("ui8 ", [0]), "TB0T": ("sp78", [0x1E, 0x00])], byteOrder: .big)
    }
}

final class SMCValueTests: XCTestCase {
    func testIntegerByteOrder() {
        XCTAssertEqual(SMCValue.decode([0x34, 0x12], type: "ui16", byteOrder: .little), 0x1234)
        XCTAssertEqual(SMCValue.decode([0x12, 0x34], type: "ui16", byteOrder: .big), 0x1234)
        XCTAssertEqual(SMCValue.decode([1, 0, 0, 0], type: "ui32", byteOrder: .little), 1)
        XCTAssertEqual(SMCValue.decode([0, 0, 0, 1], type: "ui32", byteOrder: .big), 1)
        XCTAssertEqual(SMCValue.decode([0xFF, 0xFE], type: "si16", byteOrder: .big), -2)
        XCTAssertEqual(SMCValue.decode([0xFE, 0xFF], type: "si16", byteOrder: .little), -2)
        XCTAssertEqual(SMCValue.decode([0xFF, 0xFF, 0xFF, 0xFE], type: "si32", byteOrder: .big), -2)
        XCTAssertNil(SMCValue.decode([1], type: "ui16", byteOrder: .big))
    }

    func testFixedPointAndFloat() {
        XCTAssertEqual(SMCValue.decode([0x1F, 0x80], type: "sp78", byteOrder: .big), 31.5)
        XCTAssertEqual(SMCValue.decode([0x1F, 0x80], type: "sp78", byteOrder: .little), 31.5, "fixed point is big endian on both")
        XCTAssertEqual(SMCValue.decode([0x05, 0x40], type: "sp96", byteOrder: .big), 21)
        XCTAssertEqual(SMCValue.decode([0x07, 0xD0], type: "fpe2", byteOrder: .big), 500)
        XCTAssertEqual(SMCValue.decode([0xFF, 0x00], type: "sp78", byteOrder: .big), -1)
        let f = Array(withUnsafeBytes(of: Float(12.5).bitPattern.littleEndian, Array.init))
        XCTAssertEqual(SMCValue.decode(f, type: "flt ", byteOrder: .big), 12.5)
        XCTAssertEqual(SMCValue.decode([7], type: "ui8 ", byteOrder: .big), 7)
        XCTAssertNil(SMCValue.decode([1, 2], type: "ch8*", byteOrder: .big))
        XCTAssertEqual(SMCValue.encodeUInt(0x0102, size: 2, byteOrder: .big), [1, 2])
        XCTAssertEqual(SMCValue.encodeUInt(0x0102, size: 2, byteOrder: .little), [2, 1])
        XCTAssertEqual(SMCValue.encodeUInt(80, size: 1, byteOrder: .big), [80])
    }

    func testPlatform() {
        XCTAssertEqual(HardwarePlatform(isAppleSilicon: true).smcByteOrder, .little)
        XCTAssertEqual(HardwarePlatform(isAppleSilicon: false).smcByteOrder, .big)
        #if arch(arm64)
        XCTAssertTrue(HardwarePlatform.current.isAppleSilicon)
        #endif
    }
}

final class ChargeBackendTests: XCTestCase {
    func testAppleSiliconCHTE() throws {
        let smc = FakeSMC.appleSiliconCHTE()
        let cc = ChargeControl(access: smc, platform: .init(isAppleSilicon: true))
        XCTAssertEqual(cc.backend, .chte)
        XCTAssertTrue(cc.supportsDischarge); XCTAssertTrue(cc.hasLED)
        let caps = cc.capabilities
        XCTAssertTrue(caps.chargeInhibit); XCTAssertTrue(caps.discharge); XCTAssertTrue(caps.led)
        XCTAssertFalse(caps.limitOnly); XCTAssertFalse(caps.isIntel)
        try cc.setChargingInhibited(true)
        XCTAssertEqual(smc.keys["CHTE"]!.bytes, [1, 0, 0, 0]); XCTAssertTrue(cc.isChargingInhibited())
        try cc.setAdapterDisabled(true)
        XCTAssertEqual(smc.keys["CHIE"]!.bytes, [0x08]); XCTAssertTrue(cc.isAdapterDisabled())
        XCTAssertEqual(cc.batteryTemperatureC, 31.5)
        XCTAssertEqual(cc.systemPowerW, 22.25)
        XCTAssertThrowsError(try cc.applyHardwareLimit(80))
        XCTAssertNil(cc.readHardwareLimit())
    }

    func testIntelT2UsesCH0BFamily() throws {
        let smc = FakeSMC.intelT2()
        let cc = ChargeControl(access: smc, platform: .init(isAppleSilicon: false))
        XCTAssertEqual(cc.backend, .ch0b, "CH0B wins over BCLM")
        let caps = cc.capabilities
        XCTAssertTrue(caps.isIntel); XCTAssertTrue(caps.chargeInhibit); XCTAssertTrue(caps.discharge)
        XCTAssertFalse(caps.led); XCTAssertFalse(caps.limitOnly)
        try cc.setChargingInhibited(true)
        XCTAssertEqual(smc.writes.map(\.0), ["CH0B", "CH0C"])
        XCTAssertEqual(smc.keys["CH0C"]!.bytes, [0x02])
        try cc.setAdapterDisabled(true)
        XCTAssertEqual(smc.keys["CH0I"]!.bytes, [0x01])
        try cc.setAdapterDisabled(false)
        XCTAssertFalse(cc.isAdapterDisabled())
        XCTAssertEqual(cc.batteryTemperatureC, 31.5, "big-endian sp78")
        XCTAssertEqual(cc.systemPowerW, 21)
    }

    func testCH0JPreferredOverCH0I() throws {
        let smc = FakeSMC.intelT2(); smc.keys["CH0J"] = ("hex_", [0])
        let cc = ChargeControl(access: smc, platform: .init(isAppleSilicon: false))
        try cc.setAdapterDisabled(true)
        XCTAssertEqual(smc.keys["CH0J"]!.bytes, [0x20]); XCTAssertEqual(smc.keys["CH0I"]!.bytes, [0])
        XCTAssertTrue(cc.isAdapterDisabled())
    }

    func testIntelBCLMLimitOnly() throws {
        let smc = FakeSMC.intelBCLM()
        let cc = ChargeControl(access: smc, platform: .init(isAppleSilicon: false))
        XCTAssertEqual(cc.backend, .bclm)
        let caps = cc.capabilities
        XCTAssertTrue(caps.limitOnly); XCTAssertTrue(caps.limitPersistsWhenOff); XCTAssertTrue(caps.isIntel)
        XCTAssertFalse(caps.chargeInhibit); XCTAssertFalse(caps.discharge); XCTAssertTrue(caps.led)

        // Inhibit is a no-op: BCLM is never toggled for sailing or heat protection.
        try cc.setChargingInhibited(true)
        XCTAssertTrue(smc.writes.isEmpty)
        XCTAssertFalse(cc.isChargingInhibited())
        XCTAssertThrowsError(try cc.setAdapterDisabled(true)) { e in
            XCTAssertTrue("\(e)".contains("cannot run from the battery"))
        }
        XCTAssertNoThrow(try cc.setAdapterDisabled(false), "enabling the adapter is always safe")

        XCTAssertEqual(try cc.applyHardwareLimit(80), 77, "default offset −3")
        XCTAssertEqual(smc.keys["BCLM"]!.bytes, [77])
        XCTAssertEqual(try cc.applyHardwareLimit(80), 77)
        XCTAssertEqual(smc.writes.count, 1, "written once; unchanged value is not rewritten")
        cc.bclmOffset = 0
        XCTAssertEqual(try cc.applyHardwareLimit(80), 80)
        XCTAssertEqual(try cc.applyHardwareLimit(100), 100)
        XCTAssertEqual(cc.readHardwareLimit(), 100)
        XCTAssertEqual(smc.writes.count, 3)
    }

    func testBCLMValue() {
        XCTAssertEqual(ChargeControl.bclmValue(forLimit: 80, offset: -3), 77)
        XCTAssertEqual(ChargeControl.bclmValue(forLimit: 100, offset: -3), 100, "100 = no limit, never offset")
        XCTAssertEqual(ChargeControl.bclmValue(forLimit: 21, offset: -3), 20)
        XCTAssertEqual(ChargeControl.bclmValue(forLimit: 99, offset: 0), 99)
    }

    func testNoBackend() {
        let cc = ChargeControl(access: FakeSMC([:], byteOrder: .little), platform: .init(isAppleSilicon: true))
        XCTAssertEqual(cc.backend, .none)
        XCTAssertFalse(cc.capabilities.chargeInhibit); XCTAssertFalse(cc.capabilities.led)
        XCTAssertNoThrow(try cc.setChargingInhibited(true))
        XCTAssertNil(cc.batteryTemperatureC)
    }

    func testOldConfigGetsDefaultBCLMOffsetAndClamp() throws {
        let c = try SimmerJSON.decode(SimmerConfig.self, Data(#"{"chargeLimit":70}"#.utf8))
        XCTAssertEqual(c.intelBCLMOffset, -3)
        var d = c; d.intelBCLMOffset = 5; d.cheapWindows = [TimeWindow(startHour: 30, startMinute: 99, endHour: -1, endMinute: 0)]; d.clamp()
        XCTAssertEqual(d.intelBCLMOffset, 0)
        XCTAssertEqual(d.cheapWindows, [TimeWindow(startHour: 23, startMinute: 59, endHour: 0, endMinute: 0)])
    }
}

final class BCLMPolicyTests: XCTestCase {
    func input(_ pct: Int, plugged: Bool = true, cfg: SimmerConfig = SimmerConfig(), rt: RuntimeState = RuntimeState(), temp: Double = 30) -> PolicyInput {
        PolicyInput(config: cfg, runtime: rt, percent: pct, pluggedIn: plugged, temperatureC: temp, backend: .bclm, supportsDischarge: false)
    }

    func testStatesAndTarget() {
        XCTAssertEqual(ChargePolicy.decide(input(70)).state, .charging)
        XCTAssertEqual(ChargePolicy.decide(input(80)).state, .limitReached)
        XCTAssertEqual(ChargePolicy.decide(input(80)).targetPercent, 80)
        XCTAssertEqual(ChargePolicy.decide(input(80, plugged: false)).state, .notPluggedIn)
        var off = SimmerConfig(); off.limiterEnabled = false
        XCTAssertEqual(ChargePolicy.decide(input(80, cfg: off)).targetPercent, 100)
        XCTAssertEqual(ChargePolicy.decide(input(80, cfg: off)).state, .limiterOff)
    }

    func testNoSailingHeatTopUpOrDischarge() {
        var cfg = SimmerConfig(); cfg.sailingEnabled = true; cfg.heatProtectionEnabled = true; cfg.automaticDischarge = true
        var rt = RuntimeState(); rt.topUp = true; rt.manualDischarge = true; rt.calibrationPhase = .holdFull; rt.heatPaused = true
        let d = ChargePolicy.decide(input(90, cfg: cfg, rt: rt, temp: 45))
        XCTAssertEqual(d.state, .limitReached)
        XCTAssertEqual(d.targetPercent, 80, "top up ignored")
        XCTAssertFalse(d.inhibitCharging); XCTAssertFalse(d.disableAdapter); XCTAssertFalse(d.preventSleep)
        XCTAssertFalse(d.runtime.topUp); XCTAssertFalse(d.runtime.manualDischarge); XCTAssertNil(d.runtime.calibrationPhase)
        XCTAssertFalse(d.runtime.sailingLatched); XCTAssertFalse(d.runtime.heatPaused)
        XCTAssertEqual(d.events, [.heatProtectionEnded])
    }

    func testSmartLEDOnBCLM() {
        var cfg = SimmerConfig(); cfg.ledMode = .smart
        XCTAssertEqual(ChargePolicy.decide(input(70, cfg: cfg)).led, .orange)
        XCTAssertEqual(ChargePolicy.decide(input(80, cfg: cfg)).led, .green)
    }
}

final class EnergyTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func p(_ pid: Int32, _ path: String, start: UInt64 = 1, j: Double, cpuS: Double = 0, wake: UInt64 = 0) -> ProcessSample {
        ProcessSample(pid: pid, path: path, startAbs: start, energyNJ: UInt64(j * 1e9), cpuNS: UInt64(cpuS * 1e9), wakeups: wake)
    }
    func accumulator() -> EnergyAccumulator {
        EnergyAccumulator(grouper: EnergyGrouper(bundleInfo: { path in
            path.hasSuffix("Google Chrome.app") ? ("com.google.Chrome", "Google Chrome") : (nil, nil)
        }, responsiblePID: { pid in pid == 30 ? 10 : nil }))
    }
    let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"

    func testOutermostAppBundle() {
        XCTAssertEqual(EnergyGrouper.outermostAppBundle(chromeHelper), "/Applications/Google Chrome.app")
        XCTAssertEqual(EnergyGrouper.outermostAppBundle("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"), "/System/Library/CoreServices/Finder.app")
        XCTAssertNil(EnergyGrouper.outermostAppBundle("/usr/libexec/trustd"))
        XCTAssertEqual(EnergyGrouper.cleanName("\u{200E}WhatsApp "), "WhatsApp")
    }

    func testGroupsHelpersDeltasAndWatts() {
        let acc = accumulator()
        let paths: [Int32: String] = [10: chrome]
        XCTAssertNil(acc.ingest([p(10, chrome, j: 100), p(11, chromeHelper, j: 50), p(20, "/usr/libexec/trustd", j: 5)],
                                time: t0, abs: 1000, onBattery: false, pathOfPID: { paths[$0] }))
        let r = acc.ingest([p(10, chrome, j: 160, cpuS: 6, wake: 600), p(11, chromeHelper, j: 80, cpuS: 3),
                            p(20, "/usr/libexec/trustd", j: 11),
                            p(30, "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent", start: 2000, j: 6)],
                           time: t0 + 60, abs: 2_000_000, onBattery: false, pathOfPID: { paths[$0] })!
        XCTAssertEqual(r.windowSeconds, 60)
        let c = r.entries.first { $0.id == "com.google.Chrome" }!
        XCTAssertEqual(c.name, "Google Chrome"); XCTAssertTrue(c.isApp); XCTAssertEqual(c.bundlePath, "/Applications/Google Chrome.app")
        XCTAssertEqual(c.pidCount, 3, "main app, helper, and the XPC service it is responsible for")
        XCTAssertEqual(c.watts1m, (60 + 30 + 6) / 60.0, accuracy: 0.001, "new process counts fully")
        XCTAssertEqual(c.cpuPercent1m, 9 / 60.0 * 100, accuracy: 0.01)
        XCTAssertEqual(c.wakeupsPerSec1m, 10)
        XCTAssertNil(c.energySinceUnplugWh)
        let t = r.entries.first { $0.id == "/usr/libexec/trustd" }!
        XCTAssertEqual(t.name, "trustd"); XCTAssertFalse(t.isApp); XCTAssertEqual(t.watts1m, 0.1, accuracy: 0.001)
        XCTAssertEqual(r.totalWatts1m, (96 + 6) / 60.0, accuracy: 0.001)
        XCTAssertEqual(r.entries.first?.id, "com.google.Chrome", "sorted by watts")
        XCTAssertEqual(r.processCount, 4)
    }

    func testPidReuseIsNotADelta() {
        let acc = accumulator()
        _ = acc.ingest([p(20, "/usr/bin/a", start: 5, j: 1000)], time: t0, abs: 100, onBattery: false)
        let r = acc.ingest([p(20, "/usr/bin/b", start: 7, j: 3)], time: t0 + 60, abs: 50, onBattery: false)!
        // The new process started before the previous sample's abs time (50 < 100 is impossible in reality, so
        // it is treated as unknown history) → no energy counted, no negative delta.
        XCTAssertEqual(r.entries.first { $0.id == "/usr/bin/b" }?.watts1m, 0)
    }

    func testRollingHourAndSinceUnplug() {
        let acc = accumulator()
        var j = 0.0
        var reports: [EnergyReport] = []
        for i in 0...70 {
            let watts = i <= 10 ? 10.0 : 1.0
            if i > 0 { j += watts * 60 }
            if let r = acc.ingest([p(20, "/usr/bin/x", j: j)], time: t0 + Double(i) * 60, abs: 1, onBattery: i >= 65) { reports.append(r) }
        }
        let last = reports.last!.entries[0]
        XCTAssertEqual(last.watts1m, 1, accuracy: 0.001)
        XCTAssertEqual(last.watts1h, 1, accuracy: 0.001, "the 10 W minutes are older than an hour")
        let mid = reports[19].entries[0]   // i = 20: 10 × 10 W + 10 × 1 W over 20 min
        XCTAssertEqual(mid.watts1h, 5.5, accuracy: 0.001)
        XCTAssertEqual(last.energySinceUnplugWh!, 6 * 60.0 / 3600, accuracy: 0.0001, "six minutes at 1 W since unplug")
        XCTAssertNil(reports[60].entries[0].energySinceUnplugWh)
    }

    func testTopEntriesKeepSimmer() {
        let acc = accumulator(); acc.maxEntries = 2
        let s0 = [p(1, "/a", j: 0), p(2, "/b", j: 0), p(3, "/c", j: 0), p(4, Simmer.helperInstallPath, j: 0)]
        _ = acc.ingest(s0, time: t0, abs: 1, onBattery: false)
        let r = acc.ingest([p(1, "/a", j: 30), p(2, "/b", j: 20), p(3, "/c", j: 10), p(4, Simmer.helperInstallPath, j: 0.06)],
                           time: t0 + 60, abs: 2, onBattery: false)!
        XCTAssertEqual(r.entries.map(\.id), ["/a", "/b", Simmer.helperLabel])
        XCTAssertEqual(r.entries.last?.name, "Simmer helper")
        XCTAssertEqual(r.entries.last!.watts1m, 0.001, accuracy: 0.0001)
    }

    func testLiveSamplerIsFast() {
        let t = Date()
        let s = ProcessList.sampleAll()
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.contains { $0.pid == getpid() })
        XCTAssertLessThan(Date().timeIntervalSince(t), 0.5, "well under the 50 ms budget even in debug; loose bound for CI")
    }
}

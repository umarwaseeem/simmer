import Foundation
import IOKit

extension BatteryDetails {
    static func readFromRegistry() -> BatteryDetails {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return BatteryDetails() }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let d = props?.takeRetainedValue() as? [String: Any] else { return BatteryDetails() }
        return parse(d)
    }

    /// Pure: builds the details from the AppleSmartBattery property dictionary.
    ///
    /// Units, checked on an M5 Pro (bq40z651 gauge, 111 cycles, macOS 26.4) against realistic ranges:
    /// - CellVoltage: mV per cell (4116, 4115, 4113 at 80 %). Qmax: mAh per cell (6263, 6245, 6214; design 6249).
    /// - LifetimeData.MaximumTemperature / MinimumTemperature: whole °C (43 and 16). Read as tenths they would
    ///   give a lifetime maximum of 4.3 °C, which is impossible.
    /// - LifetimeData.AverageTemperature: tenths of °C (263 = 26.3 °C). Read as whole °C it would be impossible.
    ///   Because the units differ between fields (and may differ on other gauges), any value above 100 is
    ///   treated as tenths of °C and any value at or below 100 as whole °C.
    /// - LifetimeData.TotalOperatingTime: hours. 6620 h ≈ 9 months, which fits 111 cycles; as minutes it
    ///   would be 110 h, too short for 111 cycles. The 28 counters in TimeAtHighSoc also add up to 6614,
    ///   which matches 6620 h, so both use hours.
    /// - TimeAtHighSoc (112 bytes = 28 little-endian UInt32) is a histogram of operating hours that sums to the
    ///   total operating time. It looks like 4 rows × 7 columns (one axis temperature bands, the other
    ///   state-of-charge bands), but the axis order and the band edges are not documented and one battery is
    ///   not enough to tell them apart. `hoursAtHighCharge` therefore stays nil — never guess.
    /// - ManufactureDate: on Intel / Smart Battery gauges it is the SBS 16-bit date
    ///   ((year − 1980) << 9 | month << 5 | day), which is decoded. On Apple silicon it is a 48-bit value whose
    ///   bytes are ASCII digits (here 0x353032303433 = "502043"); the layout of those digits (lot code vs. date)
    ///   is not documented, so it stays nil there.
    static func parse(_ d: [String: Any]) -> BatteryDetails {
        var r = BatteryDetails()
        let bd = (d["BatteryData"] as? [String: Any]) ?? [:]
        func ints(_ v: Any?) -> [Int] { (v as? [NSNumber])?.map(\.intValue) ?? [] }
        func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }

        r.cellVoltagesMV = ints(bd["CellVoltage"]).filter { $0 > 0 }
        r.qmaxMAh = ints(bd["Qmax"]).filter { $0 > 0 }
        r.serial = (bd["Serial"] as? String) ?? (d["Serial"] as? String) ?? ""
        if let chem = int(bd["ChemID"]) ?? int(bd["AlgoChemID"]), chem > 0 { r.chemistryID = chem }
        if let v = int(bd["DailyMinSoc"]), (0...100).contains(v) { r.dailyMinSoc = v }
        if let v = int(bd["DailyMaxSoc"]), (0...100).contains(v) { r.dailyMaxSoc = v }
        r.manufactureDate = decodeManufactureDate(bd["ManufactureDate"] ?? d["ManufactureDate"])

        if let life = bd["LifetimeData"] as? [String: Any] {
            r.lifetimeMaxTempC = temperature(int(life["MaximumTemperature"]))
            r.lifetimeMinTempC = temperature(int(life["MinimumTemperature"]))
            r.lifetimeAvgTempC = temperature(int(life["AverageTemperature"]))
            if let h = int(life["TotalOperatingTime"]), h > 0 { r.totalOperatingHours = Double(h) }
        }
        return r
    }

    /// > 100 → tenths of °C; otherwise whole °C. Values outside −40...100 °C are rejected.
    static func temperature(_ raw: Int?) -> Double? {
        guard let raw, raw != 0 else { return nil }
        let c = abs(raw) > 100 ? Double(raw) / 10 : Double(raw)
        return (-40...100).contains(c) ? c : nil
    }

    /// Smart Battery Data Specification date (16 bit). Anything else → nil.
    static func decodeManufactureDate(_ v: Any?) -> Date? {
        guard let raw = (v as? NSNumber)?.intValue, raw > 0, raw <= 0xFFFF else { return nil }
        let day = raw & 0x1F, month = (raw >> 5) & 0x0F, year = 1980 + (raw >> 9)
        guard (1...31).contains(day), (1...12).contains(month), (2000...2060).contains(year) else { return nil }
        var c = DateComponents(); c.year = year; c.month = month; c.day = day; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)
    }
}

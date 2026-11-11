import Foundation
import IOKit

/// Extra charger facts the app reads itself from AppleSmartBattery (read-only, no root):
/// the USB-PD voltage options ("UsbHvcMenu"), the active option, and adapter identity.
struct ChargerDetails: Equatable, Sendable {
    struct PDOption: Equatable, Identifiable, Sendable {
        var index: Int
        var voltageV: Double
        var currentA: Double
        var watts: Double { voltageV * currentA }
        var id: Int { index }
    }

    var options: [PDOption] = []
    var activeIndex: Int?
    var manufacturer = ""
    var serial = ""
    var firmware = ""
    var isWireless = false
    var description = ""

    static func read() -> ChargerDetails {
        var r = ChargerDetails()
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return r }
        defer { IOObjectRelease(svc) }
        guard let a = IORegistryEntryCreateCFProperty(svc, "AdapterDetails" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else { return r }
        func int(_ k: String, _ d: [String: Any]) -> Int? { (d[k] as? NSNumber)?.intValue }
        if let menu = a["UsbHvcMenu"] as? [[String: Any]] {
            r.options = menu.compactMap { m in
                guard let v = int("MaxVoltage", m), let c = int("MaxCurrent", m), v > 0 else { return nil }
                return PDOption(index: int("Index", m) ?? 0, voltageV: Double(v) / 1000, currentA: Double(c) / 1000)
            }.sorted { $0.voltageV < $1.voltageV }
        }
        r.activeIndex = int("UsbHvcHvcIndex", a)
        r.manufacturer = (a["Manufacturer"] as? String) ?? ""
        r.serial = (a["SerialString"] as? String) ?? ""
        r.firmware = (a["FwVersion"] as? String) ?? ""
        r.isWireless = (a["IsWireless"] as? Bool) ?? false
        r.description = (a["Description"] as? String) ?? ""
        return r
    }
}

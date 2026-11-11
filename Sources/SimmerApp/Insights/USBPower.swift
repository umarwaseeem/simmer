import Foundation
import IOKit

/// Read-only USB power facts from the IORegistry (no root):
/// - `IOUSBHostDevice` entries: name, vendor, speed and `UsbPowerSinkAllocation` (mA reserved at 5 V).
/// - `AppleSmartBattery` → `PowerOutDetails`: live power the Mac sends out of each USB-C port.
struct USBSnapshot: Equatable, Sendable {
    struct Device: Equatable, Identifiable, Sendable {
        var locationID: Int
        var name: String
        var vendor: String
        var speed: Int?             // 0 low, 1 full, 2 high, 3 super, 4 super+ (IOUSBHostFamily "Device Speed")
        var allocationMA: Int?      // UsbPowerSinkAllocation
        var isHub: Bool
        var depth: Int              // hubs and their children, for indentation
        var id: Int { locationID }
        var allocationW: Double? { allocationMA.map { Double($0) * 5 / 1000 } }

        var speedText: String? {
            switch speed {
            case 0: return "USB 1 (1.5 Mb/s)"
            case 1: return "USB 1 (12 Mb/s)"
            case 2: return "USB 2 (480 Mb/s)"
            case 3: return "USB 3 (5 Gb/s)"
            case 4: return "USB 3 (10 Gb/s)"
            case 5: return "USB 3 (20 Gb/s)"
            default: return nil
            }
        }
    }

    struct PortOut: Equatable, Identifiable, Sendable {
        var port: Int
        var watts: Double
        var voltageV: Double
        var currentA: Double
        var maxCurrentA: Double?
        var id: Int { port }
    }

    var devices: [Device] = []
    var ports: [PortOut] = []
    var totalOutW: Double { ports.reduce(0) { $0 + $1.watts } }

    static func read() -> USBSnapshot {
        var s = USBSnapshot()
        s.devices = readDevices()
        s.ports = readPortsOut()
        return s
    }

    private static func readDevices() -> [Device] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        var out: [Device] = []
        while case let svc = IOIteratorNext(iter), svc != 0 {
            defer { IOObjectRelease(svc) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let d = props?.takeRetainedValue() as? [String: Any] else { continue }
            func int(_ k: String) -> Int? { (d[k] as? NSNumber)?.intValue }
            let name = (d["USB Product Name"] as? String) ?? (d["kUSBProductString"] as? String) ?? "USB device"
            let loc = int("locationID") ?? Int(truncatingIfNeeded: svc)
            let cls = int("bDeviceClass")
            let isHub = cls == 9 || name.localizedCaseInsensitiveContains("hub")
            // Each hub tier uses one nibble of the location ID below the bus byte.
            var depth = 0
            var rest = loc & 0x00FF_FFFF
            while rest & 0x00F0_0000 != 0 { depth += 1; rest = (rest << 4) & 0x00FF_FFFF }
            out.append(Device(locationID: loc, name: name, vendor: (d["USB Vendor Name"] as? String) ?? (d["kUSBVendorString"] as? String) ?? "",
                              speed: int("Device Speed"), allocationMA: int("UsbPowerSinkAllocation"), isHub: isHub, depth: max(0, depth - 1)))
        }
        return out.sorted { $0.locationID < $1.locationID }
    }

    private static func readPortsOut() -> [PortOut] {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return [] }
        defer { IOObjectRelease(svc) }
        guard let list = IORegistryEntryCreateCFProperty(svc, "PowerOutDetails" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            func int(_ k: String) -> Int? { (d[k] as? NSNumber)?.intValue }
            guard let port = int("PortIndex") else { return nil }
            let mw = int("Watts") ?? int("FilteredPower") ?? 0
            let mv = int("ConfiguredVoltage") ?? int("AdapterVoltage") ?? 0
            return PortOut(port: port, watts: Double(mw) / 1000, voltageV: Double(mv) / 1000,
                           currentA: Double(int("Current") ?? 0) / 1000,
                           maxCurrentA: int("ConfiguredCurrent").map { Double($0) / 1000 })
        }
        .sorted { $0.port < $1.port }
    }
}

import Foundation
import IOKit
import IOKit.ps

/// One USB Power Delivery voltage/current option the charger offers (AdapterDetails.UsbHvcMenu).
public struct PowerDeliveryOption: Codable, Equatable, Sendable {
    public var voltageV: Double
    public var currentA: Double
    public var watts: Double { voltageV * currentA }
    public init(voltageV: Double, currentA: Double) { self.voltageV = voltageV; self.currentA = currentA }
}

/// Snapshot of the AppleSmartBattery IORegistry entry. Readable as any user.
public struct BatterySnapshot: Codable, Equatable, Sendable {
    public var present = false
    public var percent = 0                // macOS-reported (CurrentCapacity)
    public var hardwarePercent = 0.0       // AppleRawCurrentCapacity / AppleRawMaxCapacity
    public var externalConnected = false
    public var isCharging = false
    public var fullyCharged = false
    public var voltageV = 0.0
    public var amperageA = 0.0             // + charging, - discharging
    public var batteryPowerW: Double { voltageV * amperageA }
    public var temperatureC = 0.0
    public var cycleCount = 0
    public var designCapacity = 0          // mAh
    public var rawMaxCapacity = 0          // mAh
    public var rawCurrentCapacity = 0      // mAh
    public var nominalCapacity = 0         // mAh
    public var healthPercent: Double { designCapacity > 0 ? Double(rawMaxCapacity) / Double(designCapacity) * 100 : 0 }
    public var timeRemainingMin: Int? = nil   // to empty or to full
    public var adapterWatts = 0
    public var adapterName = ""
    public var adapterVoltageV = 0.0
    public var adapterCurrentA = 0.0
    public var serial = ""
    /// AdapterDetails.Description, e.g. "pd charger".
    public var adapterDescription = ""
    /// USB-PD options the charger offers (empty for non-PD adapters or older daemons).
    public var adapterPDOptions: [PowerDeliveryOption] = []
    /// Index into `adapterPDOptions` of the option in use (AdapterDetails.UsbHvcHvcIndex).
    public var adapterPDIndex: Int? = nil

    public init() {}

    /// Tolerant decoding: status.json may come from an older or newer daemon.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BatterySnapshot()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        present = v(.present, d.present)
        percent = v(.percent, d.percent)
        hardwarePercent = v(.hardwarePercent, d.hardwarePercent)
        externalConnected = v(.externalConnected, d.externalConnected)
        isCharging = v(.isCharging, d.isCharging)
        fullyCharged = v(.fullyCharged, d.fullyCharged)
        voltageV = v(.voltageV, d.voltageV)
        amperageA = v(.amperageA, d.amperageA)
        temperatureC = v(.temperatureC, d.temperatureC)
        cycleCount = v(.cycleCount, d.cycleCount)
        designCapacity = v(.designCapacity, d.designCapacity)
        rawMaxCapacity = v(.rawMaxCapacity, d.rawMaxCapacity)
        rawCurrentCapacity = v(.rawCurrentCapacity, d.rawCurrentCapacity)
        nominalCapacity = v(.nominalCapacity, d.nominalCapacity)
        timeRemainingMin = v(.timeRemainingMin, d.timeRemainingMin)
        adapterWatts = v(.adapterWatts, d.adapterWatts)
        adapterName = v(.adapterName, d.adapterName)
        adapterVoltageV = v(.adapterVoltageV, d.adapterVoltageV)
        adapterCurrentA = v(.adapterCurrentA, d.adapterCurrentA)
        serial = v(.serial, d.serial)
        adapterDescription = v(.adapterDescription, d.adapterDescription)
        adapterPDOptions = v(.adapterPDOptions, d.adapterPDOptions)
        adapterPDIndex = v(.adapterPDIndex, d.adapterPDIndex)
    }

    /// Reads AdapterDetails fields (pure, unit tested).
    public mutating func applyAdapterDetails(_ a: [String: Any]) {
        func num(_ k: String) -> Int? { (a[k] as? NSNumber)?.intValue }
        adapterWatts = num("Watts") ?? 0
        adapterName = (a["Name"] as? String) ?? (a["Description"] as? String) ?? ""
        adapterDescription = (a["Description"] as? String) ?? ""
        adapterVoltageV = Double(num("AdapterVoltage") ?? 0) / 1000
        adapterCurrentA = Double(num("Current") ?? 0) / 1000
        let menu = (a["UsbHvcMenu"] as? [[String: Any]]) ?? []
        adapterPDOptions = menu
            .sorted { (($0["Index"] as? NSNumber)?.intValue ?? 0) < (($1["Index"] as? NSNumber)?.intValue ?? 0) }
            .compactMap { o in
                guard let mv = (o["MaxVoltage"] as? NSNumber)?.intValue, let mc = (o["MaxCurrent"] as? NSNumber)?.intValue,
                      mv > 0, mc > 0 else { return nil }
                return PowerDeliveryOption(voltageV: Double(mv) / 1000, currentA: Double(mc) / 1000)
            }
        adapterPDIndex = adapterPDOptions.isEmpty ? nil : num("UsbHvcHvcIndex")
    }

    public static func read() -> BatterySnapshot {
        var s = BatterySnapshot()
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return s }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let d = props?.takeRetainedValue() as? [String: Any] else { return s }
        func int(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        s.present = (d["BatteryInstalled"] as? Bool) ?? true
        s.percent = int("CurrentCapacity")
        s.externalConnected = (d["ExternalConnected"] as? Bool) ?? false
        s.isCharging = (d["IsCharging"] as? Bool) ?? false
        s.fullyCharged = (d["FullyCharged"] as? Bool) ?? false
        s.voltageV = Double(int("Voltage")) / 1000
        s.amperageA = Double(Int64(truncatingIfNeeded: (d["Amperage"] as? NSNumber)?.int64Value ?? 0)) / 1000
        s.temperatureC = Double(int("Temperature")) / 100
        s.cycleCount = int("CycleCount")
        s.designCapacity = int("DesignCapacity")
        s.rawMaxCapacity = int("AppleRawMaxCapacity")
        s.rawCurrentCapacity = int("AppleRawCurrentCapacity")
        s.nominalCapacity = int("NominalChargeCapacity")
        s.serial = (d["Serial"] as? String) ?? ""
        if s.rawMaxCapacity > 0 { s.hardwarePercent = min(100, Double(s.rawCurrentCapacity) / Double(s.rawMaxCapacity) * 100) }
        let t = s.isCharging ? int("AvgTimeToFull") : int("AvgTimeToEmpty")
        s.timeRemainingMin = (t > 0 && t < 65535) ? t : nil
        if let a = d["AdapterDetails"] as? [String: Any] { s.applyAdapterDetails(a) }
        return s
    }
}

/// Calls `handler` on the main run loop whenever the power source changes.
public final class PowerSourceObserver {
    private var source: CFRunLoopSource?
    private let handler: () -> Void
    public init(_ handler: @escaping () -> Void) {
        self.handler = handler
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PowerSourceObserver>.fromOpaque(ctx).takeUnretainedValue().handler()
        }, ctx)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }
    deinit { if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) } }
}

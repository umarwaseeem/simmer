import Foundation
import IOKit

/// The Mac's model identifier (sysctl hw.model, e.g. "Mac17,9") and its marketing name.
/// Apple silicon Macs store the marketing name in the device tree ("IODeviceTree:/product" → product-name);
/// Intel Macs fall back to a small built-in table, then to the identifier.
struct MacModel: Equatable, Sendable {
    var identifier: String
    var marketingName: String?

    var displayName: String { marketingName ?? Self.table[identifier] ?? identifier }

    static let current: MacModel = {
        MacModel(identifier: sysctlString("hw.model") ?? "Mac", marketingName: deviceTreeProductName())
    }()

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func deviceTreeProductName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        let s = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Intel MacBooks (no device-tree name). Apple silicon Macs report their own name.
    static let table: [String: String] = [
        "MacBookPro16,1": "MacBook Pro (16-inch, 2019)",
        "MacBookPro16,4": "MacBook Pro (16-inch, 2019)",
        "MacBookPro16,2": "MacBook Pro (13-inch, 2020, Four Thunderbolt 3 ports)",
        "MacBookPro16,3": "MacBook Pro (13-inch, 2020, Two Thunderbolt 3 ports)",
        "MacBookPro15,1": "MacBook Pro (15-inch, 2018/2019)",
        "MacBookPro15,3": "MacBook Pro (15-inch, 2019)",
        "MacBookPro15,2": "MacBook Pro (13-inch, 2018/2019, Four Thunderbolt 3 ports)",
        "MacBookPro15,4": "MacBook Pro (13-inch, 2019, Two Thunderbolt 3 ports)",
        "MacBookPro14,1": "MacBook Pro (13-inch, 2017, Two Thunderbolt 3 ports)",
        "MacBookPro14,2": "MacBook Pro (13-inch, 2017, Four Thunderbolt 3 ports)",
        "MacBookPro14,3": "MacBook Pro (15-inch, 2017)",
        "MacBookPro13,1": "MacBook Pro (13-inch, 2016, Two Thunderbolt 3 ports)",
        "MacBookPro13,2": "MacBook Pro (13-inch, 2016, Four Thunderbolt 3 ports)",
        "MacBookPro13,3": "MacBook Pro (15-inch, 2016)",
        "MacBookAir9,1": "MacBook Air (Retina, 13-inch, 2020)",
        "MacBookAir8,2": "MacBook Air (Retina, 13-inch, 2019)",
        "MacBookAir8,1": "MacBook Air (Retina, 13-inch, 2018)",
        "MacBookAir7,2": "MacBook Air (13-inch, 2015–2017)",
        "MacBook10,1": "MacBook (Retina, 12-inch, 2017)",
    ]
}

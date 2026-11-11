import Foundation
import Darwin

/// Power of the main parts of an Apple silicon chip, in watts, averaged over one sample window.
struct ComponentPowerSample: Equatable, Sendable {
    var cpuW = 0.0
    var gpuW = 0.0
    var aneW = 0.0
    var dramW = 0.0
    var windowSeconds = 0.0
    var takenAt = Date()
    var totalW: Double { cpuW + gpuW + aneW + dramW }
}

/// Reads the "Energy Model" group of IOReport, the same private counters that powermetrics, macmon and asitop
/// use. It needs no root. The library is loaded with dlopen so that a missing symbol fails softly.
final class ComponentPowerReader: @unchecked Sendable {
    private typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSubscription = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary,
                                                           UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> OpaquePointer?
    private typealias CreateSamples = @convention(c) (OpaquePointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias GetString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias GetInt = @convention(c) (CFDictionary, Int32) -> Int64

    private let createSamples: CreateSamples
    private let createDelta: CreateSamplesDelta
    private let channelName: GetString
    private let unitLabel: GetString
    private let integerValue: GetInt
    private let subscription: OpaquePointer
    private let channels: CFMutableDictionary
    private let lock = NSLock()

    static let libraryPath = "/usr/lib/libIOReport.dylib"

    /// Fails (nil) on Intel Macs, or when the private library or its channels are missing.
    init?() {
        #if arch(x86_64)
        return nil
        #else
        guard let h = dlopen(Self.libraryPath, RTLD_NOW) else { return nil }
        func sym<T>(_ name: String, _ t: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: t)
        }
        guard let copy = sym("IOReportCopyChannelsInGroup", CopyChannelsInGroup.self),
              let sub = sym("IOReportCreateSubscription", CreateSubscription.self),
              let samples = sym("IOReportCreateSamples", CreateSamples.self),
              let delta = sym("IOReportCreateSamplesDelta", CreateSamplesDelta.self),
              let name = sym("IOReportChannelGetChannelName", GetString.self),
              let unit = sym("IOReportChannelGetUnitLabel", GetString.self),
              let int = sym("IOReportSimpleGetIntegerValue", GetInt.self),
              let group = copy("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
              let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(group), group) else { return nil }
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let s = sub(nil, mutable, &subbed, 0, nil) else { return nil }
        _ = subbed   // owned by IOReport; not released here (macmon does the same)
        createSamples = samples; createDelta = delta; channelName = name; unitLabel = unit; integerValue = int
        subscription = s; channels = mutable
        #endif
    }

    /// Blocks for `seconds` and returns the average power over that window. Call off the main thread.
    func sample(seconds: Double = 1) -> ComponentPowerSample? {
        lock.lock(); defer { lock.unlock() }
        guard let a = createSamples(subscription, channels, nil)?.takeRetainedValue() else { return nil }
        let t0 = Date()
        Thread.sleep(forTimeInterval: seconds)
        guard let b = createSamples(subscription, channels, nil)?.takeRetainedValue() else { return nil }
        let dt = Date().timeIntervalSince(t0)
        guard dt > 0.05, let d = createDelta(a, b, nil)?.takeRetainedValue() as NSDictionary?,
              let list = d["IOReportChannels"] as? [NSDictionary] else { return nil }

        var r = ComponentPowerSample(windowSeconds: dt, takenAt: Date())
        for ch in list {
            let cf = ch as CFDictionary
            guard let name = channelName(cf)?.takeUnretainedValue() as String? else { continue }
            let unit = (unitLabel(cf)?.takeUnretainedValue() as String?) ?? "mJ"
            let joules = Double(integerValue(cf, 0)) * Self.scale(unit)
            let w = joules / dt
            // Names differ per chip: "CPU Energy" (or "DIE_n_CPU Energy"), "GPU Energy", "ANE…", "DRAM…".
            if name.hasSuffix("CPU Energy") { r.cpuW += w }
            else if name == "GPU Energy" { r.gpuW += w }
            else if name.hasPrefix("ANE") && !name.contains("_SRAM") { r.aneW += w }
            else if name.hasPrefix("DRAM") { r.dramW += w }
        }
        return r
    }

    private static func scale(_ unit: String) -> Double {
        switch unit.trimmingCharacters(in: .whitespaces) {
        case "nJ": return 1e-9
        case "uJ", "µJ": return 1e-6
        case "mJ": return 1e-3
        case "J": return 1
        default: return 1e-3
        }
    }
}

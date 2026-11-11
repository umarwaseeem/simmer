import Foundation
import ObjectiveC

/// How Simmer stops charging at the limit.
public enum ChargeControlMode: String, Codable, CaseIterable, Sendable {
    /// Direct SMC control when it works; the macOS Charge Limit when macOS blocks it (macOS 27+).
    case automatic
    /// Always write the SMC charging keys (all features).
    case smc
    /// Always use the macOS Charge Limit (80–100% in steps; no discharge, sailing or heat pause).
    case native

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .smc: return "Simmer direct (SMC)"
        case .native: return "macOS Charge Limit"
        }
    }
}

/// Maps Simmer's limit onto the targets the macOS Charge Limit accepts.
public enum NativeLimitMapper {
    /// The smallest available target at or above `limit`; the lowest one if `limit` is below all of them.
    public static func target(for limit: Int, available: [Int]) -> Int {
        let sorted = available.filter { (1...100).contains($0) }.sorted()
        guard let lowest = sorted.first else { return 100 }
        if limit <= lowest { return lowest }
        return sorted.first(where: { $0 >= limit }) ?? 100
    }
}

/// The macOS Charge Limit ("manual charge limit", MCL) behind System Settings → Battery → Charging,
/// reached through the private `PowerUISmartChargeClient` of PowerUI.framework (macOS 26.4+).
///
/// It runs per user (PowerUIAgent), so call it from the app, not from the root daemon.
/// Everything is optional: on older systems `isSupported` is false and setters return an error.
public final class NativeChargeLimit: @unchecked Sendable {
    public static let shared = NativeChargeLimit()

    private let client: AnyObject?
    private let lock = NSLock()

    private static let frameworkPath = "/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI"

    private init() {
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil,
              let cls = NSClassFromString("PowerUISmartChargeClient"),
              let allocMethod = class_getClassMethod(cls, NSSelectorFromString("alloc")) else { client = nil; return }
        let initSel = NSSelectorFromString("initWithClientName:")
        guard class_respondsToSelector(cls, initSel) else { client = nil; return }
        typealias AllocFn = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
        typealias InitFn = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
        let allocated = unsafeBitCast(method_getImplementation(allocMethod), to: AllocFn.self)(cls, NSSelectorFromString("alloc"))
        let initImp = class_getMethodImplementation(cls, initSel)
        // alloc returns +1; init consumes it and returns +1, which we keep.
        client = unsafeBitCast(initImp, to: InitFn.self)(allocated.takeUnretainedValue(), initSel, "Simmer" as NSString)?
            .takeRetainedValue()
    }

    private func imp(_ name: String) -> (AnyObject, Selector, IMP)? {
        guard let c = client else { return nil }
        let sel = NSSelectorFromString(name)
        guard c.responds(to: sel), let m = class_getMethodImplementation(type(of: c), sel) else { return nil }
        return (c, sel, m)
    }

    /// True when this macOS has the Charge Limit feature and Simmer can reach it.
    public var isSupported: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let (c, sel, m) = imp("isMCLSupported") else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(m, to: Fn.self)(c, sel)
    }

    /// Targets the user can pick (for example 80, 85, 90, 95, 100).
    public func availableLimits() -> [Int] {
        lock.lock(); defer { lock.unlock() }
        guard let (c, sel, m) = imp("availableChargeLimitsWithError:") else { return [] }
        typealias Fn = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Unmanaged<AnyObject>?
        var err: NSError?
        let arr = unsafeBitCast(m, to: Fn.self)(c, sel, &err)?.takeUnretainedValue() as? [NSNumber]
        return (arr ?? []).map(\.intValue).sorted()
    }

    /// The current target, and whether the limit is switched on. nil when unavailable.
    public func current() -> (limit: Int, enabled: Bool)? {
        lock.lock(); defer { lock.unlock() }
        guard let (c, sel, m) = imp("getMCLLimitWithError:"), let (c2, sel2, m2) = imp("isMCLCurrentlyEnabled:") else { return nil }
        typealias LimitFn = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
        typealias EnabledFn = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt64
        var e1: NSError?, e2: NSError?
        let limit = Int(unsafeBitCast(m, to: LimitFn.self)(c, sel, &e1))
        let on = unsafeBitCast(m2, to: EnabledFn.self)(c2, sel2, &e2) != 0
        if e1 != nil || limit == 0 { return nil }
        return (limit, on)
    }

    /// Sets the target (must be one of `availableLimits()`); 100 means "no limit".
    @discardableResult
    public func set(limit: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        if limit >= 100 {
            return call("disableMCL:")
        }
        if let err = call("enableMCL:") { return err }
        guard let (c, sel, m) = imp("setMCLLimit:error:") else { return "The macOS Charge Limit is not available on this Mac" }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
        var err: NSError?
        let ok = unsafeBitCast(m, to: Fn.self)(c, sel, UInt8(clamping: limit), &err)
        return ok ? nil : (err?.localizedDescription ?? "macOS refused the charge limit \(limit)%")
    }

    private func call(_ name: String) -> String? {
        guard let (c, sel, m) = imp(name) else { return "The macOS Charge Limit is not available on this Mac" }
        typealias Fn = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
        var err: NSError?
        let ok = unsafeBitCast(m, to: Fn.self)(c, sel, &err)
        return ok ? nil : (err?.localizedDescription ?? "macOS refused \(name)")
    }
}

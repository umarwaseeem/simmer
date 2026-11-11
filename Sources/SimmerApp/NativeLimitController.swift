import Foundation
import SimmerShared

/// Applies Simmer's limit through the macOS Charge Limit when the helper reports `usingNativeLimit`
/// (chosen in settings, or automatic fallback when macOS 27+ blocks direct SMC control).
///
/// The macOS limit accepts only some targets (for example 80, 85, 90, 95, 100), so Simmer picks the
/// nearest one at or above its own limit. Top Up, calibration and "limiter off" release it (100%).
/// It lives in the app because PowerUIAgent runs per user; the limit itself persists in macOS.
@MainActor
final class NativeLimitController: ObservableObject {
    static let shared = NativeLimitController()

    @Published private(set) var active = false
    @Published private(set) var appliedLimit: Int?
    @Published private(set) var availableLimits: [Int] = []
    @Published private(set) var lastError: String?

    /// Remembers that Simmer changed the macOS setting, so it can hand it back when the mode ends.
    private let ownedKey = "nativeLimitOwnedBySimmer"
    private var owned: Bool {
        get { UserDefaults.standard.bool(forKey: ownedKey) }
        set { UserDefaults.standard.set(newValue, forKey: ownedKey) }
    }
    private var inFlight = false

    var isSupported: Bool { NativeChargeLimit.shared.isSupported }

    /// Call on every status / config update. Cheap when nothing changed.
    func sync(status: SimmerStatus?, config: SimmerConfig) {
        guard let s = status else { return }
        guard s.usingNativeLimit else {
            active = false
            if owned { release() }
            return
        }
        active = true
        let n = NativeChargeLimit.shared
        guard n.isSupported else {
            lastError = "This macOS has no Charge Limit setting, and it blocks direct charge control."
            return
        }
        if availableLimits.isEmpty { availableLimits = n.availableLimits() }
        let releaseNow = !config.limiterEnabled || s.runtime.topUp || s.runtime.calibrationPhase != nil
        let want = releaseNow ? 100 : NativeLimitMapper.target(for: s.effectiveLimit, available: availableLimits)
        if appliedLimit == want, !inFlight { return }
        apply(want)
    }

    /// The limit macOS will actually hold for a requested Simmer limit (for UI hints).
    func nativeTarget(for limit: Int) -> Int {
        if availableLimits.isEmpty { availableLimits = NativeChargeLimit.shared.availableLimits() }
        return NativeLimitMapper.target(for: limit, available: availableLimits)
    }

    private func apply(_ want: Int) {
        guard !inFlight else { return }
        inFlight = true
        Task.detached(priority: .utility) {
            let n = NativeChargeLimit.shared
            let current = n.current()
            let currentEffective = current.map { $0.enabled ? $0.limit : 100 }
            let err: String? = currentEffective == want ? nil : n.set(limit: want)
            await MainActor.run {
                self.inFlight = false
                self.lastError = err
                if err == nil {
                    self.appliedLimit = want
                    self.owned = want < 100
                }
            }
        }
    }

    /// Gives the macOS setting back (no limit) when Simmer no longer uses it.
    private func release() {
        guard !inFlight else { return }
        inFlight = true
        Task.detached(priority: .utility) {
            let err = NativeChargeLimit.shared.set(limit: 100)
            await MainActor.run {
                self.inFlight = false
                if err == nil { self.owned = false; self.appliedLimit = nil }
                self.lastError = err
            }
        }
    }
}

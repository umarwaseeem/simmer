import Foundation

/// Estimates how long charging (or draining) takes to reach a target percentage.
///
/// Model: lithium-ion cells charge at roughly constant current up to about 80% and then taper
/// (constant voltage). Above `taperStart` the effective current is assumed to fall linearly to
/// `taperFloor` × the current at the taper start, which matches typical MacBook curves well
/// enough for a "about 25 min" estimate. Below the taper the live current is used as is.
public enum ChargeEstimate {
    public static let taperStart = 80.0
    public static let taperFloor = 0.25

    /// Minutes until the battery reaches `targetPercent`, or nil when it is not moving toward it
    /// (not charging / not discharging, current too small, or already there).
    public static func minutes(to targetPercent: Int, battery b: BatterySnapshot) -> Int? {
        guard b.present, b.rawMaxCapacity > 0 else { return nil }
        let now = b.hardwarePercent > 0 ? b.hardwarePercent : Double(b.percent)
        let target = Double(min(100, max(0, targetPercent)))
        let amps = b.amperageA
        guard abs(amps) >= 0.05 else { return nil }                // idle: holding at the limit
        let capacityAh = Double(b.rawMaxCapacity) / 1000

        if amps > 0 {                                                   // charging up
            guard target > now + 0.4 else { return nil }
            var hours = 0.0
            // Part below the taper at the measured current (or the current scaled back up if we are already tapering).
            let measuredAt = now
            let baseCurrent = measuredAt >= taperStart ? amps / taperFactor(measuredAt) : amps
            let flatEnd = min(target, taperStart)
            if now < flatEnd { hours += (flatEnd - now) / 100 * capacityAh / baseCurrent }
            // Taper part, integrated in 1% steps.
            var p = max(now, taperStart)
            while p < target {
                let step = min(1, target - p)
                hours += step / 100 * capacityAh / (baseCurrent * taperFactor(p + step / 2))
                p += step
            }
            return clampMinutes(hours)
        } else {                                                        // draining down
            guard target < now - 0.4 else { return nil }
            let hours = (now - target) / 100 * capacityAh / abs(amps)
            return clampMinutes(hours)
        }
    }

    /// Fraction of the pre-taper current that flows at `percent`.
    static func taperFactor(_ percent: Double) -> Double {
        guard percent > taperStart else { return 1 }
        let t = min(1, (percent - taperStart) / (100 - taperStart))
        return 1 - t * (1 - taperFloor)
    }

    private static func clampMinutes(_ hours: Double) -> Int? {
        guard hours.isFinite, hours > 0 else { return nil }
        let m = Int((hours * 60).rounded())
        return m > 24 * 60 ? nil : max(1, m)
    }

    /// "25 min", "1 h 10 min".
    public static func format(minutes m: Int) -> String {
        m < 60 ? "\(m) min" : (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min")
    }
}

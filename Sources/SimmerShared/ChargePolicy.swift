import Foundation

/// Inputs the policy needs, independent of hardware.
public struct PolicyInput: Sendable {
    public var config: SimmerConfig
    public var runtime: RuntimeState
    public var percent: Int
    public var pluggedIn: Bool
    public var fullyCharged: Bool
    public var temperatureC: Double
    public var backend: ChargeBackend
    public var supportsDischarge: Bool
    public var now: Date
    public init(config: SimmerConfig, runtime: RuntimeState, percent: Int, pluggedIn: Bool, fullyCharged: Bool = false,
                temperatureC: Double, backend: ChargeBackend, supportsDischarge: Bool, now: Date = Date()) {
        self.config = config; self.runtime = runtime; self.percent = percent; self.pluggedIn = pluggedIn; self.fullyCharged = fullyCharged
        self.temperatureC = temperatureC; self.backend = backend; self.supportsDischarge = supportsDischarge; self.now = now
    }
}

public enum PolicyEvent: String, Codable, Sendable {
    case heatProtectionStarted, heatProtectionEnded, dischargeFinished, topUpEnded, calibrationPhaseChanged, calibrationFinished
}

public struct PolicyDecision: Equatable, Sendable {
    public var inhibitCharging = false
    public var disableAdapter = false
    public var preventSleep = false
    public var state: ChargeState = .notPluggedIn
    public var targetPercent = 80
    public var led: LEDColor = .system
    public var runtime = RuntimeState()
    public var phaseEndsAt: Date? = nil
    public var events: [PolicyEvent] = []
}

/// Pure charging state machine: limit, sailing, heat protection,
/// discharge, top up, and the 6-phase calibration (100% → hold → low → 100% → hold → limit).
public enum ChargePolicy {
    public static func decide(_ i: PolicyInput) -> PolicyDecision {
        var d = PolicyDecision()
        var rt = i.runtime
        let cfg = i.config
        let pct = i.percent
        let plugged = i.pluggedIn

        guard i.backend != .none else {
            d.state = .unsupported; d.runtime = rt; d.targetPercent = cfg.chargeLimit
            return d
        }

        // Limit-only hardware (Intel BCLM): the SMC enforces the level by itself. No sailing, heat pause,
        // discharge, top up or calibration; the engine writes BCLM = targetPercent when it changes.
        if i.backend == .bclm {
            if rt.heatPaused { d.events.append(.heatProtectionEnded) }
            rt.topUp = false; rt.manualDischarge = false; rt.calibrationPhase = nil; rt.phaseStartedAt = nil
            rt.sailingLatched = false; rt.heatPaused = false
            let target = cfg.limiterEnabled ? cfg.chargeLimit : 100
            d.targetPercent = target
            if !cfg.limiterEnabled { d.state = plugged ? .limiterOff : .notPluggedIn }
            else if !plugged { d.state = .notPluggedIn }
            else { d.state = pct >= target ? .limitReached : .charging }
            d.runtime = rt
            d.led = led(cfg, state: d.state, plugged: plugged, inhibit: pct >= target, adapterOff: false, pct: pct)
            return d
        }

        if rt.topUp && !plugged { rt.topUp = false; d.events.append(.topUpEnded) }
        if rt.manualDischarge && !plugged { rt.manualDischarge = false }
        if !cfg.sailingEnabled { rt.sailingLatched = false }

        // Calibration overrides everything else.
        if let phase = rt.calibrationPhase {
            let holdSecs = TimeInterval(cfg.calibrationHoldMinutes * 60)
            let started = rt.phaseStartedAt ?? i.now
            func advance(_ next: CalibrationPhase?) {
                rt.calibrationPhase = next; rt.phaseStartedAt = i.now
                d.events.append(next == nil ? .calibrationFinished : .calibrationPhaseChanged)
            }
            let full = pct >= 100 || i.fullyCharged
            switch phase {
            case .chargeToFull:
                if full { advance(.holdFull) }
            case .holdFull:
                if i.now.timeIntervalSince(started) >= holdSecs { advance(.dischargeLow) }
            case .dischargeLow:
                if pct <= cfg.calibrationDischargeTo { advance(.chargeToFullAgain) }
            case .chargeToFullAgain:
                if full { advance(.holdFullAgain) }
            case .holdFullAgain:
                if i.now.timeIntervalSince(started) >= holdSecs { advance(.returnToLimit) }
            case .returnToLimit:
                if pct <= cfg.chargeLimit { advance(nil); rt.lastCalibration = i.now }
            }
            if let p = rt.calibrationPhase {
                d.state = .calibration
                d.preventSleep = true
                switch p {
                case .chargeToFull, .holdFull, .chargeToFullAgain, .holdFullAgain:
                    d.targetPercent = 100; d.inhibitCharging = false; d.disableAdapter = false
                    if p == .holdFull || p == .holdFullAgain { d.phaseEndsAt = (rt.phaseStartedAt ?? i.now).addingTimeInterval(holdSecs) }
                case .dischargeLow:
                    d.targetPercent = cfg.calibrationDischargeTo
                    d.inhibitCharging = true; d.disableAdapter = plugged && i.supportsDischarge
                case .returnToLimit:
                    d.targetPercent = cfg.chargeLimit
                    d.inhibitCharging = true; d.disableAdapter = plugged && i.supportsDischarge
                }
                d.runtime = rt
                d.led = led(cfg, state: d.state, plugged: plugged, inhibit: d.inhibitCharging, adapterOff: d.disableAdapter, pct: pct)
                return d
            }
            // calibration just finished: fall through to normal logic
        }

        let target = rt.topUp ? 100 : cfg.chargeLimit
        d.targetPercent = target

        // Heat protection with hysteresis.
        if cfg.heatProtectionEnabled && !rt.topUp {
            if !rt.heatPaused && i.temperatureC >= cfg.heatThresholdC { rt.heatPaused = true; d.events.append(.heatProtectionStarted) }
            else if rt.heatPaused && i.temperatureC < cfg.heatThresholdC - cfg.heatResumeDeltaC { rt.heatPaused = false; d.events.append(.heatProtectionEnded) }
        } else if rt.heatPaused { rt.heatPaused = false; d.events.append(.heatProtectionEnded) }

        if rt.manualDischarge && pct <= target { rt.manualDischarge = false; d.events.append(.dischargeFinished) }
        let wantsDischarge = (rt.manualDischarge || (cfg.automaticDischarge && cfg.limiterEnabled && !rt.topUp)) && pct > target

        if !cfg.limiterEnabled && !rt.topUp && !rt.manualDischarge {
            rt.sailingLatched = false
            d.state = plugged ? .limiterOff : .notPluggedIn
        } else if !plugged {
            d.state = .notPluggedIn
            d.inhibitCharging = pct >= target     // pre-arm so plugging in does not cause a charge burst
        } else if wantsDischarge && i.supportsDischarge {
            d.state = .discharging; d.inhibitCharging = true; d.disableAdapter = true; d.preventSleep = true
        } else if rt.topUp {
            d.state = .topUp
        } else if rt.heatPaused {
            d.state = .heatProtection; d.inhibitCharging = true
        } else if pct >= target {
            if cfg.sailingEnabled { rt.sailingLatched = true }
            d.state = .limitReached; d.inhibitCharging = true
        } else if cfg.sailingEnabled && rt.sailingLatched && pct > target - cfg.sailingLevel {
            d.state = .sailing; d.inhibitCharging = true
        } else {
            rt.sailingLatched = false
            d.state = .charging; d.inhibitCharging = false
            d.preventSleep = cfg.disableSleepUntilLimit
        }

        d.runtime = rt
        d.led = led(cfg, state: d.state, plugged: plugged, inhibit: d.inhibitCharging, adapterOff: d.disableAdapter, pct: pct)
        return d
    }

    static func led(_ cfg: SimmerConfig, state: ChargeState, plugged: Bool, inhibit: Bool, adapterOff: Bool, pct: Int) -> LEDColor {
        switch cfg.ledMode {
        case .system: return .system
        case .alwaysOff: return .off
        case .custom: return plugged ? cfg.ledCustom.color(for: state) : .system
        case .smart:
            guard plugged else { return .system }
            if adapterOff { return cfg.blinkOrangeDuringDischarge ? .orangeBlinkSlow : .off }
            if !inhibit && pct < 100 { return .orange }
            return .green
        }
    }
}

/// Decides which scheduled tasks are due.
public enum TaskScheduler {
    /// Most recent scheduled occurrence at or before `now`, searching back up to 62 days.
    public static func lastOccurrence(of t: ScheduledTask, before now: Date, calendar cal: Calendar = .current) -> Date? {
        if case .once(let date) = t.recurrence { return date <= now ? date : nil }
        let startOfToday = cal.startOfDay(for: now)
        for back in 0...62 {
            guard let day = cal.date(byAdding: .day, value: -back, to: startOfToday),
                  let occ = cal.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day), occ <= now else { continue }
            let wd = cal.component(.weekday, from: day)
            switch t.recurrence {
            case .daily: return occ
            case .weekly(let days): if days.map(\.rawValue).contains(wd) { return occ }
            case .biweekly(let d):
                if d.rawValue == wd && cal.component(.weekOfYear, from: day) % 2 == 0 { return occ }
            case .monthly(let dom):
                let range = cal.range(of: .day, in: .month, for: day) ?? 1..<29
                if cal.component(.day, from: day) == min(dom, range.upperBound - 1) { return occ }
            case .once: return nil
            }
        }
        return nil
    }

    /// A task is due when an occurrence passed after its last run. Without catch-up, only within `window`.
    public static func isDue(_ t: ScheduledTask, now: Date, catchUp: Bool, window: TimeInterval = 120, calendar: Calendar = .current) -> Date? {
        guard t.enabled, let occ = lastOccurrence(of: t, before: now, calendar: calendar) else { return nil }
        if let last = t.lastRun, last >= occ { return nil }
        let recent = now.timeIntervalSince(occ) <= window
        if recent { return occ }
        // Catch-up only applies once the task has run before (avoids firing on first install).
        if catchUp, t.lastRun != nil { return occ }
        return nil
    }
}

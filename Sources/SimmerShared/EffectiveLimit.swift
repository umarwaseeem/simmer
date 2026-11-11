import Foundation

extension TimeWindow {
    public var startMinuteOfDay: Int { startHour * 60 + startMinute }
    public var endMinuteOfDay: Int { endHour * 60 + endMinute }

    /// True when `minute` (0..<1440) is inside the window. Windows may wrap past midnight; start == end
    /// means the whole day.
    public func contains(minuteOfDay m: Int) -> Bool {
        let s = startMinuteOfDay, e = endMinuteOfDay
        if s == e { return true }
        return s < e ? (m >= s && m < e) : (m >= s || m < e)
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return contains(minuteOfDay: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// The next time this window starts, strictly after `date`.
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: date)
        for d in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: d, to: today),
                  let t = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day) else { continue }
            if t > date { return t }
        }
        return nil
    }

    /// "HH:MM-HH:MM".
    public var cliString: String { String(format: "%02d:%02d-%02d:%02d", startHour, startMinute, endHour, endMinute) }

    /// Parses "HH:MM-HH:MM" (24 h).
    public init?(cliString s: String) {
        let parts = s.split(separator: "-")
        guard parts.count == 2 else { return nil }
        func hm(_ x: Substring) -> (Int, Int)? {
            let p = x.split(separator: ":")
            guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
            return (h, m)
        }
        guard let a = hm(parts[0]), let b = hm(parts[1]) else { return nil }
        self.init(startHour: a.0, startMinute: a.1, endHour: b.0, endMinute: b.1)
    }
}

extension EffectiveLimit {
    static func evaluate(_ cfg: SimmerConfig, _ ctx: LimitContext, calendar: Calendar = .current) -> (limit: Int, reason: LimitReason) {
        let user = cfg.chargeLimit

        // 1. Smart top-up: 100 % within the lead time before a predicted departure.
        if cfg.smartTopUpEnabled, ctx.pluggedIn, let dep = ctx.predictedDeparture, user < 100 {
            let lead = TimeInterval(cfg.smartTopUpLeadMinutes * 60)
            if ctx.now >= dep.addingTimeInterval(-lead) && ctx.now < dep {
                return (100, .smartTopUp(departure: dep))
            }
        }

        // 2. Desk mode: a lower limit during long desk / clamshell use. Never above the user limit.
        if cfg.deskModeEnabled, ctx.pluggedIn, cfg.deskModeLimit < user {
            let clamshell = ctx.lidClosed
            let longPlugged = ctx.pluggedSince.map { ctx.now.timeIntervalSince($0) >= cfg.deskModeAfterHours * 3600 } ?? false
            let active: Bool
            switch cfg.deskModeTrigger {
            case .clamshell: active = clamshell
            case .pluggedHours: active = longPlugged
            case .clamshellOrPluggedHours: active = clamshell || longPlugged
            }
            if active { return (cfg.deskModeLimit, .deskMode) }
        }

        // 3. Cheap windows: outside every window, charge only up to the floor.
        if cfg.cheapChargingEnabled, !cfg.cheapWindows.isEmpty, cfg.cheapFloorPercent < user {
            let inside = cfg.cheapWindows.contains { $0.contains(ctx.now, calendar: calendar) }
            if !inside {
                let next = cfg.cheapWindows.compactMap { $0.nextStart(after: ctx.now, calendar: calendar) }.min()
                    ?? ctx.now.addingTimeInterval(86_400)
                return (cfg.cheapFloorPercent, .waitingForCheapWindow(start: next))
            }
        }

        return (user, .user)
    }
}

extension DeparturePredictor {
    /// Unplug times: the first unplugged sample after a plugged run that lasted at least 30 minutes.
    public static func unplugEvents(samples: [HistorySample]) -> [Date] {
        let sorted = samples.sorted { $0.t < $1.t }
        var events: [Date] = []
        var runStart: Date?
        for s in sorted {
            if s.plugged {
                if runStart == nil { runStart = s.t }
            } else {
                if let start = runStart, s.t.timeIntervalSince(start) >= 30 * 60 { events.append(s.t) }
                runStart = nil
            }
        }
        return events
    }

    static func predict(samples: [HistorySample], now: Date, calendar cal: Calendar) -> Date? {
        let events = unplugEvents(samples: samples)
        guard events.count >= 2 else { return nil }
        var byWeekday: [Int: [Int]] = [:]   // weekday → minutes after midnight
        for e in events {
            let c = cal.dateComponents([.weekday, .hour, .minute], from: e)
            guard let wd = c.weekday else { continue }
            byWeekday[wd, default: []].append((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        let today = cal.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let wd = cal.component(.weekday, from: day)
            guard let minutes = byWeekday[wd], let m = clusterMedian(minutes) else { continue }
            guard let t = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day), t > now else { continue }
            return t
        }
        return nil
    }

    /// Median of the largest group of ≥ 2 times that lie within 45 minutes of each other, else nil.
    static func clusterMedian(_ minutes: [Int]) -> Int? {
        let s = minutes.sorted()
        guard s.count >= 2 else { return nil }
        var best: ArraySlice<Int> = []
        var lo = 0
        for hi in s.indices {
            while s[hi] - s[lo] > 45 { lo += 1 }
            if hi - lo + 1 > best.count { best = s[lo...hi] }
        }
        guard best.count >= 2 else { return nil }
        let a = Array(best)
        return a.count % 2 == 1 ? a[a.count / 2] : (a[a.count / 2 - 1] + a[a.count / 2]) / 2
    }
}

extension DeparturePredictor {
    /// Start of the plugged-in run that reaches the newest sample, when that sample is recent (≤ 15 min old)
    /// and plugged. Gaps over 20 minutes end the run (the Mac may have been unplugged while asleep).
    public static func pluggedSince(samples: [HistorySample], now: Date) -> Date? {
        let sorted = samples.sorted { $0.t < $1.t }
        guard let last = sorted.last, last.plugged, now.timeIntervalSince(last.t) <= 15 * 60 else { return nil }
        var start = last.t
        for s in sorted.dropLast().reversed() {
            guard s.plugged, start.timeIntervalSince(s.t) <= 20 * 60 else { break }
            start = s.t
        }
        return start
    }
}

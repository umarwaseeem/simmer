import Foundation
import SimmerShared

enum Fmt {
    static func watts(_ w: Double?) -> String {
        guard let w else { return "–" }
        return String(format: "%.1f W", w)
    }

    static func temp(_ c: Double) -> String { String(format: "%.1f °C", c) }

    static func percent(_ p: Double, digits: Int = 1) -> String { String(format: "%.\(digits)f%%", p) }

    static func duration(minutes m: Int) -> String { String(format: "%d:%02d", m / 60, m % 60) }

    static func remaining(until date: Date, now: Date = Date()) -> String {
        let secs = max(0, Int(date.timeIntervalSince(now)))
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func time(hour: Int, minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }

    static let weekdayShort: [Weekday: String] = [.sun: "Sun", .mon: "Mon", .tue: "Tue", .wed: "Wed", .thu: "Thu", .fri: "Fri", .sat: "Sat"]

    static func describe(_ a: TaskAction) -> String {
        switch a {
        case .setLimit(let v): return "Set limit to \(v)%"
        case .topUp: return "Top Up"
        case .discharge(let v): return "Discharge to \(v)%"
        case .calibrate: return "Calibrate"
        case .lowPowerMode(let b): return "Low Power Mode \(b ? "on" : "off")"
        case .highPowerMode(let b): return "High Power Mode \(b ? "on" : "off")"
        case .limiter(let b): return "Limiter \(b ? "on" : "off")"
        }
    }

    static func describe(_ r: TaskRecurrence) -> String {
        switch r {
        case .once(let d): return "Once on " + DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
        case .daily: return "Daily"
        case .weekly(let days):
            if days.isEmpty { return "Weekly (no days)" }
            return "Weekly on " + days.sorted { $0.rawValue < $1.rawValue }.compactMap { weekdayShort[$0] }.joined(separator: ", ")
        case .biweekly(let d): return "Every 2 weeks on \(weekdayShort[d] ?? "")"
        case .monthly(let day): return "Monthly on day \(day)"
        }
    }
}

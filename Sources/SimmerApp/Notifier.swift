import Foundation
import UserNotifications
import SimmerShared

/// Posts user notifications for status transitions. Fails silently when notifications are unavailable
/// (for example when the binary runs outside an .app bundle).
final class Notifier {
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    func requestAuthorization() {
        guard Self.isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ title: String, _ body: String) {
        guard Self.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    /// Compares two consecutive status snapshots and posts a notification for each relevant transition.
    func diff(old: SimmerStatus, new: SimmerStatus) {
        let o = old.runtime, n = new.runtime
        let pct = new.battery.percent

        if old.state == .charging && new.state == .limitReached {
            post("Charge Limit Reached", "The battery is at \(pct)%. Simmer stopped charging at the \(new.targetPercent)% limit.")
        }
        if !o.heatPaused && n.heatPaused {
            post("Heat Protection Started", String(format: "Battery at %.1f °C. Charging is paused until it cools down.", new.temperatureC))
        } else if o.heatPaused && !n.heatPaused {
            post("Heat Protection Ended", String(format: "Battery at %.1f °C. Charging can continue.", new.temperatureC))
        }
        if old.state == .discharging && new.state != .discharging && new.battery.externalConnected {
            post("Discharge Finished", "The battery is at \(pct)%.")
        }
        if o.topUp && !n.topUp {
            post("Top Up Ended", "The battery is at \(pct)%. The \(new.targetPercent)% limit is active again.")
        }
        if o.calibrationPhase != n.calibrationPhase {
            if let phase = n.calibrationPhase {
                post("Calibration", "\(phase.title) (\(pct)%).")
            } else if o.calibrationPhase != nil {
                post("Calibration Finished", "The battery is back at the charge limit.")
            }
        }
    }

    /// Desk mode and smart top-up transitions (the daemon changes the effective limit by itself).
    func limitReasonChanged(old: SimmerStatus, new: SimmerStatus) {
        let wasDesk = old.limitReason == .deskMode, isDesk = new.limitReason == .deskMode
        if !wasDesk && isDesk {
            post("Desk Mode On", "Simmer holds the battery at \(new.effectiveLimit)% while your Mac stays at the desk.")
        } else if wasDesk && !isDesk {
            post("Desk Mode Off", "The \(new.effectiveLimit)% limit applies again.")
        }
        if case .smartTopUp(let departure) = new.limitReason {
            if case .smartTopUp = old.limitReason {} else {
                post("Smart Top-Up Started",
                     "Charging to \(new.effectiveLimit)% for your usual departure at \(departure.formatted(date: .omitted, time: .shortened)).")
            }
        }
    }

    // MARK: charger

    private var chargerWarnedThisPlug = false
    private var insufficientSince: Date?

    /// Warns once per plug-in when the charger stays too weak for 30 seconds.
    func chargerCheck(_ report: ChargerReport, pluggedIn: Bool, now: Date = Date()) {
        guard pluggedIn else { chargerWarnedThisPlug = false; insufficientSince = nil; return }
        guard report.rating == .insufficient else { insufficientSince = nil; return }
        if insufficientSince == nil { insufficientSince = now }
        guard !chargerWarnedThisPlug, let since = insufficientSince, now.timeIntervalSince(since) >= 30 else { return }
        chargerWarnedThisPlug = true
        post("Charger Too Weak", report.headline.isEmpty
             ? "Your charger cannot keep up with your Mac. The battery may drain while plugged in."
             : report.headline)
    }

    // MARK: battery cells and conflicts

    private static let cellWarningKey = "lastCellBalanceWarning"
    private static let notifiedConflictsKey = "notifiedConflictIDs"

    /// At most once a week.
    func cellBalancePoor(imbalanceMV: Int, now: Date = Date(), defaults: UserDefaults = .standard) {
        if let last = defaults.object(forKey: Self.cellWarningKey) as? Date, now.timeIntervalSince(last) < 7 * 86_400 { return }
        defaults.set(now, forKey: Self.cellWarningKey)
        post("Battery Cells Out of Balance",
             "The battery cells differ by \(imbalanceMV) mV. Plan a battery check. Open Simmer → Cells & Stress for details.")
    }

    /// Once per conflict until it is gone.
    func conflictsFound(_ conflicts: [Conflict], defaults: UserDefaults = .standard) {
        let known = Set(defaults.stringArray(forKey: Self.notifiedConflictsKey) ?? [])
        let current = Set(conflicts.map(\.id))
        let fresh = conflicts.filter { !known.contains($0.id) }
        defaults.set(Array(current), forKey: Self.notifiedConflictsKey)
        guard !fresh.isEmpty else { return }
        if fresh.count == 1 {
            post("Conflict: \(fresh[0].name)", fresh[0].detail)
        } else {
            post("\(fresh.count) Charge-Limit Conflicts", "Other tools can fight with Simmer: " + fresh.map(\.name).joined(separator: ", ") + ". Open Conflict Doctor to fix it.")
        }
    }

    func helperUnreachable() {
        post("Simmer Helper Unreachable", "The charge limiter does not respond. Open Simmer to reinstall the helper.")
    }
}

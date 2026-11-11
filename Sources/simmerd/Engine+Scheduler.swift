import Foundation
import SimmerShared

extension Engine {
    /// Runs every due scheduled task once. Called at the start of each tick on the engine queue.
    func runScheduler(now: Date) {
        dispatchPrecondition(condition: .onQueue(queue))
        var changed = false
        for idx in config.schedule.indices {
            let task = config.schedule[idx]
            guard let occurrence = TaskScheduler.isDue(task, now: now, catchUp: config.catchUpMissedTasks) else { continue }
            config.schedule[idx].lastRun = now
            changed = true

            if runtime.calibrationPhase != nil && Self.interruptsCalibration(task.action) {
                log.notice("skipped task \(task.name, privacy: .public) (due \(occurrence, privacy: .public)): calibration is running")
                continue
            }
            log.notice("running scheduled task \(task.name, privacy: .public) (due \(occurrence, privacy: .public))")
            let name = task.name
            let outcome = run(task.action) { err in
                if let err { log.error("task \(name, privacy: .public) failed: \(err, privacy: .public)") }
                else { log.info("task \(name, privacy: .public) done") }
            }
            if case .failed(let err) = outcome {
                log.error("task \(name, privacy: .public) failed: \(err, privacy: .public)")
            }
        }
        if changed { persistConfig() }
    }

    /// Power-mode tasks are independent of charging, so they may run during calibration.
    static func interruptsCalibration(_ a: TaskAction) -> Bool {
        switch a {
        case .lowPowerMode, .highPowerMode: return false
        default: return true
        }
    }
}

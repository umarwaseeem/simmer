import Foundation
import SimmerShared

extension Engine {
    enum Outcome { case ok, failed(String), pending }

    // MARK: XPC entry points (any thread)

    func perform(_ data: Data, reply: @escaping (String?) -> Void) {
        let cmd: SimmerCommand
        do { cmd = try SimmerJSON.decode(SimmerCommand.self, data) } catch {
            reply("Invalid command: \(error.localizedDescription)"); return
        }
        queue.async {
            self.refreshReading()
            log.info("command: \(String(describing: cmd), privacy: .public)")
            let outcome = self.execute(cmd, source: "command") { err in
                // Async commands (pmset) finish here, off the engine queue.
                reply(err)
                self.requestTick("command done")
            }
            switch outcome {
            case .ok:
                self.tick(reason: "command")
                reply(nil)
            case .failed(let msg):
                log.error("command \(String(describing: cmd), privacy: .public) failed: \(msg, privacy: .public)")
                reply(msg)
            case .pending:
                break
            }
        }
    }

    func setConfig(_ data: Data, reply: @escaping (String?) -> Void) {
        var cfg: SimmerConfig
        do { cfg = try SimmerJSON.decode(SimmerConfig.self, data) } catch {
            reply("Invalid config: \(error.localizedDescription)"); return
        }
        cfg.clamp()
        queue.async {
            let old = self.config
            if cfg.chargeLimit != old.chargeLimit || cfg.sailingLevel != old.sailingLevel { self.runtime.sailingLatched = false }
            // A client may send a config read before a task ran; keep the newer lastRun so the task does not run twice.
            for i in cfg.schedule.indices {
                if let prev = old.schedule.first(where: { $0.id == cfg.schedule[i].id })?.lastRun,
                   prev > (cfg.schedule[i].lastRun ?? .distantPast) {
                    cfg.schedule[i].lastRun = prev
                }
            }
            if cfg.intelBCLMOffset != old.intelBCLMOffset { self.bclmOffsetChanged(cfg.intelBCLMOffset) }
            if cfg.smartTopUpEnabled != old.smartTopUpEnabled { self.invalidatePrediction() }
            self.config = cfg
            self.persistConfig()
            log.info("config updated: limit=\(cfg.chargeLimit) limiter=\(cfg.limiterEnabled) led=\(cfg.ledMode.rawValue, privacy: .public)")
            self.tick(reason: "config")
            reply(nil)
        }
    }

    func statusData(reply: @escaping (Data) -> Void) { queue.async { reply(SimmerJSON.encode(self.status)) } }
    func configData(reply: @escaping (Data) -> Void) { queue.async { reply(SimmerJSON.encode(self.config)) } }

    // MARK: command execution (engine queue)

    /// Mutates config/runtime for `cmd`. Does not tick. `asyncDone` is called only for `.pending`.
    func execute(_ cmd: SimmerCommand, source: String, asyncDone: @escaping (String?) -> Void) -> Outcome {
        dispatchPrecondition(condition: .onQueue(queue))
        let pct = snapshot.percent
        switch cmd {
        case .setLimit(let n):
            config.chargeLimit = Self.clampLimit(n)
            runtime.sailingLatched = false
            persistConfig(); persistRuntimeIfNeeded()
            return .ok

        case .setLimiterEnabled(let on):
            config.limiterEnabled = on
            if !on { runtime.sailingLatched = false }
            persistConfig(); persistRuntimeIfNeeded()
            return .ok

        case .topUp(let on):
            if on {
                guard !capabilities.limitOnly else {
                    return .failed("Top Up is not available on this Mac: it only has a fixed charge limit (BCLM). Set the limit to 100% instead.")
                }
                guard pluggedIn else { return .failed("Top Up needs the charger connected") }
                runtime.topUp = true
                runtime.manualDischarge = false
            } else {
                runtime.topUp = false
            }
            persistRuntimeIfNeeded()
            return .ok

        case .discharge(let on):
            if on {
                guard pluggedIn else { return .failed("Discharge needs the charger connected") }
                guard supportsDischarge else { return .failed("This Mac cannot discharge while the charger is connected") }
                guard pct > config.chargeLimit else {
                    return .failed("Battery is at \(pct)%, which is not above the \(config.chargeLimit)% charge limit")
                }
                runtime.manualDischarge = true
                runtime.topUp = false
            } else {
                runtime.manualDischarge = false
            }
            persistRuntimeIfNeeded()
            return .ok

        case .calibrate(let on):
            if on {
                guard supportsDischarge else {
                    return .failed("Calibration is not available on this Mac: it cannot run from the battery while the charger is connected")
                }
                guard pluggedIn else { return .failed("Calibration needs the charger connected") }
                runtime.calibrationPhase = .chargeToFull
                runtime.phaseStartedAt = Date()
                runtime.topUp = false
                runtime.manualDischarge = false
                runtime.sailingLatched = false
            } else {
                runtime.calibrationPhase = nil
                runtime.phaseStartedAt = nil
            }
            persistRuntimeIfNeeded()
            return .ok

        case .pause:
            guard snapshot.present else { return .failed("Cannot read the battery level") }
            config.chargeLimit = Self.clampLimit(pct)
            runtime.sailingLatched = false
            runtime.topUp = false
            runtime.manualDischarge = false
            persistConfig(); persistRuntimeIfNeeded()
            return .ok

        case .setLED(let m):
            config.ledMode = m
            persistConfig()
            return .ok

        case .setLowPowerMode(let on, let scope):
            // macOS 14+ stores Low Power Mode as `powermode 1` (High Power = 2, Automatic = 0).
            powerModes.set([PowerModeMonitor.scopeFlag(scope), "powermode", on ? "1" : "0"],
                           dryRun: !mode.writesHardware, done: asyncDone)
            return .pending

        case .setHighPowerMode(let on, let scope):
            guard powerModes.status.highPowerSupported else { return .failed("High Power Mode is not supported on this Mac") }
            powerModes.set([PowerModeMonitor.scopeFlag(scope), "powermode", on ? "2" : "0"],
                           dryRun: !mode.writesHardware, done: asyncDone)
            return .pending

        case .runTask(let id):
            guard let idx = config.schedule.firstIndex(where: { $0.id == id }) else {
                return .failed("No scheduled task with id \(id.uuidString)")
            }
            let task = config.schedule[idx]
            config.schedule[idx].lastRun = Date()
            persistConfig()
            log.notice("running task now: \(task.name, privacy: .public)")
            return run(task.action, asyncDone: asyncDone)

        case .ledNotify(let pattern, let repeats):
            return startLEDNotification(pattern, repeats: repeats)

        case .removeConflict(let id):
            return removeConflict(id, asyncDone: asyncDone)

        case .sleepNow:
            guard mode.writesHardware else { return .ok }
            // Reply first, then sleep.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let err = sleepSystemNow() {
                    log.error("sleep now failed: \(err, privacy: .public); trying pmset sleepnow")
                    DispatchQueue.global(qos: .utility).async { _ = Shell.run(PowerModeMonitor.pmset, ["sleepnow"], timeout: 10) }
                }
            }
            return .ok
        }
    }

    /// Runs a scheduled task action through the command path.
    func run(_ action: TaskAction, asyncDone: @escaping (String?) -> Void) -> Outcome {
        switch action {
        case .setLimit(let n): return execute(.setLimit(n), source: "task", asyncDone: asyncDone)
        case .topUp: return execute(.topUp(true), source: "task", asyncDone: asyncDone)
        case .discharge(let n):
            _ = execute(.setLimit(n), source: "task", asyncDone: asyncDone)
            return execute(.discharge(true), source: "task", asyncDone: asyncDone)
        case .calibrate: return execute(.calibrate(true), source: "task", asyncDone: asyncDone)
        case .lowPowerMode(let on): return execute(.setLowPowerMode(on, .all), source: "task", asyncDone: asyncDone)
        case .highPowerMode(let on): return execute(.setHighPowerMode(on, .all), source: "task", asyncDone: asyncDone)
        case .limiter(let on): return execute(.setLimiterEnabled(on), source: "task", asyncDone: asyncDone)
        }
    }

    static func clampLimit(_ n: Int) -> Int { min(100, max(20, n)) }

    // MARK: LED notification

    /// Plays the pattern with timed ACLC writes on the engine queue, then restores the normal LED.
    func startLEDNotification(_ pattern: LEDPattern, repeats: Int) -> Outcome {
        dispatchPrecondition(condition: .onQueue(queue))
        guard supportsLED else { return .failed("This Mac has no MagSafe LED") }
        guard pluggedIn else { return .failed("The MagSafe LED lights only while the MagSafe charger is connected") }
        let steps = LEDPatternPlayer.steps(pattern, repeats: repeats, percent: snapshot.percent)
        ledNotificationGeneration &+= 1
        let generation = ledNotificationGeneration
        ledNotificationActive = true
        log.info("LED notification \(pattern.rawValue, privacy: .public) x\(repeats): \(steps.count) steps")
        playLEDStep(steps, index: 0, generation: generation)
        return .ok
    }

    private func playLEDStep(_ steps: [LEDPatternPlayer.Step], index: Int, generation: UInt64) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard generation == ledNotificationGeneration, !shuttingDownFlag else { return }
        guard index < steps.count else {
            ledNotificationFinished()
            tick(reason: "led notification done")
            return
        }
        if let err = writeNotificationLED(steps[index].color) {
            log.error("LED notification stopped: \(err, privacy: .public)")
            ledNotificationFinished()
            tick(reason: "led notification failed")
            return
        }
        if mode == .dryRun { print("[dry-run] LED \(steps[index].color) for \(steps[index].seconds) s") }
        queue.asyncAfter(deadline: .now() + steps[index].seconds) { [weak self] in
            self?.playLEDStep(steps, index: index + 1, generation: generation)
        }
    }

    // MARK: conflicts

    /// Removes a leftover helper of another charge limiter: `launchctl bootout system/<label>`, then deletes
    /// exactly the files ConflictScanner listed (only directly inside /Library/LaunchDaemons and
    /// /Library/PrivilegedHelperTools, only paths of the matching known helper). Nothing else.
    func removeConflict(_ id: String, asyncDone: @escaping (String?) -> Void) -> Outcome {
        dispatchPrecondition(condition: .onQueue(queue))
        let found = ConflictScanner.scan()
        guard let c = found.first(where: { $0.id == id }) else {
            return .failed("No conflict with id '\(id)'. Run 'simmerctl conflicts' to list them.")
        }
        guard c.fixableBySimmer, c.kind == .leftoverHelper,
              let known = ConflictScanner.knownHelperDetails.first(where: { $0.label == id }) else {
            return .failed("Simmer cannot remove '\(c.name)'. \(c.detail)")
        }
        let files = c.paths.filter { known.files.contains($0) && ConflictScanner.isRemovablePath($0) }
        guard !files.isEmpty, files.count == c.paths.count else {
            return .failed("Refusing to remove '\(id)': unexpected file list \(c.paths)")
        }
        // The plist's own Label is what launchd knows (bclm uses an unusual label); fall back to the id.
        let label = files.first(where: { $0.hasSuffix(".plist") }).flatMap { ConflictEnvironment.live.plistLabel($0) } ?? id
        guard label.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
              !label.hasPrefix("com.umarwaseem.simmer") else {
            return .failed("Refusing to remove '\(id)': unexpected launchd label '\(label)'")
        }
        guard mode.writesHardware else {
            log.notice("[dry-run] would run launchctl bootout system/\(label, privacy: .public) and delete \(files.joined(separator: ", "), privacy: .public)")
            return .ok
        }
        DispatchQueue.global(qos: .utility).async {
            let r = Shell.run("/bin/launchctl", ["bootout", "system/\(label)"], timeout: 15)
            // "No such process" (3, 113) only means the job was not loaded.
            let bootoutNote = r.status == 0 ? "stopped" : "not running (launchctl \(r.status))"
            var removed: [String] = [], failed: [String] = []
            for f in files {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: f, isDirectory: &isDir) else { continue }
                if isDir.boolValue { failed.append("\(f) (is a folder, left alone)"); continue }
                do { try FileManager.default.removeItem(atPath: f); removed.append(f) }
                catch { failed.append("\(f) (\(error.localizedDescription))") }
            }
            let msg = "\(c.name): job \(bootoutNote); removed \(removed.isEmpty ? "nothing" : removed.joined(separator: ", "))"
            if failed.isEmpty {
                log.notice("removeConflict \(id, privacy: .public): \(msg, privacy: .public)")
                asyncDone(nil)
            } else {
                log.error("removeConflict \(id, privacy: .public): \(msg, privacy: .public); failed: \(failed.joined(separator: ", "), privacy: .public)")
                asyncDone("Could not remove: " + failed.joined(separator: ", "))
            }
        }
        return .pending
    }
}

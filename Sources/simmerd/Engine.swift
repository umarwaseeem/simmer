import Darwin
import notify
import Foundation
import IOKit
import SimmerShared

/// Owns all charge-control state. Every mutable property is touched only on `queue`.
final class Engine: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.umarwaseem.simmer.engine", qos: .userInitiated)
    let mode: RunMode
    let control: ChargeControl?
    let backend: ChargeBackend
    let supportsDischarge: Bool
    let supportsLED: Bool
    let capabilities: Capabilities
    let store: Store
    let powerModes = PowerModeMonitor()
    let sleepAssertion = SleepAssertion()
    let clamshellBlocker = ClamshellSleepBlocker()

    var config: SimmerConfig
    var runtime: RuntimeState
    private(set) var status = SimmerStatus()

    /// Latest battery reading (updated by every tick and before every command).
    var snapshot = BatterySnapshot()
    var pluggedIn = false
    private var flagsDownSince: Date?
    // Files for the app and the widget (world-readable, no XPC needed).
    private var history = BatteryHistory.load() ?? BatteryHistory()
    private var lastSnapshotWrite = Date.distantPast
    private var lastSnapshotKey: String?
    private let unplugDebounce: TimeInterval = 3

    // Last value written to the SMC. nil = unknown, write on the next tick.
    private var appliedInhibit: Bool?
    private var appliedAdapterOff: Bool?
    private var appliedLED: LEDColor?
    private var ledOwned = false          // true while a non-system LED value is on the hardware
    private var lastReassert = Date.distantPast
    private let reassertInterval: TimeInterval = 60

    private var savedRuntime: RuntimeState
    private var smcOpenError: String?
    private var lastErrorMessage: String?
    private var lastErrorAt = Date.distantPast
    private var lastNotified: NotifyKey?
    private var lastState: ChargeState?
    private var lastDecision: PolicyDecision?
    private var timer: DispatchSourceTimer?
    private var shuttingDown = false

    // Effective limit inputs (desk mode, smart top-up, cheap windows).
    private(set) var pluggedSince: Date?
    private var wasPluggedIn: Bool?
    private var predictedDeparture: Date?
    private var lastPrediction = Date.distantPast
    private(set) var effective: (limit: Int, reason: LimitReason) = (80, .user)
    private var appliedHardwareLimit: Int?      // BCLM backend: last value written

    /// While a LED notification plays, the policy does not write the LED. Touched only on `queue`.
    var ledNotificationActive = false
    var ledNotificationGeneration: UInt64 = 0
    var shuttingDownFlag: Bool { shuttingDown }
    /// Thread-safe copy of `pluggedIn` for the energy sampler queue.
    let pluggedBox = LockedBox(false)

    private let pendingLock = NSLock()
    private var tickPending = false

    private struct NotifyKey: Equatable { var state: ChargeState; var target: Int; var inhibit: Bool; var adapterOff: Bool }

    init(mode: RunMode) {
        self.mode = mode
        store = Store(writable: mode.persists)
        config = store.loadConfig()
        do {
            let cc = ChargeControl(smc: try SMC())
            cc.bclmOffset = config.intelBCLMOffset
            control = cc
            backend = cc.backend
            supportsDischarge = cc.supportsDischarge
            supportsLED = cc.hasLED
            capabilities = cc.capabilities
        } catch {
            control = nil
            backend = .none
            supportsDischarge = false
            supportsLED = false
            var c = Capabilities(); c.chargeInhibit = false; c.isIntel = HardwarePlatform.current.isIntel
            capabilities = c
            smcOpenError = "Cannot open AppleSMC: \(error)"
            log.error("\(self.smcOpenError ?? "", privacy: .public)")
        }
        runtime = store.loadState()
        savedRuntime = runtime
        powerModes.onChange = { [weak self] pm in
            guard let self else { return }
            self.queue.async { self.status.powerModes = pm }
        }
        log.info("engine ready: mode=\(String(describing: mode), privacy: .public) backend=\(self.backend.rawValue, privacy: .public) discharge=\(self.supportsDischarge) led=\(self.supportsLED)")
    }

    // MARK: lifecycle

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 5, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.tick(reason: "timer") }
        timer = t
        if mode.writesHardware { queue.async { self.clamshellBlocker.recover() } }
        t.resume()
    }

    /// Coalesced asynchronous tick. Safe from any thread.
    func requestTick(_ reason: String) {
        pendingLock.lock()
        let already = tickPending
        tickPending = true
        pendingLock.unlock()
        if already { return }
        queue.async {
            self.pendingLock.lock(); self.tickPending = false; self.pendingLock.unlock()
            self.tick(reason: reason)
        }
    }

    /// Next tick re-writes every SMC value (used after wake).
    func forceReassert() { lastReassert = .distantPast }

    // MARK: tick

    /// Reads the battery, runs the scheduler and the policy, applies the result. Call on `queue`.
    func tick(reason: String) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !shuttingDown else { return }
        let now = Date()
        var tickErrors: [String] = []

        refreshReading()
        guard snapshot.present else {
            tickErrors.append("Battery read failed")
            if appliedAdapterOff != false || reassertDue(now) {
                ensureAdapterEnabled(&tickErrors)
                lastReassert = now
            }
            if mode.holdsSleepAssertion { sleepAssertion.release() }
            if mode.writesHardware { clamshellBlocker.set(false) }
            finishTick(decision: nil, temperature: nil, now: now, errors: tickErrors, reason: reason)
            return
        }

        if mode.runsScheduler { runScheduler(now: now) }

        let smcTemp = sanitizedTemperature(control?.batteryTemperatureC)
        let temperature = smcTemp ?? snapshot.temperatureC
        updateEffectiveLimit(now: now)
        var policyConfig = config
        policyConfig.chargeLimit = effective.limit
        let input = PolicyInput(config: policyConfig, runtime: runtime, percent: snapshot.percent, pluggedIn: pluggedIn,
                                fullyCharged: snapshot.fullyCharged, temperatureC: temperature, backend: backend,
                                supportsDischarge: supportsDischarge, now: now)
        let d = ChargePolicy.decide(input)

        for e in d.events {
            log.notice("policy event: \(e.rawValue, privacy: .public) (pct=\(self.snapshot.percent) temp=\(temperature, format: .fixed(precision: 1)))")
        }
        if d.state != lastState {
            log.notice("state \(self.lastState?.rawValue ?? "-", privacy: .public) -> \(d.state.rawValue, privacy: .public) target=\(d.targetPercent) pct=\(self.snapshot.percent)")
            lastState = d.state
        }
        if d.runtime != runtime { runtime = d.runtime }
        persistRuntimeIfNeeded()

        apply(d, now: now, errors: &tickErrors)

        if mode.holdsSleepAssertion {
            sleepAssertion.set(d.preventSleep, reason: d.state.title)
        }
        if mode.writesHardware {
            clamshellBlocker.set(config.preventClamshellSleepWhileDischarging && d.disableAdapter && appliedAdapterOff == true)
        }
        lastDecision = d
        finishTick(decision: d, temperature: smcTemp, now: now, errors: tickErrors, reason: reason)
    }

    /// Fresh battery reading plus a robust plugged-in flag.
    func refreshReading() {
        snapshot = BatterySnapshot.read()
        // Measured on M5 Pro / macOS 26.4: with CHIE=0x08 both ExternalConnected and AppleRawExternalConnected
        // read false, but AdapterDetails keeps Watts (94) and SMC ACFP stays 1. Use those only while the
        // adapter is disabled by us, so a real unplug is still detected through the normal flags.
        // macOS also resets CHIE once after the first write, which makes the flags drop for ~1 s, so a
        // flag drop must persist for `unplugDebounce` before it counts as an unplug.
        let now = Date()
        let flags = snapshot.externalConnected || (Self.rawExternalConnected() ?? false)
        let wantAdapterOff = appliedAdapterOff == true || lastDecision?.disableAdapter == true || (control?.isAdapterDisabled() ?? false)
        if flags || (wantAdapterOff && snapshot.adapterWatts > 0) {
            pluggedIn = true
            flagsDownSince = nil
        } else {
            if flagsDownSince == nil { flagsDownSince = now }
            if now.timeIntervalSince(flagsDownSince!) >= unplugDebounce { pluggedIn = false }
        }
        pluggedBox.set(pluggedIn)
    }

    // MARK: effective limit

    /// Tracks how long the charger has been connected, refreshes the departure prediction every 10 min,
    /// and computes the limit the policy applies.
    private func updateEffectiveLimit(now: Date) {
        if pluggedIn {
            if wasPluggedIn != true {
                // At daemon start, take the plugged run from history so desk mode survives a restart.
                pluggedSince = (wasPluggedIn == nil ? DeparturePredictor.pluggedSince(samples: history.samples, now: now) : nil) ?? now
            }
        } else {
            pluggedSince = nil
        }
        wasPluggedIn = pluggedIn
        if config.smartTopUpEnabled {
            if now.timeIntervalSince(lastPrediction) >= 600 {
                predictedDeparture = DeparturePredictor.nextDeparture(samples: history.samples, now: now)
                lastPrediction = now
            }
        } else {
            predictedDeparture = nil
        }
        let ctx = LimitContext(now: now, pluggedIn: pluggedIn, pluggedSince: pluggedSince,
                               lidClosed: control?.lidClosed ?? false, predictedDeparture: predictedDeparture)
        let e = EffectiveLimit.compute(config, ctx)
        if e.limit != effective.limit || e.reason != effective.reason {
            log.notice("effective limit \(e.limit)% (\(String(describing: e.reason), privacy: .public))")
        }
        effective = e
    }

    /// Forces a new departure prediction on the next tick (after a config change).
    func invalidatePrediction() { lastPrediction = .distantPast }

    private static func rawExternalConnected() -> Bool? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        let v = IORegistryEntryCreateCFProperty(svc, "AppleRawExternalConnected" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return v as? Bool
    }

    private func sanitizedTemperature(_ t: Double?) -> Double? {
        guard let t, t > 0, t < 100 else { return nil }
        return t
    }

    private func reassertDue(_ now: Date) -> Bool { now.timeIntervalSince(lastReassert) >= reassertInterval }

    // MARK: apply

    private func apply(_ d: PolicyDecision, now: Date, errors: inout [String]) {
        guard let cc = control, backend != .none else { return }

        if cc.isLimitOnly {
            // BCLM: write the level once when it changes (or when something else changed the key).
            let want = ChargeControl.bclmValue(forLimit: d.targetPercent, offset: cc.bclmOffset)
            if appliedHardwareLimit != want || (mode.writesHardware && cc.readHardwareLimit() != want) {
                if write("BCLM \(want) (limit \(d.targetPercent)%)", errors: &errors, { try cc.applyHardwareLimit(d.targetPercent) }) {
                    appliedHardwareLimit = want
                } else {
                    appliedHardwareLimit = nil
                }
            }
            applyLED(d, cc: cc, errors: &errors)
            return
        }

        if reassertDue(now) {
            appliedInhibit = nil
            appliedAdapterOff = nil
            if ledOwned { appliedLED = nil }
            lastReassert = now
        }
        // macOS 26 (powerd / native charge limit) resets CHIE once after the first write, and can reset CHTE.
        // Read back every tick and write again when the hardware no longer matches what we applied.
        if mode.writesHardware {
            if let a = appliedAdapterOff, cc.isAdapterDisabled() != a { appliedAdapterOff = nil }
            if let i = appliedInhibit, cc.isChargingInhibited() != i { appliedInhibit = nil }
        }

        func setInhibit(_ v: Bool) -> Bool {
            if appliedInhibit == v { return true }
            if write("charging \(v ? "inhibited" : "allowed")", errors: &errors, { try cc.setChargingInhibited(v) }) {
                appliedInhibit = v; return true
            }
            appliedInhibit = nil; return false
        }
        func setAdapterOff(_ v: Bool) -> Bool {
            if appliedAdapterOff == v { return true }
            if write("adapter \(v ? "disabled" : "enabled")", errors: &errors, { try cc.setAdapterDisabled(v) }) {
                appliedAdapterOff = v; return true
            }
            appliedAdapterOff = nil; return false
        }

        if d.disableAdapter {
            // Inhibit first; only cut the adapter once charging is known to be inhibited.
            if setInhibit(d.inhibitCharging) || !d.inhibitCharging { _ = setAdapterOff(true) }
        } else {
            _ = setAdapterOff(false)
            _ = setInhibit(d.inhibitCharging)
        }

        applyLED(d, cc: cc, errors: &errors)

        // Never leave the adapter disabled because some other write failed.
        if !errors.isEmpty && appliedAdapterOff != false { ensureAdapterEnabled(&errors) }
    }

    private func applyLED(_ d: PolicyDecision, cc: ChargeControl, errors: inout [String]) {
        guard supportsLED, !ledNotificationActive else { return }
        if d.led != .system {
            if appliedLED != d.led {
                if write("LED \(d.led)", errors: &errors, { try cc.setLED(d.led) }) { appliedLED = d.led; ledOwned = true }
                else { appliedLED = nil }
            }
        } else if ledOwned {
            if write("LED system", errors: &errors, { try cc.setLED(.system) }) { appliedLED = .system; ledOwned = false }
            else { appliedLED = nil }
        }
    }

    /// After a LED notification: the next tick writes the policy LED (or hands the LED back to macOS).
    func ledNotificationFinished() {
        dispatchPrecondition(condition: .onQueue(queue))
        ledNotificationActive = false
        appliedLED = nil
        ledOwned = true
    }

    /// Writes one LED value for a notification. Returns an error message on failure.
    func writeNotificationLED(_ c: LEDColor) -> String? {
        guard let cc = control, supportsLED else { return "This Mac has no MagSafe LED" }
        guard mode.writesHardware else { return nil }
        do { try cc.setLED(c); return nil } catch { return "LED write failed: \(error)" }
    }

    /// After a BCLM offset change.
    func bclmOffsetChanged(_ offset: Int) {
        control?.bclmOffset = offset
        appliedHardwareLimit = nil
    }

    /// Writes CHIE/CH0I back to "adapter enabled". Safe to call any time.
    func ensureAdapterEnabled(_ errors: inout [String]) {
        guard let cc = control, backend != .none else { return }
        if write("adapter enabled (safety)", errors: &errors, { try cc.setAdapterDisabled(false) }) { appliedAdapterOff = false }
        else { appliedAdapterOff = nil }
    }

    /// Performs an SMC write unless in a read-only mode. Returns success.
    private func write(_ what: String, errors: inout [String], _ body: () throws -> Void) -> Bool {
        guard mode.writesHardware else { return true }
        do {
            try body()
            log.info("smc: \(what, privacy: .public)")
            return true
        } catch {
            let msg = "SMC write failed (\(what)): \(error)"
            log.error("\(msg, privacy: .public)")
            errors.append(msg)
            return false
        }
    }

    // MARK: status

    private func finishTick(decision d: PolicyDecision?, temperature smcTemp: Double?, now: Date, errors: [String], reason: String) {
        if let e = errors.last ?? smcOpenError {
            lastErrorMessage = e; lastErrorAt = now
        } else if lastErrorMessage != nil && now.timeIntervalSince(lastErrorAt) > 60 {
            lastErrorMessage = nil
        }

        var s = SimmerStatus()
        s.backend = backend
        s.supportsDischarge = supportsDischarge
        s.supportsLED = supportsLED
        s.state = d?.state ?? (backend == .none ? .unsupported : .notPluggedIn)
        s.targetPercent = d?.targetPercent ?? config.chargeLimit
        s.chargingInhibited = control?.isChargingInhibited() ?? false
        s.adapterDisabled = control?.isAdapterDisabled() ?? false
        var battery = snapshot
        battery.externalConnected = pluggedIn
        s.battery = battery
        s.smcTemperatureC = smcTemp
        s.systemPowerW = control?.systemPowerW
        s.adapterPowerW = control?.adapterInputPowerW
        s.lidClosed = control?.lidClosed ?? false
        s.sleepPrevented = mode.holdsSleepAssertion ? sleepAssertion.isHeld : (d?.preventSleep ?? false)
        s.runtime = runtime
        s.calibrationPhaseEndsAt = d?.phaseEndsAt
        if mode.runsScheduler { powerModes.refreshIfStale(now: now) }
        s.powerModes = powerModes.status
        s.lastError = lastErrorMessage
        s.updatedAt = now
        s.effectiveLimit = effective.limit
        s.limitReason = effective.reason
        s.capabilities = capabilities
        status = s

        let key = NotifyKey(state: s.state, target: s.targetPercent, inhibit: s.chargingInhibited, adapterOff: s.adapterDisabled)
        if key != lastNotified {
            lastNotified = key
            if mode.postsNotifications { notify_post(Simmer.statusNotification) }
        }

        if mode == .dryRun { printDryRunLine(d, temperature: smcTemp ?? snapshot.temperatureC, reason: reason) }
        if mode.persists { writeSharedFiles(s, now: now) }
    }

    /// history.json (5-min samples + daily health) and status.json (latest status) for the app and the widget.
    private func writeSharedFiles(_ s: SimmerStatus, now: Date) {
        if HistoryRecorder.record(&history, battery: s.battery, tempC: s.temperatureC, systemW: s.systemPowerW,
                                  plugged: pluggedIn, now: now) {
            Self.writeReadable(SimmerJSON.encode(history), to: Simmer.historyPath)
        }
        // Rewrite the snapshot when something visible changed, or every 60 s for the live numbers.
        let key = "\(s.state.rawValue)|\(s.targetPercent)|\(s.battery.percent)|\(s.battery.externalConnected)|\(s.chargingInhibited)|\(s.adapterDisabled)"
        if key != lastSnapshotKey || now.timeIntervalSince(lastSnapshotWrite) >= 60 {
            lastSnapshotKey = key; lastSnapshotWrite = now
            Self.writeReadable(SimmerJSON.encode(s), to: Simmer.statusSnapshotPath)
        }
    }

    static func writeReadable(_ data: Data, to path: String) {
        guard !data.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        } catch {
            log.error("cannot write \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func reasonText(_ r: LimitReason) -> String {
        switch r {
        case .user: return "user"
        case .deskMode: return "desk"
        case .smartTopUp(let d): return "topup-before-\(ISO8601DateFormatter().string(from: d))"
        case .waitingForCheapWindow(let d): return "cheap-from-\(ISO8601DateFormatter().string(from: d))"
        }
    }

    private func printDryRunLine(_ d: PolicyDecision?, temperature: Double, reason: String) {
        func yn(_ b: Bool) -> String { b ? "yes" : "no" }
        let ts = ISO8601DateFormatter().string(from: status.updatedAt)
        let line: String
        if let d {
            line = "\(ts) pct=\(snapshot.percent) plugged=\(yn(pluggedIn)) temp=\(String(format: "%.1f", temperature))C "
                + "state=\(d.state.rawValue) target=\(d.targetPercent) inhibit=\(yn(d.inhibitCharging)) "
                + "adapterOff=\(yn(d.disableAdapter)) led=\(d.led) preventSleep=\(yn(d.preventSleep)) "
                + "| hw inhibit=\(yn(status.chargingInhibited)) adapterOff=\(yn(status.adapterDisabled)) "
                + "effective=\(effective.limit)(\(Self.reasonText(effective.reason))) [\(reason)]"
        } else {
            line = "\(ts) battery read failed -> adapter enabled (would write) [\(reason)]"
        }
        print(line)
        fflush(stdout)
    }

    // MARK: persistence

    func persistRuntimeIfNeeded() {
        guard runtime != savedRuntime else { return }
        if store.save(runtime) { savedRuntime = runtime }
    }

    func persistConfig() {
        store.save(config)
    }

    // MARK: sleep / shutdown

    /// Called synchronously before system sleep.
    func prepareForSleep() {
        dispatchPrecondition(condition: .onQueue(queue))
        var errors: [String] = []
        ensureAdapterEnabled(&errors)
        if config.stopChargingWhenSleeping && config.limiterEnabled, let cc = control, backend != .none {
            if write("charging inhibited (sleep)", errors: &errors, { try cc.setChargingInhibited(true) }) { appliedInhibit = true }
            else { appliedInhibit = nil }
        }
        if let e = errors.last { lastErrorMessage = e; lastErrorAt = Date() }
        forceReassert()
    }

    /// Leaves the hardware in a safe state. Call on `queue`; the caller exits afterwards.
    func shutdown() {
        dispatchPrecondition(condition: .onQueue(queue))
        shuttingDown = true
        timer?.cancel()
        sleepAssertion.release()
        if mode.writesHardware { clamshellBlocker.set(false) }
        var errors: [String] = []
        if let cc = control, backend != .none {
            ensureAdapterEnabled(&errors)
            if supportsLED && mode.writesHardware {
                if write("LED system (exit)", errors: &errors, { try cc.setLED(.system) }) { ledOwned = false }
            }
            if cc.isLimitOnly {
                // BCLM persists without the daemon: keep the limit, or hand back a full charge.
                let target = config.keepLimitWhenQuit && config.limiterEnabled ? config.chargeLimit : 100
                _ = write("BCLM for limit \(target)% (exit)", errors: &errors, { try cc.applyHardwareLimit(target) })
            } else {
                let pct = BatterySnapshot.read().percent
                let keep = config.keepLimitWhenQuit && config.limiterEnabled && pct >= config.chargeLimit
                _ = write("charging \(keep ? "inhibited" : "allowed") (exit)", errors: &errors, { try cc.setChargingInhibited(keep) })
            }
        }
        persistRuntimeIfNeeded()
        log.notice("simmerd stopped (\(errors.count) errors)")
    }
}

/// A value guarded by a lock, readable from any queue.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ v: T) { value = v }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: T) { lock.lock(); value = v; lock.unlock() }
}

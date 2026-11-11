import SwiftUI
import AppKit
import Darwin
import notify
import WidgetKit
import SimmerShared

/// Per-user display preferences (stored in UserDefaults, not in the daemon config).
struct UIPrefs: Equatable {
    var showPercent = true
    var showHardwarePercent = false
    var showTemperature = false
    var showSystemWatts = false
    var notificationsEnabled = true
    /// false = Simmer jar icon in the menu bar (default), true = the classic battery symbol.
    var useBatteryIcon = false

    private static let d = UserDefaults.standard
    static func load() -> UIPrefs {
        var p = UIPrefs()
        if d.object(forKey: "showPercent") != nil { p.showPercent = d.bool(forKey: "showPercent") }
        p.showHardwarePercent = d.bool(forKey: "showHardwarePercent")
        p.showTemperature = d.bool(forKey: "showTemperature")
        p.showSystemWatts = d.bool(forKey: "showSystemWatts")
        if d.object(forKey: "notificationsEnabled") != nil { p.notificationsEnabled = d.bool(forKey: "notificationsEnabled") }
        p.useBatteryIcon = d.bool(forKey: "useBatteryIcon")
        return p
    }
    func save() {
        let d = Self.d
        d.set(showPercent, forKey: "showPercent")
        d.set(showHardwarePercent, forKey: "showHardwarePercent")
        d.set(showTemperature, forKey: "showTemperature")
        d.set(showSystemWatts, forKey: "showSystemWatts")
        d.set(notificationsEnabled, forKey: "notificationsEnabled")
        d.set(useBatteryIcon, forKey: "useBatteryIcon")
    }
}

/// Fires a completion once, from either the XPC reply or the timeout.
private final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let client = HelperClient()

    @Published private(set) var status: SimmerStatus?
    @Published private(set) var localBattery = BatterySnapshot.read()
    @Published var config = SimmerConfig()
    @Published private(set) var configLoaded = false
    /// nil = not checked yet.
    @Published private(set) var reachable: Bool?
    @Published private(set) var helperVersion: String?
    @Published private(set) var connectionError: String?
    @Published var commandError: String?
    @Published private(set) var installing = false
    @Published var prefs = UIPrefs.load() { didSet { if prefs != oldValue { prefs.save() } } }

    var helperInstalled: Bool { FileManager.default.fileExists(atPath: Simmer.helperInstallPath) }
    /// Battery data from the helper when reachable, else read directly from the IORegistry.
    var battery: BatterySnapshot { status?.battery ?? localBattery }
    var connected: Bool { reachable == true && status != nil }

    private var timer: Timer?
    private var notifyToken: Int32 = 0
    private var notifyRegistered = false
    private var statusInFlight = false
    private var configInFlight = false
    private var configHoldUntil = Date.distantPast
    private var pushWork: DispatchWorkItem?
    private var errorClearWork: DispatchWorkItem?
    private let notifier = Notifier()
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {}

    // MARK: lifecycle

    func start() {
        guard timer == nil else { return }
        notifier.requestAuthorization()
        refresh()
        let insights = InsightsModel.shared
        insights.onEvent = { event in
            Task { @MainActor in AppModel.shared.handle(event) }
        }
        insights.start()

        let t = Timer(timeInterval: 2, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.refresh() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let status = notify_register_dispatch(Simmer.statusNotification, &notifyToken, DispatchQueue.main) { _ in
            Task { @MainActor in AppModel.shared.refresh() }
        }
        notifyRegistered = status == NOTIFY_STATUS_OK

        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in InsightsModel.shared.scanConflicts() }
            })
        }
    }

    private func handle(_ event: InsightEvent) {
        guard prefs.notificationsEnabled else { return }
        switch event {
        case .cellBalancePoor(let mv): notifier.cellBalancePoor(imbalanceMV: mv)
        case .conflictsFound(let list): notifier.conflictsFound(list)
        }
    }


    // MARK: XPC with timeout

    private func call<T>(_ op: (@escaping (Result<T, Error>) -> Void) -> Void,
                         timeout: TimeInterval = 5,
                         _ done: @escaping @MainActor (Result<T, Error>) -> Void) {
        let flag = OnceFlag()
        let finish: (Result<T, Error>) -> Void = { r in
            guard flag.claim() else { return }
            Task { @MainActor in done(r) }
        }
        op(finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(.failure(HelperError.timeout)) }
    }

    // MARK: polling

    func refresh() {
        localBattery = BatterySnapshot.read()
        guard !statusInFlight else { return }
        statusInFlight = true
        let client = self.client
        call({ client.status($0) }) { [weak self] r in
            guard let self else { return }
            self.statusInFlight = false
            switch r {
            case .success(let s): self.apply(s)
            case .failure(let e): self.markUnreachable(e.localizedDescription)
            }
        }
        loadConfig()
    }

    private func loadConfig(force: Bool = false) {
        guard force || (Date() >= configHoldUntil && pushWork == nil), !configInFlight else { return }
        configInFlight = true
        let client = self.client
        call({ client.config($0) }) { [weak self] r in
            guard let self else { return }
            self.configInFlight = false
            guard case .success(let c) = r, Date() >= self.configHoldUntil, self.pushWork == nil else { return }
            if c != self.config { self.config = c }
            self.configLoaded = true
            self.autoBackupIfDue()
        }
    }

    private func apply(_ s: SimmerStatus) {
        let old = status
        status = s
        connectionError = nil
        if reachable != true {
            reachable = true
            loadVersion()
            loadConfig(force: true)
        }
        if let old, prefs.notificationsEnabled {
            notifier.diff(old: old, new: s)
            notifier.limitReasonChanged(old: old, new: s)
        }
        if prefs.notificationsEnabled {
            notifier.chargerCheck(InsightsModel.shared.chargerReport(status: s, battery: s.battery), pluggedIn: s.battery.externalConnected)
        }
        reloadWidgetIfNeeded(s)
    }

    // MARK: automatic backup

    private var lastBackupCheck = Date.distantPast

    /// Writes the weekly backup (checked at most once an hour, only with a config from the helper).
    private func autoBackupIfDue() {
        guard Date().timeIntervalSince(lastBackupCheck) > 3600 else { return }
        lastBackupCheck = Date()
        let c = config, layout = PanelLayoutStore.shared.layout
        DispatchQueue.global(qos: .utility).async {
            BackupManager.autoBackupIfDue(config: c, layout: layout)
        }
    }

    // MARK: widget

    private var widgetKey = ""
    private var lastWidgetReload = Date.distantPast
    private var widgetReloadPending = false

    /// Reloads the desktop widget when state, percent or target changes, at most once per 30 s.
    /// The reload waits at least 1 s so simmerd has rewritten status.json, which the widget reads.
    private func reloadWidgetIfNeeded(_ s: SimmerStatus) {
        let key = "\(s.state.rawValue)|\(s.battery.percent)|\(s.targetPercent)"
        guard key != widgetKey else { return }
        widgetKey = key
        guard !widgetReloadPending else { return }
        widgetReloadPending = true
        let wait = max(1, 30 - Date().timeIntervalSince(lastWidgetReload))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            Task { @MainActor in
                let m = AppModel.shared
                m.widgetReloadPending = false
                m.lastWidgetReload = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private func markUnreachable(_ message: String) {
        if reachable == true && prefs.notificationsEnabled { notifier.helperUnreachable() }
        reachable = false
        status = nil
        helperVersion = nil
        connectionError = message
    }

    func loadVersion() {
        let client = self.client
        call({ client.version($0) }) { [weak self] r in
            if case .success(let v) = r { self?.helperVersion = v }
        }
    }

    // MARK: commands

    func perform(_ cmd: SimmerCommand) {
        let client = self.client
        call({ client.perform(cmd, $0) }) { [weak self] r in
            guard let self else { return }
            if case .failure(let e) = r { self.showError(e.localizedDescription) }
            self.refresh()
        }
    }

    func setLimit(_ v: Int) {
        let v = min(100, max(20, v))
        config.chargeLimit = v
        configHoldUntil = Date().addingTimeInterval(3)
        perform(.setLimit(v))
    }

    func setLimiter(_ on: Bool) {
        config.limiterEnabled = on
        configHoldUntil = Date().addingTimeInterval(3)
        perform(.setLimiterEnabled(on))
    }

    func showError(_ message: String) {
        commandError = message
        errorClearWork?.cancel()
        let w = DispatchWorkItem { Task { @MainActor in AppModel.shared.commandError = nil } }
        errorClearWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: w)
    }

    // MARK: config editing (local copy + debounced setConfig)

    func binding<V>(_ kp: WritableKeyPath<SimmerConfig, V>) -> Binding<V> {
        Binding(get: { self.config[keyPath: kp] },
                set: { v in self.updateConfig { $0[keyPath: kp] = v } })
    }

    func updateConfig(_ mutate: (inout SimmerConfig) -> Void) {
        var c = config
        mutate(&c)
        c.clamp()
        guard c != config else { return }
        config = c
        configHoldUntil = Date().addingTimeInterval(3)
        pushWork?.cancel()
        let w = DispatchWorkItem { Task { @MainActor in AppModel.shared.pushConfig() } }
        pushWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    private func pushConfig() {
        pushWork = nil
        let c = config
        configHoldUntil = Date().addingTimeInterval(3)
        let client = self.client
        call({ client.setConfig(c, $0) }) { [weak self] r in
            guard let self else { return }
            if case .failure(let e) = r { self.showError("Could not save settings: \(e.localizedDescription)") }
            self.refresh()
        }
    }

    // MARK: schedule

    func saveTask(_ t: ScheduledTask) {
        updateConfig { cfg in
            if let i = cfg.schedule.firstIndex(where: { $0.id == t.id }) { cfg.schedule[i] = t } else { cfg.schedule.append(t) }
        }
    }

    func deleteTask(_ id: UUID) { updateConfig { $0.schedule.removeAll { $0.id == id } } }

    func runTask(_ id: UUID) { perform(.runTask(id)) }

    // MARK: helper install

    func installHelper() { runInstaller { HelperInstaller.install() } }
    func uninstallHelper(purge: Bool = false) { runInstaller { HelperInstaller.uninstall(purge: purge) } }

    private func runInstaller(_ op: @escaping () -> HelperInstaller.Outcome) {
        guard !installing else { return }
        installing = true
        // Let SwiftUI finish the current event (and dismiss the panel) before the auth prompt blocks.
        DispatchQueue.main.async {
            let outcome = op()
            Task { @MainActor in
                let m = AppModel.shared
                m.installing = false
                switch outcome {
                case .success: break
                case .cancelled: break
                case .failed(let msg): m.showError(msg)
                }
                m.client.invalidate()
                m.reachable = nil
                m.refresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Task { @MainActor in AppModel.shared.refresh() } }
            }
        }
    }

    // MARK: URL scheme

    /// simmer://limit/80, simmer://topup[/off], simmer://discharge[/off], simmer://calibrate[/stop], simmer://pause,
    /// simmer://limiter/on|off, simmer://led/system|smart|off, simmer://lpm/on|off, simmer://hpm/on|off, simmer://sleep
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "simmer" else { return }
        var parts = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        if let host = url.host(percentEncoded: false), !host.isEmpty { parts.insert(host.lowercased(), at: 0) }
        guard let verb = parts.first else { return }
        let arg = parts.count > 1 ? parts[1] : nil

        func flag(_ s: String?, default def: Bool) -> Bool? {
            guard let s else { return def }
            switch s {
            case "on", "start", "true", "1", "enable": return true
            case "off", "stop", "false", "0", "disable": return false
            default: return nil
            }
        }

        let cmd: SimmerCommand?
        switch verb {
        case "limit":
            if let s = arg, let v = Int(s), (20...100).contains(v) { setLimit(v); return }
            cmd = nil
        case "topup", "top-up": cmd = flag(arg, default: true).map { .topUp($0) }
        case "discharge": cmd = flag(arg, default: true).map { .discharge($0) }
        case "calibrate", "calibration": cmd = flag(arg, default: true).map { .calibrate($0) }
        case "pause": cmd = .pause
        case "limiter": cmd = flag(arg, default: true).map { .setLimiterEnabled($0) }
        case "led":
            switch arg {
            case "system": cmd = .setLED(.system)
            case "smart": cmd = .setLED(.smart)
            case "off", "alwaysoff": cmd = .setLED(.alwaysOff)
            case "custom": cmd = .setLED(.custom)
            default: cmd = nil
            }
        case "lpm": cmd = flag(arg, default: true).map { .setLowPowerMode($0, .all) }
        case "hpm": cmd = flag(arg, default: true).map { .setHighPowerMode($0, .all) }
        case "sleep": cmd = .sleepNow
        case "open": return          // from the desktop widget: launching / activating the app is enough
        default: cmd = nil
        }
        guard let cmd else { showError("Unknown Simmer URL: \(url.absoluteString)"); return }
        perform(cmd)
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SimmerShared

/// Events that may deserve a notification. AppModel decides whether notifications are on.
enum InsightEvent {
    case cellBalancePoor(imbalanceMV: Int)
    case conflictsFound([Conflict])
}

/// Data for the insight features that the app reads itself: energy.json, history.json, BatteryData and
/// the conflict scan. Every read runs off the main thread; the published values update on the main actor.
@MainActor
final class InsightsModel: ObservableObject {
    static let shared = InsightsModel()

    @Published var energy: EnergyReport?
    @Published var energyLoaded = false
    @Published var history: BatteryHistory? { didSet { recentPeakSystemW = Self.peak(history) } }
    @Published var details: BatteryDetails?
    @Published var conflicts: [Conflict] = []
    @Published var conflictsScanned = false
    @Published var scanning = false

    /// Called for events that can produce a notification.
    var onEvent: ((InsightEvent) -> Void)?
    /// Previews and offscreen renders set this to keep injected data (no file reads).
    var frozen = false

    private var started = false
    private var tick = 0
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {}

    /// Starts the periodic reloads: energy every 20 s, history every 5 min, battery details and conflicts every 10 min.
    func start() {
        guard !started else { return }
        started = true
        reloadEnergy(); reloadHistory(); reloadDetails(); scanConflicts()
        let t = Timer(timeInterval: 20, repeats: true) { _ in
            Task { @MainActor in InsightsModel.shared.timerFired() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in InsightsModel.shared.scanConflicts() }
            })
        }
    }

    private func timerFired() {
        tick += 1
        reloadEnergy()
        if tick % 15 == 0 { reloadHistory() }
        if tick % 30 == 0 { reloadDetails(); scanConflicts() }
    }

    // MARK: loads

    func reloadEnergy() {
        guard !frozen else { return }
        Task {
            let e = await Task.detached(priority: .utility) { EnergyReport.load() }.value
            if e != energy { energy = e }
            energyLoaded = true
        }
    }

    func reloadHistory() {
        guard !frozen else { return }
        Task {
            let h = await Task.detached(priority: .utility) { BatteryHistory.load() }.value
            if h != history { history = h }
        }
    }

    func reloadDetails() {
        guard !frozen else { return }
        Task {
            let d = await Task.detached(priority: .utility) { BatteryDetails.read() }.value
            if d != details { details = d }
            if !d.cellVoltagesMV.isEmpty, d.cellBalance == .poor { onEvent?(.cellBalancePoor(imbalanceMV: d.cellImbalanceMV)) }
        }
    }

    func scanConflicts() {
        guard !scanning, !frozen else { return }
        scanning = true
        Task {
            let found = await Task.detached(priority: .utility) { ConflictScanner.scan() }.value
            scanning = false
            if found != conflicts { conflicts = found }
            conflictsScanned = true
            if !found.isEmpty { onEvent?(.conflictsFound(found)) }
        }
    }

    // MARK: derived values

    /// Highest Mac power use in the last 7 days of history (5-minute readings). Updated when the history loads.
    private(set) var recentPeakSystemW: Double?

    static func peak(_ h: BatteryHistory?, now: Date = Date()) -> Double? {
        guard let samples = h?.samples else { return nil }
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        return samples.filter { $0.t >= cutoff }.compactMap(\.systemW).max()
    }

    func chargerReport(status: SimmerStatus?, battery: BatterySnapshot) -> ChargerReport {
        ChargerAnalyzer.report(battery: battery, systemW: status?.systemPowerW, adapterW: status?.adapterPowerW,
                               recentPeakSystemW: recentPeakSystemW)
    }

    /// Energy data older than this is shown as stale.
    static let energyStaleAfter: TimeInterval = 300

    var energyIsFresh: Bool {
        guard let e = energy else { return false }
        return Date().timeIntervalSince(e.generatedAt) < Self.energyStaleAfter
    }

    /// Watts used by Simmer itself (the app and the helper), if the energy report lists them.
    var simmerWatts: Double? {
        guard let e = energy else { return nil }
        let own = e.entries.filter { Self.isSimmer($0) }
        return own.isEmpty ? nil : own.reduce(0) { $0 + $1.watts1m }
    }

    static func isSimmer(_ e: EnergyEntry) -> Bool {
        e.id == Simmer.appBundleID || e.id.hasPrefix(Simmer.appBundleID + ".") || e.id.hasSuffix("/simmerd")
            || e.id == Simmer.helperInstallPath || e.name == "Simmer" || e.name == "simmerd"
            || e.name == Simmer.helperLabel
    }
}

// MARK: - App icons

/// Small cache of app icons for the energy lists (NSWorkspace icon lookups touch the disk).
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for e: EnergyEntry) -> NSImage {
        let key = e.bundlePath ?? e.id
        if let i = cache[key] { return i }
        let img: NSImage
        if let p = e.bundlePath, FileManager.default.fileExists(atPath: p) {
            img = NSWorkspace.shared.icon(forFile: p)
        } else if e.id.hasPrefix("/"), FileManager.default.fileExists(atPath: e.id) {
            img = NSWorkspace.shared.icon(forFile: e.id)
        } else {
            img = NSWorkspace.shared.icon(for: .unixExecutable)
        }
        cache[key] = img
        return img
    }
}

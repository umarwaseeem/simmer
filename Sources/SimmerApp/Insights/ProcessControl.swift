import SwiftUI
import AppKit
import Darwin
import SimmerShared

/// One running process as the Energy page sees it.
struct ProcRef: Equatable, Hashable, Sendable {
    let pid: pid_t
    let path: String
    let uid: uid_t?
}

/// What the Energy page may do with one row.
enum ProcessTarget: Equatable {
    /// A regular app: ask it to quit (NSRunningApplication.terminate), later force quit.
    case app(name: String, bundleID: String, pids: [pid_t])
    /// A plain process of the current user: SIGTERM, later SIGKILL.
    case process(name: String, procs: [ProcRef])
    /// Not offered. The text says why (shown as a tooltip).
    case blocked(String)
}

/// Progress of a quit / end request for one row.
enum CloseState: Equatable {
    case closing(Date)
    /// Still running a few seconds after the request: offer the forced variant.
    case stuck
    case closed(Date)
}

/// Finds the processes behind Energy rows and closes them on request. Only the current user's own apps and
/// processes are ever offered; Simmer itself, macOS system processes and other users' processes never are.
@MainActor
final class ProcessControl: ObservableObject {
    static let shared = ProcessControl()

    @Published private(set) var targets: [String: ProcessTarget] = [:]
    @Published private(set) var states: [String: CloseState] = [:]
    /// Offscreen renders set fixed targets (no process scan).
    var overrides: [String: ProcessTarget]?

    private var resolving = false

    // MARK: lookup

    /// Re-reads the process list and maps every entry to a target. Cheap (one proc_listallpids pass), runs off the main thread.
    func resolve(_ entries: [EnergyEntry]) {
        if let o = overrides { targets = o; return }
        guard !resolving else { return }
        resolving = true
        Task {
            let procs = await Task.detached(priority: .utility) { Self.scan() }.value
            let apps = NSWorkspace.shared.runningApplications.map {
                RunningApp(bundleID: $0.bundleIdentifier, pid: $0.processIdentifier, bundlePath: $0.bundleURL?.path,
                           regular: $0.activationPolicy == .regular)
            }
            var t: [String: ProcessTarget] = [:]
            for e in entries {
                t[e.id] = Self.classify(e, procs: procs, apps: apps, me: getuid(), isSimmer: InsightsModel.isSimmer(e))
            }
            targets = t
            resolving = false
        }
    }

    struct RunningApp: Equatable {
        let bundleID: String?
        let pid: pid_t
        let bundlePath: String?
        let regular: Bool
    }

    nonisolated static func scan() -> [ProcRef] {
        ProcessList.pids().compactMap { pid in
            guard let path = ProcessList.path(of: pid) else { return nil }
            return ProcRef(pid: pid, path: path, uid: owner(of: pid))
        }
    }

    nonisolated static func owner(of pid: pid_t) -> uid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info.pbi_uid : nil
    }

    // MARK: rules

    /// Processes macOS needs. Closing them logs you out, freezes the screen or is undone at once.
    nonisolated static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "Dock", "Finder", "SystemUIServer", "ControlCenter",
        "NotificationCenter", "WindowManager", "Spotlight", "coreaudiod", "cfprefsd", "distnoted", "logd", "syslogd",
        "UserEventAgent", "trustd", "securityd", "opendirectoryd", "powerd", "hidd", "bluetoothd", "airportd",
        "coreservicesd", "lsd", "fseventsd", "mds", "mds_stores", "tccd", "sharedfilelistd", "talagent", "runningboardd",
    ]
    nonisolated static let protectedBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.WindowManager", "com.apple.Spotlight",
        "com.apple.WindowServer",
    ]
    nonisolated static let systemPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/", "/private/var/", "/Library/Developer/CommandLineTools/"]

    nonisolated static func isSystemPath(_ p: String) -> Bool {
        if p.hasPrefix("/usr/local/") { return false }
        return systemPrefixes.contains { p.hasPrefix($0) }
    }

    nonisolated static let simmerReason = "Simmer cannot close itself. Use Quit in the menu bar panel."
    nonisolated static let protectedReason = "macOS needs this process. Closing it could log you out or freeze the screen."
    nonisolated static let systemReason = "A macOS system process. macOS starts and stops it by itself."
    nonisolated static let otherUserReason = "Runs as root or another user. Simmer only closes your own apps and processes."
    nonisolated static let goneReason = "Not running any more."

    nonisolated static func classify(_ e: EnergyEntry, procs: [ProcRef], apps: [RunningApp], me: uid_t,
                                     isSimmer: Bool) -> ProcessTarget {
        if isSimmer { return .blocked(simmerReason) }
        let exeName = (e.id as NSString).lastPathComponent
        if protectedNames.contains(e.name) || protectedNames.contains(exeName) { return .blocked(protectedReason) }

        if e.isApp {
            if protectedBundleIDs.contains(e.id) { return .blocked(protectedReason) }
            let running = apps.filter { $0.bundleID == e.id || ($0.bundlePath != nil && $0.bundlePath == e.bundlePath) }
            if !running.isEmpty {
                let owners = running.compactMap { a in procs.first { $0.pid == a.pid }?.uid }
                if owners.contains(where: { $0 != me }) { return .blocked(otherUserReason) }
                if e.id.hasPrefix("com.apple.") && !running.contains(where: \.regular) { return .blocked(systemReason) }
                return .app(name: e.name, bundleID: running.first?.bundleID ?? e.id, pids: running.map(\.pid))
            }
            // An app bundle without an app process (for example a login item helper): its plain processes.
            guard let bundle = e.bundlePath else { return .blocked(goneReason) }
            let inside = procs.filter { $0.path.hasPrefix(bundle + "/") }
            if inside.isEmpty { return .blocked(goneReason) }
            if isSystemPath(bundle) { return .blocked(systemReason) }
            let mine = inside.filter { $0.uid == me }
            return mine.isEmpty ? .blocked(otherUserReason) : .process(name: e.name, procs: mine)
        }

        let matching = procs.filter { $0.path == e.id }
        if matching.isEmpty { return .blocked(goneReason) }
        if isSystemPath(e.id) { return .blocked(systemReason) }
        let mine = matching.filter { $0.uid == me }
        return mine.isEmpty ? .blocked(otherUserReason) : .process(name: e.name, procs: mine)
    }

    // MARK: actions

    /// Asks the app to quit. It can still ask the user to save; after 5 s a still-running app can be force quit.
    func quit(_ id: String, bundleID: String, force: Bool = false) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !apps.isEmpty else { finish(id); return }
        states[id] = .closing(Date())
        for a in apps { _ = force ? a.forceTerminate() : a.terminate() }
        check(id, after: force ? 1.5 : 5) {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
        }
    }

    /// Sends SIGTERM (or SIGKILL) to the processes, after checking again that each pid still runs the same
    /// executable for the same user, so a reused pid is never hit.
    func end(_ id: String, procs: [ProcRef], force: Bool = false) {
        let me = getuid()
        let live = procs.filter { p in
            p.pid > 1 && p.pid != getpid() && ProcessList.path(of: p.pid) == p.path && Self.owner(of: p.pid) == me
        }
        guard !live.isEmpty else { finish(id); return }
        states[id] = .closing(Date())
        for p in live { kill(p.pid, force ? SIGKILL : SIGTERM) }
        check(id, after: force ? 1 : 3) {
            live.contains { kill($0.pid, 0) == 0 && ProcessList.path(of: $0.pid) == $0.path }
        }
    }

    private func check(_ id: String, after seconds: Double, stillRunning: @escaping @MainActor () -> Bool) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if stillRunning() { states[id] = .stuck } else { finish(id) }
        }
    }

    private func finish(_ id: String) {
        states[id] = .closed(Date())
        InsightsModel.shared.reloadEnergy()
    }

    /// True while a closed row should stay hidden: until a report newer than the close arrives.
    func hides(_ id: String, reportTime: Date) -> Bool {
        if case .closed(let at) = states[id] { return reportTime < at.addingTimeInterval(60) }
        return false
    }

    func setStateForPreview(_ id: String, _ s: CloseState?) { states[id] = s }
}

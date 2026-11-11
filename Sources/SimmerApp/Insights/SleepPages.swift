import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SimmerShared

// MARK: - Sleep drain detective

enum SleepLoad: Equatable {
    case loading
    case loaded([SleepSession], Date)
}

struct SleepDrainPage: View {
    @State private var load: SleepLoad
    private let autoLoad: Bool

    /// `initial` and `autoLoad: false` are for previews and offscreen renders.
    init(initial: SleepLoad = .loading, autoLoad: Bool = true) {
        _load = State(initialValue: initial)
        self.autoLoad = autoLoad
    }

    var body: some View {
        Form {
            Section { PageHeader(page: .sleepDrain) }
            switch load {
            case .loading:
                Section {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading the macOS power log… this can take a few seconds.").foregroundStyle(.secondary)
                    }
                }
            case .loaded(let all, let at):
                let sessions = all.filter { $0.hours >= 0.25 }.sorted { $0.start > $1.start }
                if sessions.isEmpty {
                    Section {
                        EmptyState(symbol: "moon.zzz", title: "No sleeps found",
                                   message: "Simmer found no sleep longer than 15 minutes in the last 7 days of the macOS power log. Close the lid tonight and check again tomorrow.") {
                            Button("Read Again") { reload() }
                        }
                    }
                } else {
                    Section {
                        SleepVerdict(analysis: SleepAnalysis(sessions: sessions))
                    }
                    Section {
                        SleepTiles(analysis: SleepAnalysis(sessions: sessions))
                    }
                    Section {
                        ForEach(sessions) { SleepSessionRow(session: $0) }
                    } header: {
                        RefreshHeader(title: "Sleeps, Last 7 Days", topic: .sleepDrain, updated: at, busy: false) { reload() }
                    } footer: {
                        SectionCaption("On battery, a sleeping Mac should lose about 1% per hour or less. Sleeps on the charger show wakes only.")
                    }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    tip("Turn off Wake for network access in System Settings → Battery → Options.")
                    tip("Turn off Power Nap, or limit it to the charger.")
                    tip("Unplug USB devices and docks that can wake the Mac.")
                    tip("Bluetooth mice and keyboards can wake the Mac when they move.")
                }
            } header: {
                HelpLabel("Fewer Wakes, Less Drain", .darkWakes)
            }
        }
        .formStyle(.grouped)
        .task { if autoLoad { await read() } }
    }

    private func tip(_ s: String) -> some View {
        Label { Text(s).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "lightbulb").foregroundStyle(.yellow) }
            .font(.callout)
    }

    private func reload() {
        load = .loading
        Task { await read() }
    }

    private func read() async {
        let s = await Task.detached(priority: .userInitiated) { SleepLogParser.recentSessions(days: 7) }.value
        load = .loaded(s, Date())
    }
}

/// Numbers and the verdict sentence for a list of sleeps (newest first).
struct SleepAnalysis {
    let sessions: [SleepSession]

    /// True when the sleep covers part of the night (00:00–06:00 local time).
    static func isNight(_ s: SleepSession, calendar: Calendar = .current) -> Bool {
        let end = s.end ?? s.start
        var day = calendar.startOfDay(for: s.start)
        while day <= end {
            let nightEnd = day.addingTimeInterval(6 * 3600)
            if s.start < nightEnd && end > day { return true }
            day = day.addingTimeInterval(86_400)
        }
        return false
    }

    /// The sleep the verdict talks about: last night's sleep when there was one (ended in the last 20 hours),
    /// else the newest sleep of 1 hour or more, else the newest sleep.
    var focus: (session: SleepSession, isLastNight: Bool)? {
        let cutoff = Date().addingTimeInterval(-20 * 3600)
        if let n = sessions.first(where: { ($0.end ?? $0.start) >= cutoff && $0.hours >= 2 && Self.isNight($0) }) { return (n, true) }
        if let s = sessions.first(where: { $0.hours >= 1 }) ?? sessions.first { return (s, false) }
        return nil
    }

    /// Sleeps on battery that lost charge, 1 hour or longer (short sleeps give noisy rates).
    private var drainSamples: [SleepSession] {
        sessions.filter { $0.onBattery && $0.hours >= 1 && ($0.percentStart ?? 0) >= ($0.percentEnd ?? 0) && $0.percentLost != nil }
    }

    /// Total percent lost ÷ total hours, over the sleeps above.
    var averageDrainOnBattery: Double? {
        let s = drainSamples
        let h = s.reduce(0) { $0 + $1.hours }
        guard h > 0 else { return nil }
        return Double(s.reduce(0) { $0 + ($1.percentLost ?? 0) }) / h
    }

    /// Median wake count of sleeps of 2 hours or more.
    var typicalWakesPerNight: Int? {
        let counts = sessions.filter { $0.hours >= 2 }.map(\.wakes.count).sorted()
        return counts.isEmpty ? nil : counts[counts.count / 2]
    }

    var worst: SleepSession? {
        drainSamples.max { ($0.percentPerHour ?? 0) < ($1.percentPerHour ?? 0) }
    }

    static func topReasons(_ s: SleepSession, limit: Int = 3) -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for w in s.wakes { counts[WakeReason.friendly(w.reason), default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map { ($0.key, $0.value) }
    }

    var verdict: (title: String, message: String?, tint: Color, symbol: String) {
        guard let f = focus else { return ("No sleeps found", nil, .secondary, "moon.zzz") }
        let s = f.session
        let when = f.isLastNight ? "last night" : "during its last sleep (\(s.start.formatted(.dateTime.weekday(.wide).hour().minute())))"
        let n = s.wakes.count
        let title: String
        if n == 0 {
            title = "Your Mac slept \(when) without waking up."
        } else if let top = Self.topReasons(s, limit: 1).first {
            title = "Your Mac woke \(n) time\(n == 1 ? "" : "s") \(when), mostly for \(top.0)."
        } else {
            title = "Your Mac woke \(n) times \(when)."
        }
        let rate = s.onBattery ? s.percentPerHour : nil
        let charged = (s.percentEnd ?? 0) > (s.percentStart ?? 0)
        let drainBad = (rate ?? 0) > 2, manyWakes = n > 30
        var msg: String? = nil
        if !s.onBattery {
            msg = "It was on the charger, so the battery did not drain."
        } else if charged {
            msg = "The battery charged during this sleep, so Simmer cannot rate the drain."
        } else if let lost = s.percentLost, let r = rate {
            msg = String(format: "It lost %d%% in %@ (%.1f%% per hour).", lost, DurationText.hours(s.hours), r)
            if drainBad { msg! += " That is more than it should. See the tips below." }
            else if manyWakes { msg! += " The drain is fine, but fewer wakes would save more." }
            else if r <= 1 { msg! += " That is healthy." }
        }
        if drainBad { return (title, msg, .orange, "exclamationmark.triangle.fill") }
        if manyWakes { return (title, msg, .blue, "moon.stars.fill") }
        return (title, msg, .green, "checkmark.seal.fill")
    }
}

enum WakeReason {
    /// Turns raw pmset wake reasons into plain words.
    static func friendly(_ raw: String) -> String {
        let r = raw.lowercased()
        if r.contains("maintenance") || r.contains("rtc") { return "scheduled maintenance (Power Nap)" }
        if r.contains("useractivity") || r.contains("user") { return "you" }
        if r.contains("arpt") || r.contains("wlan") || r.contains("wifi") || r.contains("network") || r.contains("enet") { return "network activity" }
        if r.contains("bluetooth") || r.hasPrefix("bt") || r.contains(".bt") { return "Bluetooth devices" }
        if r.contains("xhc") || r.contains("usb") { return "USB devices" }
        if r.contains("lid") || r.contains("spmi") { return "the lid" }
        if r.contains("acattach") || r.contains("ac ") || r.contains("adapter") || r.contains("charger") { return "the charger" }
        if r.contains("notification") || r.contains("push") || r.contains("apns") { return "notifications" }
        if r.contains("smc") || r.contains("sysstate") { return "the power controller" }
        if r.contains("timer") || r.contains("schedule") { return "a scheduled timer" }
        return raw.isEmpty ? "an unknown reason" : raw
    }
}

struct SleepVerdict: View {
    let analysis: SleepAnalysis
    var body: some View {
        let v = analysis.verdict
        VerdictRow(symbol: v.symbol, tint: v.tint, title: v.title, message: v.message)
    }
}

struct SleepTiles: View {
    let analysis: SleepAnalysis
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SummaryTile(symbol: "battery.25percent", tint: .indigo, title: "Drain on Battery",
                        value: analysis.averageDrainOnBattery.map { String(format: "%.1f%%/h", $0) } ?? "–",
                        detail: analysis.averageDrainOnBattery == nil ? "No long sleep on battery yet" : "Average while asleep",
                        topic: .sleepDrain)
            Divider().padding(.horizontal, 12)
            SummaryTile(symbol: "bell.badge", tint: .orange, title: "Wakes per Night",
                        value: analysis.typicalWakesPerNight.map { "\($0)" } ?? "–",
                        detail: "Typical, sleeps of 2 h or more", topic: .darkWakes)
            Divider().padding(.horizontal, 12)
            SummaryTile(symbol: "exclamationmark.triangle", tint: .red, title: "Worst Sleep",
                        value: analysis.worst?.percentPerHour.map { String(format: "%.1f%%/h", $0) } ?? "–",
                        detail: analysis.worst.map { $0.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "Nothing to report",
                        topic: .sleepDrain)
        }
        .padding(.vertical, 4)
    }
}

struct SleepSessionRow: View {
    let session: SleepSession
    var body: some View {
        let s = session
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: s.onBattery ? "battery.50percent" : "powerplug.fill")
                .foregroundStyle(s.onBattery ? Color.indigo : Color.green).frame(width: 20)
                .help(s.onBattery ? "On battery" : "On the charger")
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(range).font(.callout.weight(.medium))
                    Text(DurationText.hours(s.hours)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if s.onBattery, let a = s.percentStart, let b = s.percentEnd, b > a {
                        Text("Charged").font(.callout).foregroundStyle(.secondary)
                    } else if let r = s.percentPerHour, s.onBattery {
                        Text(String(format: "%.1f%%/h", r)).monospacedDigit().font(.callout.weight(.semibold))
                            .foregroundStyle(r > 2 ? Color.orange : (r <= 1 ? Color.green : Color.primary))
                    }
                }
                HStack(spacing: 10) {
                    if let a = s.percentStart, let b = s.percentEnd {
                        Label("\(a)% → \(b)%", systemImage: "percent").labelStyle(.titleOnly)
                    }
                    Label("\(s.wakes.count) wake\(s.wakes.count == 1 ? "" : "s")", systemImage: "bell")
                    if !s.reason.isEmpty { Text(s.reason).foregroundStyle(.tertiary) }
                }
                .font(.caption).foregroundStyle(.secondary)
                let top = SleepAnalysis.topReasons(s)
                if !top.isEmpty {
                    Text("Woken by " + top.map { "\($0.0) (\($0.1))" }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 1)
    }

    private var range: String {
        let start = session.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        guard let end = session.end else { return start }
        return "\(start) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Why won't my Mac sleep?

struct SleepBlockersPage: View {
    @State private var blockers: [SleepBlocker]?
    @State private var updated: Date?
    private let autoLoad: Bool

    init(initial: [SleepBlocker]? = nil, autoLoad: Bool = true) {
        _blockers = State(initialValue: initial)
        self.autoLoad = autoLoad
    }

    var body: some View {
        Form {
            Section { PageHeader(page: .sleepBlockers) }
            Section {
                if let list = blockers {
                    let groups = BlockerGroup.group(list)
                    if groups.isEmpty {
                        EmptyState(symbol: "moon.zzz.fill", title: "Nothing keeps your Mac awake",
                                   message: "No app or process asks macOS to stay awake right now. Your Mac can sleep normally.",
                                   tint: .green)
                    } else {
                        ForEach(groups) { BlockerRow(group: $0) }
                    }
                } else {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
                }
            } header: {
                RefreshHeader(title: "Keeping Your Mac Awake", topic: .sleepBlockers, updated: updated, busy: false) {
                    Task { await read() }
                }
            } footer: {
                SectionCaption("Quit is offered only for regular apps. System processes are never stopped: they finish their task (for example a backup) and let go by themselves.")
            }
            Section("What the Types Mean") {
                ForEach(BlockerGroup.typeHelp, id: \.0) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(BlockerGroup.plain(t.0)) · \(t.0)").font(.callout.weight(.medium))
                        Text(t.1).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            while autoLoad && !Task.isCancelled {
                await read()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func read() async {
        blockers = await Task.detached(priority: .utility) { SleepBlocker.current() }.value
        updated = Date()
    }
}

struct BlockerGroup: Identifiable {
    let pid: Int32
    let processName: String
    let items: [SleepBlocker]
    var id: Int32 { pid }

    static func group(_ list: [SleepBlocker]) -> [BlockerGroup] {
        Dictionary(grouping: list, by: \.pid)
            .map { BlockerGroup(pid: $0.key, processName: $0.value.first?.processName ?? "pid \($0.key)", items: $0.value) }
            .sorted { $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending }
    }

    static func plain(_ type: String) -> String {
        switch type {
        case "PreventUserIdleSystemSleep", "NoIdleSleepAssertion": return "Keeps the Mac awake"
        case "PreventSystemSleep": return "Blocks all sleep"
        case "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion": return "Keeps the screen on"
        case "PreventDiskIdle": return "Keeps the disk awake"
        case "NetworkClientActive": return "Network task"
        case "BackgroundTask": return "Background task"
        case "ApplePushServiceTask": return "Notification delivery"
        case "UserIsActive": return "You are active"
        case "InternalPreventSleep", "InternalPreventDisplaySleep": return "System task"
        default: return type
        }
    }

    static let typeHelp: [(String, String)] = [
        ("PreventUserIdleSystemSleep", "The Mac does not sleep by itself, but you can still close the lid or choose Sleep."),
        ("PreventSystemSleep", "Blocks every kind of sleep, often for a backup, a download or a running server."),
        ("PreventUserIdleDisplaySleep", "Keeps the screen on, for example during a video or a presentation."),
        ("BackgroundTask", "macOS runs a short maintenance task. It stops by itself."),
    ]

    /// A regular app with a Dock icon that may be quit. System processes never qualify.
    var app: NSRunningApplication? {
        guard pid != ProcessInfo.processInfo.processIdentifier,
              let a = NSRunningApplication(processIdentifier: pid),
              a.activationPolicy == .regular,
              a.bundleIdentifier != "com.apple.finder" else { return nil }
        return a
    }
}

struct BlockerRow: View {
    let group: BlockerGroup
    @State private var quitting = false

    var body: some View {
        let app = group.app
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let icon = app?.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(for: .unixExecutable)).resizable()
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app?.localizedName ?? group.processName).font(.callout.weight(.semibold))
                    Text("pid \(String(group.pid))").font(.caption2).foregroundStyle(.tertiary)
                    if app == nil {
                        Text("Background").font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
                ForEach(group.items) { b in
                    HStack(spacing: 6) {
                        Text(BlockerGroup.plain(b.assertionType)).font(.caption.weight(.medium))
                        Text(b.name).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        if let since = b.since {
                            Text("since \(since.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .help(b.assertionType)
                }
            }
            Spacer(minLength: 8)
            if let app {
                Button(quitting ? "Quitting…" : "Quit") {
                    quitting = true
                    app.terminate()
                }
                .controlSize(.small)
                .disabled(quitting)
                .help("Ask \(app.localizedName ?? "the app") to quit. It can still ask you to save your work.")
            }
        }
        .padding(.vertical, 2)
    }
}

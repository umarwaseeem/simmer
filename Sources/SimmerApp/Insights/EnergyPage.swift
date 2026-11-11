import SwiftUI
import AppKit
import SimmerShared

enum EnergySort: String, CaseIterable {
    case name, now, hour, cpu, wakeups, sinceUnplug
}

struct EnergyPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var insights: InsightsModel = .shared
    @AppStorage("energySort") private var sortRaw = EnergySort.now.rawValue
    @AppStorage("energyShowProcesses") private var showProcesses = true
    @ObservedObject private var control: ProcessControl = .shared
    @State private var pending: PendingClose?

    private var sort: EnergySort { EnergySort(rawValue: sortRaw) ?? .now }

    var body: some View {
        Form {
            Section { PageHeader(page: .energy) }

            if let e = insights.energy, !e.entries.isEmpty {
                Section {
                    EnergyTiles(report: e, simmerWatts: insights.simmerWatts, systemW: model.status?.systemPowerW)
                }
                Section {
                    EnergyTableHeader(sort: sort) { sortRaw = $0.rawValue }
                    ForEach(rows(e)) { entry in
                        EnergyTableRow(entry: entry, isSimmer: InsightsModel.isSimmer(entry)) {
                            ProcessCloseButton(target: control.targets[entry.id], state: control.states[entry.id]) { action in
                                handle(action, entry: entry)
                            }
                        }
                    }
                } header: {
                    HStack {
                        HelpLabel(showProcesses ? "Apps & Processes" : "Apps", .energy)
                        Spacer()
                        if !insights.energyIsFresh {
                            Label("Old data: is the helper running?", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(.orange)
                                .help("The newest measurement is more than 5 minutes old. The helper measures every 60 seconds.")
                        }
                        Toggle("Include background processes", isOn: $showProcesses)
                            .toggleStyle(.checkbox).controlSize(.small)
                    }
                } footer: {
                    SectionCaption("Click a column title to sort. Watts are estimates from processor and graphics time; the screen, SSD and other parts are not included. \"Since unplug\" is empty while the charger is connected. Quit asks an app to close, so it can still ask you to save. End stops one of your own background processes. Simmer never offers it for macOS system processes or other users' processes.")
                }
            } else {
                Section {
                    if !insights.energyLoaded {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) }
                    } else {
                        EmptyState(symbol: "flame", title: "No energy data yet",
                                   message: model.connected
                                       ? "The helper measures each app's power once a minute and saves it to energy.json. If this stays empty, update the helper."
                                       : "The helper measures app energy, because only it can read every process. Install the helper to see which apps drain the battery.") {
                            PageLinkButton("Open Helper", page: .helper)
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    explain("bolt.fill", "Now and 1 h", "Power in watts over the last minute and the last hour. The 1-hour average finds slow background drains.")
                    explain("cpu", "CPU", "Processor use. 100% is one full core, so busy apps can show more than 100%.")
                    explain("alarm", "Wakeups", "How often per second the process wakes the chip. Many wakeups stop the chip from resting.")
                    explain("battery.50percent", "Since unplug", "Energy in watt-hours since you last unplugged. A full MacBook battery holds about 50–100 Wh.")
                }
            } header: {
                Text("What the Columns Mean")
            }
        }
        .formStyle(.grouped)
        .pageRefresh(busy: insights.energyLoading, updated: insights.energy?.generatedAt,
                     note: "the helper measures every 60 s") {
            insights.reloadEnergy()
            control.resolve(insights.energy?.entries ?? [])
        }
        .onChange(of: insights.energy) { _, e in control.resolve(e?.entries ?? []) }
        .onAppear { control.resolve(insights.energy?.entries ?? []) }
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { p in
            Button(p.confirm, role: .destructive) { perform(p) }
            Button("Cancel", role: .cancel) {}
        } message: { p in
            Text(p.message)
        }
        .task {
            while !Task.isCancelled {
                insights.reloadEnergy()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func handle(_ action: ProcessCloseButton.Action, entry: EnergyEntry) {
        switch (action, control.targets[entry.id]) {
        case (.close, .app(_, let bundleID, _)?):
            control.quit(entry.id, bundleID: bundleID)          // the app itself asks about unsaved work
        case (.close, .process(let name, let procs)?):
            pending = .end(id: entry.id, name: name, procs: procs)
        case (.force, .app(let name, let bundleID, let pids)?):
            pending = .forceQuit(id: entry.id, name: name, bundleID: bundleID, pids: pids)
        case (.force, .process(let name, let procs)?):
            pending = .forceEnd(id: entry.id, name: name, procs: procs)
        default:
            break
        }
    }

    private func perform(_ p: PendingClose) {
        switch p {
        case .end(let id, _, let procs): control.end(id, procs: procs)
        case .forceEnd(let id, _, let procs): control.end(id, procs: procs, force: true)
        case .forceQuit(let id, _, let bundleID, _): control.quit(id, bundleID: bundleID, force: true)
        }
    }

    private func explain(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            Text(title).fontWeight(.medium).frame(width: 90, alignment: .leading)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    private func rows(_ e: EnergyReport) -> [EnergyEntry] {
        let shown = e.entries.filter { !control.hides($0.id, reportTime: e.generatedAt) }
        let list = showProcesses ? shown : shown.filter(\.isApp)
        switch sort {
        case .name: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .now: return list.sorted { $0.watts1m > $1.watts1m }
        case .hour: return list.sorted { $0.watts1h > $1.watts1h }
        case .cpu: return list.sorted { $0.cpuPercent1m > $1.cpuPercent1m }
        case .wakeups: return list.sorted { $0.wakeupsPerSec1m > $1.wakeupsPerSec1m }
        case .sinceUnplug: return list.sorted { ($0.energySinceUnplugWh ?? -1) > ($1.energySinceUnplugWh ?? -1) }
        }
    }
}

struct EnergyTiles: View {
    let report: EnergyReport
    let simmerWatts: Double?
    let systemW: Double?

    var body: some View {
        let top = report.entries.filter { !InsightsModel.isSimmer($0) }.max { $0.watts1m < $1.watts1m }
        HStack(alignment: .top, spacing: 0) {
            SummaryTile(symbol: "flame.fill", tint: .orange, title: "Apps Total",
                        value: EnergyFmt.watts(report.totalWatts1m),
                        detail: systemW.map { String(format: "Whole Mac: %.1f W", $0) } ?? "Processor and graphics only",
                        topic: .energy)
            Divider().padding(.horizontal, 12)
            SummaryTile(symbol: "crown.fill", tint: .yellow, title: "Hungriest",
                        value: top?.name ?? "–",
                        detail: top.map { EnergyFmt.watts($0.watts1m) + " now" } ?? "Nothing busy",
                        topic: .energyNow)
            Divider().padding(.horizontal, 12)
            SummaryTile(symbol: "leaf.fill", tint: .green, title: "Simmer Itself",
                        value: simmerWatts.map { EnergyFmt.watts($0) } ?? "< 0.01 W",
                        detail: "App and helper together",
                        topic: .topApps)
        }
        .padding(.vertical, 4)
    }
}

/// Column widths shared by the header and the rows.
enum EnergyColumns {
    static let now: CGFloat = 58, hour: CGFloat = 58, cpu: CGFloat = 52, wake: CGFloat = 56, unplug: CGFloat = 62
    static let action: CGFloat = 78
}

struct EnergyTableHeader: View {
    let sort: EnergySort
    let set: (EnergySort) -> Void

    var body: some View {
        HStack(spacing: 6) {
            column("Name", .name, nil, alignment: .leading)
            column("Now", .now, EnergyColumns.now, topic: .energyNow)
            column("1 h", .hour, EnergyColumns.hour, topic: .energyHour)
            column("CPU", .cpu, EnergyColumns.cpu, topic: .cpuPercent)
            column("Wake/s", .wakeups, EnergyColumns.wake, topic: .wakeups)
            column("Unplug", .sinceUnplug, EnergyColumns.unplug, topic: .sinceUnplug)
            Color.clear.frame(width: EnergyColumns.action, height: 1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func column(_ title: String, _ key: EnergySort, _ width: CGFloat?, alignment: Alignment = .trailing, topic: HelpTopic? = nil) -> some View {
        let b = Button { set(key) } label: {
            HStack(spacing: 2) {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(title).foregroundStyle(sort == key ? Color.primary : Color.secondary)
                if sort == key { Image(systemName: key == .name ? "chevron.up" : "chevron.down").imageScale(.small) }
                if alignment == .leading { Spacer(minLength: 0) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(topic.map { $0.tooltip } ?? "Sort by name")
        if let width { b.frame(width: width) } else { b.frame(maxWidth: .infinity) }
    }
}

struct EnergyTableRow<Action: View>: View {
    let entry: EnergyEntry
    let isSimmer: Bool
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 7) {
                Image(nsImage: AppIcons.icon(for: entry)).resizable().frame(width: 18, height: 18)
                    .help(entry.id)
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.name).lineLimit(1).truncationMode(.middle)
                        .fontWeight(isSimmer ? .semibold : .regular)
                        .foregroundStyle(isSimmer ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    if entry.pidCount > 1 || !entry.isApp {
                        Text(entry.isApp ? "\(entry.pidCount) processes" : "Background process")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            num(EnergyFmt.watts(entry.watts1m), EnergyColumns.now, bold: true)
            num(EnergyFmt.watts(entry.watts1h), EnergyColumns.hour)
            num(String(format: "%.0f%%", entry.cpuPercent1m), EnergyColumns.cpu)
            num(String(format: "%.0f", entry.wakeupsPerSec1m), EnergyColumns.wake)
            num(entry.energySinceUnplugWh.map { String(format: "%.1f Wh", $0) } ?? "–", EnergyColumns.unplug)
            action().frame(width: EnergyColumns.action, alignment: .trailing)
        }
        .font(.callout)
    }

    private func num(_ s: String, _ w: CGFloat, bold: Bool = false) -> some View {
        Text(s).monospacedDigit().fontWeight(bold ? .medium : .regular)
            .foregroundStyle(bold ? .primary : .secondary)
            .frame(width: w, alignment: .trailing)
    }
}

// MARK: - Closing apps and processes

/// A request that needs a confirmation first.
enum PendingClose: Identifiable {
    case end(id: String, name: String, procs: [ProcRef])
    case forceEnd(id: String, name: String, procs: [ProcRef])
    case forceQuit(id: String, name: String, bundleID: String, pids: [pid_t])

    var id: String {
        switch self {
        case .end(let id, _, _), .forceEnd(let id, _, _), .forceQuit(let id, _, _, _): return id
        }
    }

    private static func pidList(_ pids: [pid_t]) -> String {
        let shown = pids.prefix(6).map(String.init).joined(separator: ", ")
        return (pids.count == 1 ? "pid " : "pids ") + shown + (pids.count > 6 ? " and \(pids.count - 6) more" : "")
    }

    var title: String {
        switch self {
        case .end(_, let name, _): return "End \u{201C}\(name)\u{201D}?"
        case .forceEnd(_, let name, _): return "Force end \u{201C}\(name)\u{201D}?"
        case .forceQuit(_, let name, _, _): return "Force quit \u{201C}\(name)\u{201D}?"
        }
    }

    var confirm: String {
        switch self {
        case .end: return "End Process"
        case .forceEnd: return "Force End"
        case .forceQuit: return "Force Quit"
        }
    }

    var message: String {
        switch self {
        case .end(_, _, let procs):
            return "Simmer asks \(Self.pidList(procs.map(\.pid))) to stop (SIGTERM). Any unsaved work in this process can be lost."
        case .forceEnd(_, _, let procs):
            return "\(Self.pidList(procs.map(\.pid))) did not stop. Force end closes it at once (SIGKILL). Unsaved work is lost."
        case .forceQuit(_, let name, _, let pids):
            return "\(name) (\(Self.pidList(pids))) did not quit. Force quit closes it at once. Unsaved changes are lost."
        }
    }
}

/// The last column of an Energy row: Quit / End…, then Force Quit… / Force End… if it keeps running.
struct ProcessCloseButton: View {
    enum Action { case close, force }
    let target: ProcessTarget?
    let state: CloseState?
    let act: (Action) -> Void

    var body: some View {
        switch (target, state) {
        case (nil, _):
            EmptyView()
        case (.blocked(let why)?, _):
            Image(systemName: "lock.fill")
                .font(.caption).foregroundStyle(.tertiary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
                .help(why)
                .accessibilityLabel("Cannot be closed")
                .accessibilityHint(why)
        case (_, .closing?):
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Closing").font(.caption).foregroundStyle(.secondary)
            }
        case (_, .closed?):
            Label("Closed", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
        case (.app(let name, _, _)?, .stuck?):
            forceButton("Force Quit…", help: "\(name) is still running. Force quit closes it at once.")
        case (.process(let name, _)?, .stuck?):
            forceButton("Force End…", help: "\(name) is still running. Force end closes it at once.")
        case (.app(let name, _, _)?, nil):
            Button("Quit") { act(.close) }
                .controlSize(.small)
                .help("Ask \(name) to quit. It can still ask you to save your work.")
        case (.process(let name, let procs)?, nil):
            Button("End…") { act(.close) }
                .controlSize(.small)
                .help("Stop \(name) (\(procs.count == 1 ? "pid \(procs[0].pid)" : "\(procs.count) processes")). Simmer asks you first.")
        }
    }

    private func forceButton(_ title: String, help: String) -> some View {
        Button(title) { act(.force) }
            .controlSize(.small)
            .tint(.red)
            .help(help)
    }
}

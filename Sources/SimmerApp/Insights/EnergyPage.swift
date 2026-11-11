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
                        EnergyTableRow(entry: entry, isSimmer: InsightsModel.isSimmer(entry))
                    }
                } header: {
                    HStack {
                        HelpLabel(showProcesses ? "Apps & Processes" : "Apps", .energy)
                        Spacer()
                        Toggle("Include background processes", isOn: $showProcesses)
                            .toggleStyle(.checkbox).controlSize(.small)
                        Text("Updated \(e.generatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(insights.energyIsFresh ? Color.secondary : Color.orange)
                    }
                } footer: {
                    SectionCaption("Click a column title to sort. Watts are estimates from processor and graphics time; the screen, SSD and other parts are not included. \"Since unplug\" is empty while the charger is connected.")
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
        .task {
            while !Task.isCancelled {
                insights.reloadEnergy()
                try? await Task.sleep(for: .seconds(15))
            }
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
        let list = showProcesses ? e.entries : e.entries.filter(\.isApp)
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
    static let now: CGFloat = 58, hour: CGFloat = 58, cpu: CGFloat = 52, wake: CGFloat = 60, unplug: CGFloat = 66
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

struct EnergyTableRow: View {
    let entry: EnergyEntry
    let isSimmer: Bool

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 7) {
                Image(nsImage: AppIcons.icon(for: entry)).resizable().frame(width: 18, height: 18)
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
        }
        .font(.callout)
        .help(entry.id)
    }

    private func num(_ s: String, _ w: CGFloat, bold: Bool = false) -> some View {
        Text(s).monospacedDigit().fontWeight(bold ? .medium : .regular)
            .foregroundStyle(bold ? .primary : .secondary)
            .frame(width: w, alignment: .trailing)
    }
}

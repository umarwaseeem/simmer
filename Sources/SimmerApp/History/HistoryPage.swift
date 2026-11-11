import SwiftUI
import SimmerShared

/// State of the history file.
enum HistoryLoad: Equatable {
    case loading
    case missing
    case loaded(BatteryHistory)

    var history: BatteryHistory? {
        if case .loaded(let h) = self { return h }
        return nil
    }
}

enum LongTermMetric: String, CaseIterable, Identifiable {
    case health = "Health", capacity = "Capacity"
    var id: String { rawValue }
}

struct HistoryPage: View {
    @ObservedObject var model: AppModel
    @State private var load: HistoryLoad
    @State private var loadedAt: Date?
    @AppStorage("historyRange") private var rangeRaw = HistoryRange.day.rawValue
    @AppStorage("historyLongTermMetric") private var metricRaw = LongTermMetric.health.rawValue

    /// Reload interval while the page is visible.
    static let reloadInterval: Duration = .seconds(60)
    static let thinDataMessage = "Simmer records a point every 5 minutes and a health summary every day — check back tomorrow."

    private let autoReload: Bool

    /// `initial` and `autoReload: false` are for previews and offscreen renders.
    init(model: AppModel, initial: HistoryLoad = .loading, autoReload: Bool = true) {
        self.model = model
        self.autoReload = autoReload
        _load = State(initialValue: initial)
    }

    private var range: HistoryRange { HistoryRange(rawValue: rangeRaw) ?? .day }
    private var metric: LongTermMetric { LongTermMetric(rawValue: metricRaw) ?? .health }

    var body: some View {
        let now = Date()
        let history = load.history
        let daily = (history?.daily ?? []).sorted { $0.day < $1.day }
        let summary = HistorySummary(history: history, live: model.battery, now: now)

        Form {
            Section { PageHeader(page: .history) }

            Section {
                SummaryTiles(summary: summary)
            }

            switch load {
            case .loading:
                Section {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading history…").foregroundStyle(.secondary)
                    }
                }
            case .missing:
                Section { MissingHistoryNote(model: model) }
            case .loaded(let h):
                let series = HistorySeries(samples: h.samples, range: range, now: now)
                let fullSpan = HistorySeries(samples: h.samples, range: .twoWeeks, now: now)
                if fullSpan.rawCount < 12 || daily.count < 2 {
                    Section {
                        Label(Self.thinDataMessage, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ChargeHistoryChart(series: series, range: range,
                                       limit: model.config.limiterEnabled ? model.config.chargeLimit : nil)
                } header: {
                    HStack {
                        HelpLabel("Charge Level", .chargeHistory)
                        Spacer()
                        Picker("Range", selection: $rangeRaw) {
                            ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .help("Time range for the charge, temperature and power charts")
                    }
                } footer: {
                    SectionCaption(HelpTopic.chargeHistory.what)
                }

                Section {
                    TemperatureHistoryChart(series: series, range: range)
                } header: {
                    HelpLabel("Temperature", .temperatureHistory)
                } footer: {
                    SectionCaption(HelpTopic.temperatureHistory.why)
                }

                Section {
                    PowerHistoryChart(series: series, range: range)
                } header: {
                    HelpLabel("Battery Power", .powerHistory)
                } footer: {
                    SectionCaption(HelpTopic.powerHistory.what)
                }

                Section {
                    LongTermChart(daily: daily, metric: metric)
                } header: {
                    HStack {
                        HelpLabel(metric == .health ? "Health Over Time" : "Capacity Over Time",
                                  metric == .health ? .healthHistory : .capacityHistory)
                        Spacer()
                        Picker("Metric", selection: $metricRaw) {
                            ForEach(LongTermMetric.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .help("Show health in percent or capacity in mAh")
                    }
                } footer: {
                    SectionCaption(metric == .health ? HelpTopic.healthHistory.why : HelpTopic.capacityHistory.why)
                }

                Section {
                    CycleHistoryChart(daily: daily)
                } header: {
                    HelpLabel("Cycle Count", .cycleHistory)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionCaption(HelpTopic.cycleHistory.why)
                        if let loadedAt {
                            Text("Updated \(loadedAt.formatted(date: .omitted, time: .shortened)) · Reloads every minute")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            while autoReload && !Task.isCancelled {
                let h = await Task.detached(priority: .utility) { BatteryHistory.load() }.value
                let next: HistoryLoad = h.map { .loaded($0) } ?? .missing
                if next != load { load = next }
                loadedAt = Date()
                try? await Task.sleep(for: Self.reloadInterval)
            }
        }
    }
}

// MARK: - Summary tiles

struct SummaryTiles: View {
    let summary: HistorySummary

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SummaryTile(symbol: "heart.fill", tint: .pink, title: "Health",
                        value: summary.designCapacity > 0 ? Fmt.percent(summary.healthPercent) : "–",
                        detail: healthDetail, topic: .health)
            Divider().padding(.horizontal, 12)
            SummaryTile(symbol: "battery.100percent", tint: .green, title: "Capacity",
                        value: summary.rawMaxCapacity > 0 ? "\(summary.rawMaxCapacity.formatted()) mAh" : "–",
                        detail: summary.designCapacity > 0 ? "of \(summary.designCapacity.formatted()) mAh design" : "No battery data",
                        topic: .capacity)
            Divider().padding(.horizontal, 12)
            SummaryTile(symbol: "arrow.triangle.2.circlepath", tint: .purple, title: "Cycles",
                        value: "\(summary.cycleCount)",
                        detail: summary.cyclesLast30Days.map { "+\($0) in the last 30 days" } ?? "Rated for about 1000",
                        topic: .cycleCount)
            Divider().padding(.horizontal, 12)
            SummaryTile(symbol: "thermometer.medium", tint: .red, title: "Avg. Temperature",
                        value: summary.avgTempC.map { Fmt.temp($0) } ?? "–",
                        detail: summary.avgTempC == nil ? "No readings yet" : "Last 7 days",
                        topic: .averageTemperature)
        }
        .padding(.vertical, 4)
    }

    private var healthDetail: String {
        if let change = summary.healthChange, let first = summary.firstDay {
            let sign = change > 0.05 ? "+" : (change < -0.05 ? "−" : "±")
            return "\(sign)\(String(format: "%.1f", abs(change))) pts since \(first.formatted(.dateTime.day().month(.abbreviated)))"
        }
        return "Compared to new"
    }
}

struct SummaryTile: View {
    let symbol: String, tint: Color, title: String, value: String, detail: String
    let topic: HelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(tint).imageScale(.small)
                Text(title).foregroundStyle(.secondary)
                InfoButton(topic)
            }
            .font(.caption.weight(.medium))
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(topic)
    }
}

// MARK: - Missing file

struct MissingHistoryNote: View {
    @ObservedObject var model: AppModel
    @AppStorage(SettingsPage.storageKey) private var pageRaw = SettingsPage.general.rawValue

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("No history yet").font(.headline)
            Text(HistoryPage.thinDataMessage)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.reachable == true
                 ? "If this stays empty, update the helper: an older helper does not record history."
                 : "The helper records the history. Install it to start recording.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Open Helper") { pageRaw = SettingsPage.helper.rawValue }
                .controlSize(.small)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .help(.history)
    }
}

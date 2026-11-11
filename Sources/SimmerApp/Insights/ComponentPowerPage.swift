import SwiftUI
import Charts
import SimmerShared

/// Owns the IOReport reader and a short rolling history. Sampling runs on a background thread.
@MainActor
final class ComponentPowerModel: ObservableObject {
    enum State: Equatable { case starting, unavailable, running }
    @Published var state: State = .starting
    @Published var latest: ComponentPowerSample?
    @Published var recent: [ComponentPowerSample] = []

    static let keep = 60
    /// Created once, lazily and thread-safely, on first use (off the main thread).
    private nonisolated static let reader = ComponentPowerReader()

    init(preview: [ComponentPowerSample]? = nil) {
        if let preview { recent = preview; latest = preview.last; state = .running }
    }

    /// Samples once per second (each sample covers one second) until the task is cancelled.
    func run() async {
        let ok = await Task.detached(priority: .utility) { Self.sharedReader() != nil }.value
        guard ok else { state = .unavailable; return }
        while !Task.isCancelled {
            let s = await Task.detached(priority: .utility) { Self.sharedReader()?.sample(seconds: 1) }.value
            guard let s else { state = .unavailable; return }
            latest = s
            recent.append(s)
            if recent.count > Self.keep { recent.removeFirst(recent.count - Self.keep) }
            state = .running
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Starts the last-minute chart over. Sampling keeps running.
    func reset() {
        recent = latest.map { [$0] } ?? []
    }

    private nonisolated static func sharedReader() -> ComponentPowerReader? { reader }
}

enum ChipPart: String, CaseIterable, Identifiable {
    case cpu = "CPU", gpu = "GPU", ane = "Neural Engine", dram = "Memory"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .cpu: return "cpu"; case .gpu: return "cube.transparent"; case .ane: return "brain"; case .dram: return "memorychip" }
    }
    var tint: Color {
        switch self { case .cpu: return .blue; case .gpu: return .purple; case .ane: return .pink; case .dram: return .teal }
    }
    var caption: String {
        switch self {
        case .cpu: return "Processor cores: apps, compiling, everyday work"
        case .gpu: return "Graphics: animations, video, games, external displays"
        case .ane: return "Machine learning: Apple Intelligence, photo and voice features"
        case .dram: return "Unified memory"
        }
    }
    func watts(_ s: ComponentPowerSample) -> Double {
        switch self { case .cpu: return s.cpuW; case .gpu: return s.gpuW; case .ane: return s.aneW; case .dram: return s.dramW }
    }
}

struct ComponentPowerPage: View {
    @ObservedObject var model: AppModel
    @StateObject private var power: ComponentPowerModel
    private let live: Bool

    init(model: AppModel, preview: [ComponentPowerSample]? = nil, unavailable: Bool = false) {
        self.model = model
        let m = ComponentPowerModel(preview: preview)
        if unavailable { m.state = .unavailable }
        _power = StateObject(wrappedValue: m)
        live = preview == nil && !unavailable
    }

    var body: some View {
        Form {
            Section { PageHeader(page: .componentPower) }
            switch power.state {
            case .starting:
                Section {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Measuring…").foregroundStyle(.secondary) }
                }
            case .unavailable:
                Section {
                    EmptyState(symbol: "cpu", title: "Chip power is not available",
                               message: "This Mac does not offer the chip's energy counters to apps. They exist on Apple silicon Macs only. Battery and charger power still work on every Mac.")
                }
            case .running:
                if let s = power.latest {
                    Section {
                        ForEach(ChipPart.allCases) { part in
                            VStack(alignment: .leading, spacing: 2) {
                                ValueBar(label: part.rawValue, value: part.watts(s), maxValue: max(5, peak),
                                         text: EnergyFmt.watts(part.watts(s)), tint: part.tint, symbol: part.symbol)
                                Text(part.caption).font(.caption).foregroundStyle(.secondary).padding(.leading, 22)
                            }
                        }
                        LabeledContent {
                            Text(EnergyFmt.watts(s.totalW)).monospacedDigit().fontWeight(.semibold)
                        } label: { Text("Chip total") }
                        if let sys = model.status?.systemPowerW {
                            LabeledContent {
                                Text(String(format: "%.1f W", sys)).monospacedDigit()
                            } label: { Text("Whole Mac (screen, SSD, ports included)") }
                        }
                    } header: {
                        HStack {
                            HelpLabel("Right Now", .componentPower)
                            Spacer()
                            Text("1-second average · updates every second").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Section {
                        ChipPowerChart(samples: power.recent)
                    } header: {
                        Text("Last Minute")
                    } footer: {
                        SectionCaption("Simmer reads the chip's own energy counters (IOReport), the same source powermetrics uses. No admin rights are needed.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .pageRefresh(busy: power.state == .starting, updated: power.latest?.takenAt,
                     note: "live, every second") { power.reset() }
        .task { if live { await power.run() } }
    }

    private var peak: Double {
        power.recent.map { max($0.cpuW, $0.gpuW, $0.aneW, $0.dramW) }.max() ?? 5
    }
}

struct ChipPowerChart: View {
    let samples: [ComponentPowerSample]

    var body: some View {
        Chart {
            ForEach(ChipPart.allCases) { part in
                ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                    LineMark(x: .value("Time", s.takenAt), y: .value("Watts", part.watts(s)))
                        .foregroundStyle(by: .value("Part", part.rawValue))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartForegroundStyleScale(domain: ChipPart.allCases.map(\.rawValue), range: ChipPart.allCases.map(\.tint))
        .chartYAxis { AxisMarks(position: .leading) { v in
            AxisGridLine(); AxisValueLabel { if let w = v.as(Double.self) { Text("\(Int(w)) W") } }
        } }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute().second()) } }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 160)
        .padding(.vertical, 4)
    }
}

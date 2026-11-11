import SwiftUI
import SimmerShared

// MARK: - Battery sessions

struct SessionsPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var insights: InsightsModel = .shared

    var body: some View {
        let sessions = BatterySession.sessions(from: insights.history?.samples ?? []).filter { $0.hours >= 0.25 }
        let rated = sessions.filter { $0.percentStart > $0.percentEnd }
        let best = rated.min { $0.percentPerHour < $1.percentPerHour }
        let worst = rated.max { $0.percentPerHour < $1.percentPerHour }
        Form {
            Section { PageHeader(page: .sessions) }
            if sessions.isEmpty {
                Section {
                    EmptyState(symbol: "battery.75percent", title: "No battery sessions yet",
                               message: insights.history == nil
                                   ? "The helper records the battery every 5 minutes. Once it has history, every stretch on battery appears here."
                                   : "Unplug your Mac for a while. Each time on battery of 15 minutes or more appears here with its drain rate.")
                }
            } else {
                Section {
                    SessionTiles(sessions: rated, best: best, worst: worst)
                }
                Section {
                    ForEach(sessions) { s in
                        SessionRow(session: s, isBest: s.id == best?.id && rated.count > 1, isWorst: s.id == worst?.id && rated.count > 1)
                    }
                } header: {
                    HelpLabel("On Battery, Last 14 Days", .sessions)
                } footer: {
                    SectionCaption("Drain is the percent lost per hour. Light work such as writing or browsing is often 5–10%/h; video calls and builds drain faster.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { insights.reloadHistory() }
    }
}

struct SessionTiles: View {
    let sessions: [BatterySession]
    let best: BatterySession?
    let worst: BatterySession?

    var body: some View {
        let hours = sessions.reduce(0) { $0 + $1.hours }
        let lost = sessions.reduce(0) { $0 + ($1.percentStart - $1.percentEnd) }
        let avg = hours > 0 ? Double(lost) / hours : 0
        HStack(alignment: .top, spacing: 0) {
            SummaryTile(symbol: "speedometer", tint: .green, title: "Typical Drain",
                        value: avg > 0 ? String(format: "%.1f%%/h", avg) : "–",
                        detail: avg > 0 ? "About \(DurationText.hours(100 / avg)) from full to empty" : "Not enough data",
                        topic: .sessions)
            Divider().padding(.horizontal, 12)
            SummaryTile(symbol: "tortoise.fill", tint: .teal, title: "Best",
                        value: best.map { String(format: "%.1f%%/h", $0.percentPerHour) } ?? "–",
                        detail: best.map { $0.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? "–",
                        topic: .sessions)
            Divider().padding(.horizontal, 12)
            SummaryTile(symbol: "hare.fill", tint: .orange, title: "Worst",
                        value: worst.map { String(format: "%.1f%%/h", $0.percentPerHour) } ?? "–",
                        detail: worst.map { String(format: "%.1f W average", $0.averageWatts) } ?? "–",
                        topic: .sessions)
        }
        .padding(.vertical, 4)
    }
}

struct SessionRow: View {
    let session: BatterySession
    let isBest: Bool
    let isWorst: Bool

    var body: some View {
        let s = session
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(s.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        .font(.callout.weight(.medium))
                    if isBest { tag("Best", .teal) }
                    if isWorst { tag("Worst", .orange) }
                }
                Text("\(DurationText.hours(s.hours)) · \(s.percentStart)% → \(s.percentEnd)%")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f%%/h", s.percentPerHour)).monospacedDigit().font(.callout.weight(.semibold))
                Text(String(format: "%.1f W", s.averageWatts)).monospacedDigit().font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }

    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 1)
            .background(c.opacity(0.2), in: Capsule())
    }
}

// MARK: - Cells & stress

struct BatteryHealthPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var insights: InsightsModel = .shared

    var body: some View {
        let d = insights.details
        Form {
            Section { PageHeader(page: .batteryHealth) }

            Section {
                if let d, d.hoursAtHighCharge != nil || d.dailyMaxSoc != nil {
                    StressMeter(details: d)
                } else {
                    EmptyState(symbol: "gauge.with.dots.needle.0percent", title: "No stress data",
                               message: d == nil ? "Reading the battery…" : "This battery does not report its lifetime charge levels, or Simmer cannot read them yet.")
                }
            } header: {
                HelpLabel("Battery Stress", .stressMeter)
            } footer: {
                SectionCaption("Lithium batteries age fastest when they sit full and warm. A charge limit lowers the time at a high charge from the day you turn it on.")
            }

            Section {
                if let d, !d.cellVoltagesMV.isEmpty {
                    CellBalanceView(details: d)
                } else {
                    EmptyState(symbol: "battery.100percent.bolt", title: "No cell data",
                               message: d == nil ? "Reading the battery…" : "This battery does not report its cell voltages, or Simmer cannot read them yet.")
                }
            } header: {
                HelpLabel("Cell Balance", .cellBalance)
            } footer: {
                SectionCaption("Below 30 mV is normal. 30–80 mV: keep an eye on it. Above 80 mV: one cell ages faster; plan a battery check. The difference is largest when the battery is nearly empty or full.")
            }

            if let d, d.lifetimeMaxTempC != nil || d.totalOperatingHours != nil {
                Section {
                    if let t = d.lifetimeMaxTempC { LabeledContent("Highest temperature", value: Fmt.temp(t)) }
                    if let t = d.lifetimeAvgTempC { LabeledContent("Average temperature", value: Fmt.temp(t)) }
                    if let t = d.lifetimeMinTempC { LabeledContent("Lowest temperature", value: Fmt.temp(t)) }
                    if let h = d.totalOperatingHours { LabeledContent("Operating time", value: "\(Int(h).formatted()) h") }
                    if let m = d.manufactureDate { LabeledContent("Manufactured", value: m.formatted(date: .abbreviated, time: .omitted)) }
                } header: {
                    HelpLabel("Lifetime", .lifetimeTemperature)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { insights.reloadDetails() }
    }
}

struct StressMeter: View {
    let details: BatteryDetails

    /// Share of the operating time spent at a high charge, 0...1, when both numbers are known.
    var share: Double? {
        guard let h = details.hoursAtHighCharge, let total = details.totalOperatingHours, total > 0 else { return nil }
        return min(1, h / total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                if let share {
                    Gauge(value: share) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(Int((share * 100).rounded()))%").font(.system(.title3, design: .rounded).weight(.semibold))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(tint(share))
                    .scaleEffect(1.25)
                    .frame(width: 70, height: 70)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let h = details.hoursAtHighCharge {
                LabeledContent {
                    Text("\(Int(h).formatted()) h" + (details.totalOperatingHours.map { " of \(Int($0).formatted()) h" } ?? ""))
                        .monospacedDigit()
                } label: { HelpLabel("Time at high charge", .timeAtHighCharge) }
            }
            if let lo = details.dailyMinSoc, let hi = details.dailyMaxSoc {
                LabeledContent {
                    HStack(spacing: 8) {
                        RangeBar(low: Double(lo), high: Double(hi)).frame(width: 140, height: 8)
                        Text("\(lo)% – \(hi)%").monospacedDigit()
                    }
                } label: { HelpLabel("Today's charge range", .dailyChargeRange) }
            }
        }
        .padding(.vertical, 4)
    }

    private func tint(_ s: Double) -> Color { s < 0.25 ? .green : (s < 0.5 ? .orange : .red) }

    private var title: String {
        guard let s = share else { return details.hoursAtHighCharge == nil ? "Daily charge pattern" : "Battery stress" }
        if s < 0.25 { return "Low stress" }
        if s < 0.5 { return "Moderate stress" }
        return "High stress"
    }

    private var message: String {
        guard let s = share else {
            if details.hoursAtHighCharge == nil {
                return "This battery does not report its lifetime time at a high charge. Its charge range for today is below; a range that stays below 85% is gentle."
            }
            return "The battery reports its time at a high charge, but not its total operating time, so Simmer cannot compare them."
        }
        let pct = Int((s * 100).rounded())
        if s < 0.25 { return "The battery spent \(pct)% of its life at a high charge. That is gentle. Keep it up." }
        if s < 0.5 { return "The battery spent \(pct)% of its life at a high charge. A limit of 80% or lower helps from now on." }
        return "The battery spent \(pct)% of its life at a high charge. That ages it faster. Keep the limit on and try desk mode."
    }
}

/// A 0–100 track with the low–high span filled.
struct RangeBar: View {
    let low: Double, high: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.green.gradient)
                    .frame(width: max(4, g.size.width * (high - low) / 100))
                    .offset(x: g.size.width * low / 100)
            }
        }
    }
}

struct CellBalanceView: View {
    let details: BatteryDetails

    var body: some View {
        let v = details.cellVoltagesMV
        let lo = Double((v.min() ?? 0) - 20), hi = Double((v.max() ?? 0) + 5)
        VStack(alignment: .leading, spacing: 10) {
            VerdictRow(symbol: symbol, tint: tint, title: title,
                       message: "The cells differ by \(details.cellImbalanceMV) mV.")
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Array(v.enumerated()), id: \.offset) { i, mv in
                    VStack(spacing: 4) {
                        Text(String(format: "%.3f V", Double(mv) / 1000)).font(.caption.monospacedDigit())
                        GeometryReader { g in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill((mv == v.min() && details.cellBalance != .good ? Color.orange : Color.green).gradient)
                                    .frame(height: max(6, g.size.height * (Double(mv) - lo) / max(1, hi - lo)))
                            }
                        }
                        .frame(width: 34, height: 70)
                        Text("Cell \(i + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.leading, 38)
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch details.cellBalance {
        case .good: return "Cells are well balanced"
        case .watch: return "Cells are a little out of balance — keep an eye on it"
        case .poor: return "Cells are out of balance — plan a battery check"
        }
    }
    private var tint: Color {
        switch details.cellBalance { case .good: return .green; case .watch: return .orange; case .poor: return .red }
    }
    private var symbol: String {
        switch details.cellBalance {
        case .good: return "checkmark.seal.fill"; case .watch: return "exclamationmark.circle.fill"; case .poor: return "exclamationmark.triangle.fill"
        }
    }
}

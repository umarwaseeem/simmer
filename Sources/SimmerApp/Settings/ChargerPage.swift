import SwiftUI
import SimmerShared

struct ChargerPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var insights: InsightsModel = .shared
    @State private var extras = ChargerDetails()

    var body: some View {
        let b = model.battery
        let r = insights.chargerReport(status: model.status, battery: b)
        Form {
            Section { PageHeader(page: .charger) }

            if !b.externalConnected {
                Section {
                    EmptyState(symbol: "powerplug", title: "No charger connected",
                               message: "Connect your charger to see what it offers and whether it is strong enough for your Mac.")
                }
            } else {
                Section {
                    VerdictRow(symbol: r.rating.symbol, tint: r.rating.tint,
                               title: r.headlineOrFallback(battery: b),
                               message: r.rating == .none ? "Simmer could not rate this charger yet." : "Rating: \(r.rating.title)")
                    ForEach(r.details, id: \.self) { line in
                        Text(line).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 38)
                    }
                } header: {
                    HelpLabel("Verdict", .charger)
                }

                Section("Charger") {
                    LabeledContent("Name", value: name(r, b))
                    if !extras.manufacturer.isEmpty { LabeledContent("Maker", value: extras.manufacturer) }
                    LabeledContent("Offers", value: watts(r.negotiatedWatts > 0 ? r.negotiatedWatts : b.adapterWatts))
                    LabeledContent("Negotiated", value: voltsAmps(r.voltageV > 0 ? r.voltageV : b.adapterVoltageV,
                                                                   r.currentA > 0 ? r.currentA : b.adapterCurrentA))
                    LabeledContent("Type", value: r.isUSBPD || !extras.options.isEmpty ? "USB Power Delivery" : (extras.isWireless ? "Wireless" : (extras.description.isEmpty ? "–" : extras.description)))
                    if !extras.firmware.isEmpty { LabeledContent("Firmware", value: extras.firmware) }
                }

                if !extras.options.isEmpty {
                    Section {
                        ForEach(extras.options) { o in
                            let active = o.index == extras.activeIndex
                            HStack {
                                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(active ? Color.green : Color.secondary)
                                Text(String(format: "%.0f V", o.voltageV)).monospacedDigit().frame(width: 50, alignment: .leading)
                                Text(String(format: "up to %.2f A", o.currentA)).monospacedDigit().foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.0f W", o.watts)).monospacedDigit().fontWeight(active ? .semibold : .regular)
                                if active { Text("In use").font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(.green.opacity(0.2), in: Capsule()) }
                            }
                        }
                    } header: {
                        HelpLabel("Voltage Options", .pdOptions)
                    } footer: {
                        SectionCaption("The charger announces these levels. Your Mac picks the best one that the cable allows.")
                    }
                }

                Section("Your Mac") {
                    LabeledContent("Using now", value: Fmt.watts(model.status?.systemPowerW))
                    LabeledContent("Coming in now", value: Fmt.watts(model.status?.adapterPowerW))
                    LabeledContent {
                        Text(insights.recentPeakSystemW.map { String(format: "%.1f W", $0) } ?? "No history yet")
                    } label: { HelpLabel("Peak use, last 7 days", .peakUse) }
                }
            }

            Section {
                ForEach(tips(r), id: \.self) { t in
                    Label { Text(t).fixedSize(horizontal: false, vertical: true) } icon: {
                        Image(systemName: "lightbulb").foregroundStyle(.yellow)
                    }
                    .font(.callout)
                }
            } header: {
                Text("Tips")
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                extras = await Task.detached(priority: .utility) { ChargerDetails.read() }.value
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func name(_ r: ChargerReport, _ b: BatterySnapshot) -> String {
        if !r.adapterName.isEmpty { return r.adapterName }
        return b.adapterName.isEmpty ? "Power adapter" : b.adapterName
    }
    private func watts(_ w: Int) -> String { w > 0 ? "\(w) W" : "–" }
    private func voltsAmps(_ v: Double, _ a: Double) -> String {
        v > 0 ? String(format: "%.1f V × %.2f A", v, a) : "–"
    }

    private func tips(_ r: ChargerReport) -> [String] {
        switch r.rating {
        case .insufficient:
            return ["Use the charger that came with your Mac, or one with more watts.",
                    "Connect the charger directly. Hubs, docks and monitors often pass on less power.",
                    "Check the cable: many USB-C cables carry only 60 W. A 100 W or 240 W cable fixes that."]
        case .limited:
            return ["The battery can drain a little during heavy work, for example exports or games. That is safe, but it charges slowly.",
                    "A cable rated for 100 W or more, connected directly to the Mac, can raise the limit."]
        case .excellent, .good:
            return ["Your charger is a good match. Nothing to do.",
                    "Simmer's charge limit works with any charger. The charger only decides how fast the battery fills."]
        case .none:
            return ["Apple recommends a charger with at least the watts printed on your Mac's original adapter.",
                    "USB-C chargers from other brands work well when they support USB Power Delivery (USB-PD)."]
        }
    }
}

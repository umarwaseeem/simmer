import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SimmerShared

/// Everything printed on the passport, captured once so the preview and the PDF match.
struct PassportData: Equatable {
    var model: MacModel
    var battery: BatterySnapshot
    var details: BatteryDetails?
    var firstRecord: DailyBatteryRecord?
    var generated: Date
    var appVersion: String

    var healthPercent: Double { battery.healthPercent }
    var serial: String { !battery.serial.isEmpty ? battery.serial : (details?.serial ?? "") }

    var healthVerdict: (String, Color) {
        let h = healthPercent
        if battery.designCapacity == 0 { return ("Unknown", .secondary) }
        if h >= 90 { return ("Excellent", .green) }
        if h >= 80 { return ("Good", .teal) }
        if h >= 70 { return ("Fair", .orange) }
        return ("Service recommended", .red)
    }
}

enum PaperSize: String, CaseIterable, Identifiable {
    case a4 = "A4", letter = "US Letter"
    var id: String { rawValue }
    /// PostScript points (1/72 inch).
    var size: CGSize { self == .a4 ? CGSize(width: 595, height: 842) : CGSize(width: 612, height: 792) }
}

struct PassportPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var insights: InsightsModel = .shared
    @AppStorage("passportPaper") private var paperRaw = Locale.current.region?.identifier == "US" ? PaperSize.letter.rawValue : PaperSize.a4.rawValue
    @State private var result: (text: String, isError: Bool)?

    private var paper: PaperSize { PaperSize(rawValue: paperRaw) ?? .a4 }

    private var data: PassportData {
        PassportData(model: .current, battery: model.battery, details: insights.details,
                     firstRecord: insights.history?.daily.min { $0.day < $1.day }, generated: Date(), appVersion: AppInfo.version)
    }

    var body: some View {
        Form {
            Section { PageHeader(page: .passport) }
            Section {
                HStack {
                    Picker("Paper", selection: $paperRaw) {
                        ForEach(PaperSize.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented).fixedSize()
                    Spacer()
                    Button("Export PDF…") { export() }
                        .disabled(!model.battery.present)
                        .help(.passport)
                }
                if let result {
                    Label(result.text, systemImage: result.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(result.isError ? Color.red : Color.green)
                }
            } header: {
                HelpLabel("Export", .passport)
            } footer: {
                SectionCaption("The PDF contains the battery serial number and your Mac's model. It contains no personal data.")
            }
            Section("Preview") {
                let d = data
                PassportSheet(data: d)
                    .frame(width: paper.size.width, height: paper.size.height)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
                    .scaleEffect(0.82, anchor: .top)
                    .frame(width: paper.size.width * 0.82, height: paper.size.height * 0.82, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .onAppear { insights.reloadDetails(); insights.reloadHistory() }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Battery Passport \(Date().formatted(.iso8601.year().month().day())).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PassportPDF.write(data: data, paper: paper, to: url)
            result = ("Saved \(url.lastPathComponent).", false)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            result = ("Could not save the PDF: \(error.localizedDescription)", true)
        }
    }
}

enum PassportPDF {
    struct Failure: LocalizedError { var errorDescription: String? { "The PDF context could not be created." } }

    /// Renders the passport as vector PDF (text stays selectable).
    @MainActor
    static func write(data: PassportData, paper: PaperSize, to url: URL) throws {
        let view = PassportSheet(data: data)
            .frame(width: paper.size.width, height: paper.size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(paper.size)
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle: "Battery Passport",
                                                                    kCGPDFContextCreator: "Simmer \(data.appVersion)"] as CFDictionary) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        if !ok { throw Failure() }
    }
}

/// One printable page. Fixed light colors, because paper is white.
struct PassportSheet: View {
    let data: PassportData

    private let ink = Color(white: 0.1)
    private let muted = Color(white: 0.42)
    private let rule = Color(white: 0.86)

    var body: some View {
        let b = data.battery
        let d = data.details
        VStack(alignment: .leading, spacing: 0) {
            // Header band
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "battery.100percent.bolt").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery Passport").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    Text(data.model.displayName).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Generated").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    Text(data.generated.formatted(date: .long, time: .shortened)).font(.system(size: 11)).foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 36).padding(.vertical, 24)
            .background(LinearGradient(colors: [Color(red: 0.10, green: 0.55, blue: 0.45), Color(red: 0.08, green: 0.38, blue: 0.55)],
                                       startPoint: .leading, endPoint: .trailing))

            VStack(alignment: .leading, spacing: 22) {
                // Health hero
                HStack(alignment: .center, spacing: 22) {
                    ZStack {
                        Circle().stroke(rule, lineWidth: 10)
                        Circle().trim(from: 0, to: min(1, data.healthPercent / 100))
                            .stroke(data.healthVerdict.1, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(b.designCapacity > 0 ? String(format: "%.0f%%", data.healthPercent) : "–")
                                .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(ink)
                            Text("health").font(.system(size: 10)).foregroundStyle(muted)
                        }
                    }
                    .frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(data.healthVerdict.0).font(.system(size: 20, weight: .semibold)).foregroundStyle(data.healthVerdict.1)
                        Text(b.designCapacity > 0
                             ? "The battery holds \(b.rawMaxCapacity.formatted()) mAh of its original \(b.designCapacity.formatted()) mAh after \(b.cycleCount) charge cycles."
                             : "No battery information was available.")
                            .font(.system(size: 12)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                        Text("Apple rates MacBook batteries to keep 80% of their capacity for about 1000 cycles.")
                            .font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    }
                }

                grid([
                    ("Model", data.model.displayName),
                    ("Model identifier", data.model.identifier),
                    ("Battery serial", data.serial.isEmpty ? "Not reported" : data.serial),
                    ("Manufactured", d?.manufactureDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Not reported"),
                    ("Full charge capacity", b.rawMaxCapacity > 0 ? "\(b.rawMaxCapacity.formatted()) mAh" : "–"),
                    ("Design capacity", b.designCapacity > 0 ? "\(b.designCapacity.formatted()) mAh" : "–"),
                    ("Cycle count", "\(b.cycleCount)"),
                    ("Cell balance", cellText(d)),
                    ("Highest temperature", d?.lifetimeMaxTempC.map { String(format: "%.0f °C", $0) } ?? "Not reported"),
                    ("Battery temperature now", String(format: "%.1f °C", b.temperatureC)),
                ])

                if let v = d?.cellVoltagesMV, !v.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CELL VOLTAGES").font(.system(size: 9, weight: .bold)).foregroundStyle(muted)
                        HStack(spacing: 18) {
                            ForEach(Array(v.enumerated()), id: \.offset) { i, mv in
                                VStack(spacing: 2) {
                                    Text(String(format: "%.3f V", Double(mv) / 1000)).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(ink)
                                    Text("Cell \(i + 1)").font(.system(size: 9)).foregroundStyle(muted)
                                }
                            }
                        }
                    }
                }

                if let first = data.firstRecord, Date().timeIntervalSince(first.date) > 7 * 86_400 {
                    Text("Simmer has tracked this battery since \(first.date.formatted(date: .abbreviated, time: .omitted)), when its health was \(String(format: "%.1f%%", first.healthPercent)) at \(first.cycleCount) cycles.")
                        .font(.system(size: 11)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 4) {
                    Rectangle().fill(rule).frame(height: 1)
                    Text("Values are read from the battery's own controller (AppleSmartBattery) at the time shown above. Health = full charge capacity ÷ design capacity.")
                        .font(.system(size: 8.5)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    Text("Generated by Simmer \(data.appVersion) · open-source battery charge limiter for macOS")
                        .font(.system(size: 8.5, weight: .medium)).foregroundStyle(muted)
                }
            }
            .padding(.horizontal, 36).padding(.top, 26).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }

    private func cellText(_ d: BatteryDetails?) -> String {
        guard let d, !d.cellVoltagesMV.isEmpty else { return "Not reported" }
        switch d.cellBalance {
        case .good: return "Good (\(d.cellImbalanceMV) mV)"
        case .watch: return "Watch (\(d.cellImbalanceMV) mV)"
        case .poor: return "Poor (\(d.cellImbalanceMV) mV)"
        }
    }

    private func grid(_ rows: [(String, String)]) -> some View {
        let pairs = stride(from: 0, to: rows.count, by: 2).map { Array(rows[$0..<min($0 + 2, rows.count)]) }
        return VStack(spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .top, spacing: 24) {
                    ForEach(pair, id: \.0) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.0.uppercased()).font(.system(size: 8.5, weight: .bold)).foregroundStyle(muted)
                            Text(r.1).font(.system(size: 13, weight: .medium)).foregroundStyle(ink).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if pair.count == 1 { Spacer().frame(maxWidth: .infinity) }
                }
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 1) }
            }
        }
    }
}

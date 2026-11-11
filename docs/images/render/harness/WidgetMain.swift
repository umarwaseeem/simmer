import SwiftUI
import AppKit
import SimmerShared
import WidgetKit

// Renders Simmer's desktop widgets with sample data into PNGs (2x, transparent around the widget).
// usage: WidgetShots <outdir>
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "out"

struct WidgetFrame<Content: View>: View {
    var size: CGSize
    var tint: Color
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(SimmerBackground(tint: tint))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 0.5))
    }
}

let sizes: [WidgetFamily: CGSize] = [
    .systemSmall: CGSize(width: 170, height: 170),
    .systemMedium: CGSize(width: 364, height: 170),
    .systemLarge: CGSize(width: 364, height: 382),
]

@MainActor func write(_ view: some View, _ name: String, scheme: ColorScheme) {
    let r = ImageRenderer(content: view.environment(\.colorScheme, scheme))
    r.scale = 2
    r.isOpaque = false
    guard let cg = r.cgImage else { print("render failed \(name)"); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    let path = "\(outDir)/\(name)-\(scheme == .dark ? "dark" : "light").png"
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote", (path as NSString).lastPathComponent, cg.width, "x", cg.height)
}

var charging = SimmerEntry.sample
charging.status!.state = .charging
charging.status!.adapterPowerW = 68
charging.status!.systemPowerW = 14
charging.battery.percent = 62
charging.battery.amperageA = 4.4
charging.battery.isCharging = true
charging.status!.battery = charging.battery

MainActor.assumeIsolated {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let e = SimmerEntry.sample
    func framed(_ f: WidgetFamily, _ tint: Color, _ v: some View) -> some View {
        WidgetFrame(size: sizes[f]!, tint: tint) { v }
    }
    for scheme in [ColorScheme.light, .dark] {
        write(framed(.systemSmall, e.style.color, SimmerWidgetView(entry: e, options: BatteryOptions(), family: .systemSmall)), "widget-battery-small", scheme: scheme)
        write(framed(.systemMedium, e.style.color, SimmerWidgetView(entry: e, options: BatteryOptions(), family: .systemMedium)), "widget-battery-medium", scheme: scheme)
        write(framed(.systemSmall, charging.style.color, SimmerWidgetView(entry: charging, options: BatteryOptions(), family: .systemSmall)), "widget-charging-small", scheme: scheme)
        write(framed(.systemMedium, .green, PowerFlowWidgetView(entry: e, family: .systemMedium)), "widget-power-medium", scheme: scheme)
        write(framed(.systemSmall, .green, PowerFlowWidgetView(entry: e, family: .systemSmall)), "widget-power-small", scheme: scheme)
        let hc = HistorySeries.make(e, metric: .charge, range: .day).color
        write(framed(.systemMedium, hc, HistoryWidgetView(entry: e, metric: .charge, range: .day, family: .systemMedium)), "widget-history-medium", scheme: scheme)
        write(framed(.systemLarge, hc, HistoryWidgetView(entry: e, metric: .charge, range: .day, family: .systemLarge)), "widget-history-large", scheme: scheme)
        write(framed(.systemMedium, .orange, TopAppsWidgetView(entry: e, count: 5, family: .systemMedium)), "widget-apps-medium", scheme: scheme)
        write(framed(.systemSmall, e.style.color, ControlsWidgetView(entry: e, limits: [60, 80, 100], family: .systemSmall)), "widget-controls-small", scheme: scheme)
        write(framed(.systemMedium, e.style.color, ControlsWidgetView(entry: e, limits: [60, 80, 100], family: .systemMedium)), "widget-controls-medium", scheme: scheme)
        write(framed(.systemSmall, ChargerPresentation(e).color, ChargerHealthWidgetView(entry: e, family: .systemSmall)), "widget-charger-small", scheme: scheme)
    }
}

// Composes docs/images/hero.png and the README screenshots from the raw renders.
// usage: swift compose.swift <raw-dir> <docs/images> <AppIcon.icns>
import SwiftUI
import AppKit

let raw = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = URL(fileURLWithPath: CommandLine.arguments[2])
let iconPath = CommandLine.arguments[3]
let shots = dest.appendingPathComponent("screenshots")
try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)

func img(_ name: String) -> NSImage {
    guard let i = NSImage(contentsOf: raw.appendingPathComponent(name + ".png")) else { fatalError("missing \(name)") }
    // Raw renders are 2x: show them at point size.
    if let rep = i.representations.first { i.size = NSSize(width: rep.pixelsWide / 2, height: rep.pixelsHigh / 2) }
    return i
}

let plum = Color(red: 0.16, green: 0.10, blue: 0.24)
let wine = Color(red: 0.47, green: 0.16, blue: 0.22)
let ember = Color(red: 0.93, green: 0.42, blue: 0.20)
let cream = Color(red: 1, green: 0.97, blue: 0.93)

struct Shot: View {
    let image: NSImage
    var scale: CGFloat = 1
    var radius: CGFloat = 16
    var body: some View {
        Image(nsImage: image).resizable().interpolation(.high)
            .frame(width: image.size.width * scale, height: image.size.height * scale)
            .shadow(color: .black.opacity(0.45), radius: 30 * scale, y: 18 * scale)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

struct Pill: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(cream)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(.white.opacity(0.12)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }
}

struct Hero: View {
    let icon: NSImage
    let panel: NSImage
    let window: NSImage
    let widgetSmall: NSImage
    let widgetMedium: NSImage
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(stops: [.init(color: plum, location: 0), .init(color: wine, location: 0.55), .init(color: ember, location: 1)],
                           startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 1, y: 1.1))
            RadialGradient(colors: [Color(red: 1, green: 0.62, blue: 0.25).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.72, y: 1.05), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [.white.opacity(0.10), .clear], center: UnitPoint(x: 0.1, y: 0), startRadius: 0, endRadius: 600)
            // Product shots, bleeding off the bottom edge.
            Shot(image: window, scale: 0.6).offset(x: 742, y: 96)
            Shot(image: panel, scale: 0.8).offset(x: 560, y: 64)
            Shot(image: widgetSmall, scale: 0.82).offset(x: 1036, y: 404)
            // Copy.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 104, height: 104)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                    Text("Simmer").font(.system(size: 84, weight: .bold, design: .rounded)).foregroundStyle(cream)
                        .tracking(-1.5)
                }
                .padding(.bottom, 26)
                Text("macOS battery\nmanager")
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .foregroundStyle(cream)
                    .lineSpacing(2)
                    .padding(.bottom, 16)
                Text("Free and open source. Charge limits, battery health\nand power insights from your menu bar.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(cream.opacity(0.78))
                    .lineSpacing(3)
                    .padding(.bottom, 26)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Pill(symbol: "bolt.badge.checkmark", text: "Limit 20–100%")
                        Pill(symbol: "sailboat.fill", text: "Sailing")
                        Pill(symbol: "thermometer.medium", text: "Heat guard")
                    }
                    HStack(spacing: 10) {
                        Pill(symbol: "chart.xyaxis.line", text: "Insights")
                        Pill(symbol: "square.grid.2x2.fill", text: "Widgets")
                        Pill(symbol: "terminal.fill", text: "CLI & Shortcuts")
                    }
                }
            }
            .offset(x: 70, y: 124)
        }
        .frame(width: 1200, height: 600)
        .clipped()
    }
}

/// A screenshot on a transparent canvas.
struct Framed: View {
    let image: NSImage
    var body: some View {
        // No drop shadow: soft shadows do not survive the 256-color palette that keeps the repo small.
        Image(nsImage: image).resizable().interpolation(.high)
            .frame(width: image.size.width, height: image.size.height)
    }
}

/// Several widgets on a desktop-like gradient.
struct WidgetBoard: View {
    let dark: Bool
    let rows: [[NSImage]]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 20) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        Image(nsImage: rows[r][c]).resizable()
                            .frame(width: rows[r][c].size.width, height: rows[r][c].size.height)
                            .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
                    }
                }
            }
        }
        .padding(36)
        .background(
            LinearGradient(colors: dark ? [plum, wine.opacity(0.9)] : [Color(red: 1, green: 0.90, blue: 0.82), Color(red: 0.98, green: 0.76, blue: 0.64)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

@MainActor func save(_ view: some View, _ url: URL) {
    let r = ImageRenderer(content: view)
    r.scale = 2
    r.isOpaque = false
    guard let cg = r.cgImage else { fatalError("render failed \(url.lastPathComponent)") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote", url.path.replacingOccurrences(of: dest.deletingLastPathComponent().deletingLastPathComponent().path + "/", with: ""),
          cg.width, "x", cg.height)
}

MainActor.assumeIsolated {
    guard let icon = NSImage(contentsOfFile: iconPath) else { fatalError("no icon") }
    save(Hero(icon: icon, panel: img("panel-dark"), window: img("settings-history-dark"),
              widgetSmall: img("widget-battery-small-dark"), widgetMedium: img("widget-power-medium-dark")),
         dest.appendingPathComponent("hero.png"))

    for theme in ["light", "dark"] {
        save(Framed(image: img("panel-\(theme)")), shots.appendingPathComponent("panel-\(theme).png"))
        for page in ["charging", "smartCharging", "led", "history", "energy", "batteryHealth", "sleepDrain", "conflicts", "schedule"] {
            save(Framed(image: img("settings-\(page)-\(theme)")), shots.appendingPathComponent("settings-\(page)-\(theme).png"))
        }
        save(WidgetBoard(dark: theme == "dark", rows: [
            [img("widget-battery-small-\(theme)"), img("widget-power-medium-\(theme)"), img("widget-controls-small-\(theme)")],
            [img("widget-history-medium-\(theme)"), img("widget-apps-medium-\(theme)")],
        ]), shots.appendingPathComponent("widgets-\(theme).png"))
    }
}

import SwiftUI
import AppKit
import WidgetKit
import SimmerShared

// MARK: - Top Energy Apps widget (energy.json from simmerd).

/// App icons for energy rows. NSWorkspace gives the icon when the sandbox can read the bundle
/// (the widget has read access to /Applications and /System/Applications); otherwise nil and the row
/// shows an SF Symbol. Icons are downscaled so the timeline stays small.
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func icon(for path: String?, size: CGFloat = 32) -> NSImage? {
        guard let raw = path, !raw.isEmpty, FileManager.default.fileExists(atPath: raw) else { return nil }
        // /Applications/Safari.app is a symlink into the system cryptex: use the target, or the icon gets an alias badge.
        let path = URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
        lock.lock(); defer { lock.unlock() }
        if let i = cache[path] { return i }
        let src = NSWorkspace.shared.icon(forFile: path)
        let px = Int(size * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        src.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        cache[path] = img
        return img
    }
}

struct AppIconView: View {
    var entry: EnergyEntry
    var size: CGFloat
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        if let img = AppIconCache.icon(for: entry.bundlePath) {
            Image(nsImage: img)
                .resizable()
                .accentDesaturated()
                .frame(width: size, height: size)
        } else {
            Image(systemName: entry.isApp ? "app.fill" : "gearshape.fill")
                .font(.system(size: size * 0.55, weight: .medium))
                .foregroundStyle(mode == .fullColor ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(.primary))
                .frame(width: size, height: size)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        }
    }
}

extension Image {
    /// Accented (tinted) widgets: show icons desaturated instead of as solid tint shapes (macOS 15+).
    @ViewBuilder func accentDesaturated() -> some View {
        if #available(macOS 15.0, *) { self.widgetAccentedRenderingMode(.desaturated) } else { self }
    }
}

private struct EnergyRow: View {
    var entry: EnergyEntry
    var maxW: Double
    var iconSize: CGFloat
    var showBar: Bool
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        HStack(spacing: 7) {
            AppIconView(entry: entry, size: iconSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 2)
                    Text(WFmt.watts(entry.watts1m))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                if showBar {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.primary.opacity(0.08))
                            Capsule()
                                .fill(mode == .fullColor ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(.primary))
                                .frame(width: max(3, geo.size.width * CGFloat(min(1, entry.watts1m / max(maxW, 0.01)))))
                                .widgetAccentable()
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}

struct TopAppsWidgetView: View {
    var entry: SimmerEntry
    var count: Int
    var family: WidgetFamily

    var body: some View {
        Group {
            if let report = entry.freshEnergy, !report.entries.isEmpty {
                content(report)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(symbol: "flame.fill", title: "Energy Use", tint: .orange)
                    if entry.helperRunning {
                        Placeholder(symbol: "clock", text: "Collecting data")
                    } else if family == .systemSmall {
                        HelperOffNotice(compact: true, message: "Energy data needs the Simmer helper.")
                    } else {
                        HelperOffNotice(message: "The Simmer helper measures energy use per app. Open Simmer to start it.")
                    }
                }
            }
        }
        .simmerWidgetChrome(tint: .orange)
    }

    @ViewBuilder private func content(_ r: EnergyReport) -> some View {
        let sorted = r.entries.sorted { $0.watts1m > $1.watts1m }
        let maxW = sorted.first?.watts1m ?? 1
        let total = "\(WFmt.watts(r.totalWatts1m)) total"
        switch family {
        case .systemSmall:
            let rows = Array(sorted.prefix(min(count, 3)))
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(symbol: "flame.fill", title: "Energy", tint: .orange)
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(rows) { EnergyRow(entry: $0, maxW: maxW, iconSize: 20, showBar: true) }
                }
                Spacer(minLength: 0)
            }
        case .systemLarge, .systemExtraLarge:
            let rows = Array(sorted.prefix(count))
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(symbol: "flame.fill", title: "Energy Use · Last Minute", tint: .orange, trailing: total)
                // Rows share the height evenly, so 3 or 5 apps do not leave a gap at the bottom.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) {
                        EnergyRow(entry: $0, maxW: maxW, iconSize: 26, showBar: true)
                            .frame(maxHeight: count > 5 ? .infinity : 58)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                Text("CPU and GPU share per app, estimated by Simmer.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        default:
            let rows = Array(sorted.prefix(count))
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(symbol: "flame.fill", title: "Energy Use · Last Minute", tint: .orange, trailing: total)
                if rows.count <= 3 {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(rows) { EnergyRow(entry: $0, maxW: maxW, iconSize: 22, showBar: true) }
                    }
                } else {
                    // Two columns, filled top to bottom.
                    let perColumn = (rows.count + 1) / 2
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(0..<2, id: \.self) { c in
                            VStack(alignment: .leading, spacing: rows.count > 6 ? 6 : 10) {
                                ForEach(Array(rows.dropFirst(c * perColumn).prefix(perColumn))) {
                                    EnergyRow(entry: $0, maxW: maxW, iconSize: rows.count > 6 ? 18 : 22, showBar: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

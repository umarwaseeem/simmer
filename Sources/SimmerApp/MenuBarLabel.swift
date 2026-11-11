import SwiftUI
import AppKit
import SimmerShared

/// Menu bar item. Rendered to a template NSImage so that several symbols and texts survive the
/// MenuBarExtra label flattening and adapt to light / dark menu bars.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(nsImage: rendered)
            .accessibilityLabel("Simmer \(model.battery.percent)%")
    }

    private var rendered: NSImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = renderer.nsImage ?? NSImage(systemSymbolName: "battery.100percent", accessibilityDescription: nil) ?? NSImage()
        img.isTemplate = true
        return img
    }

    private var content: some View {
        let b = model.battery
        let prefs = model.prefs
        return HStack(spacing: 3) {
            if prefs.useBatteryIcon {
                if let g = MenuBarLabel.glyph(model.status, battery: b, reachable: model.reachable) {
                    Image(systemName: g).font(.system(size: 9, weight: .bold))
                }
                Image(systemName: MenuBarLabel.batterySymbol(b.percent))
                    .font(.system(size: 14))
            } else {
                SimmerJarGlyph(fraction: Double(b.percent) / 100, steaming: MenuBarLabel.isCharging(model.status, battery: b),
                               alert: model.reachable == false)
                    .frame(width: 11, height: 18)
            }
            if prefs.showPercent {
                Text(prefs.showHardwarePercent ? String(format: "%.0f%%", b.hardwarePercent) : "\(b.percent)%")
            }
            if prefs.showTemperature, let s = model.status {
                Text(String(format: "%.0f°", s.temperatureC))
            }
            if prefs.showSystemWatts, let w = model.status?.systemPowerW {
                Text(String(format: "%.0fW", w))
            }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(.black)
        .padding(.vertical, 1)
        .fixedSize()
    }

    static func isCharging(_ s: SimmerStatus?, battery b: BatterySnapshot) -> Bool {
        guard let s else { return b.isCharging }
        switch s.state {
        case .charging, .topUp: return true
        case .calibration: return !s.adapterDisabled && s.battery.isCharging
        case .limiterOff: return s.battery.isCharging
        default: return false
        }
    }

    static func batterySymbol(_ pct: Int) -> String {
        switch pct {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// bolt = charging, pause = holding at limit, arrow down = discharging.
    static func glyph(_ s: SimmerStatus?, battery b: BatterySnapshot, reachable: Bool?) -> String? {
        guard let s else {
            if reachable == false { return "exclamationmark" }
            return b.isCharging ? "bolt.fill" : nil
        }
        switch s.state {
        case .charging, .topUp: return "bolt.fill"
        case .limitReached, .sailing: return "pause.fill"
        case .heatProtection: return "thermometer.high"
        case .discharging: return "arrow.down"
        case .calibration:
            if s.adapterDisabled { return "arrow.down" }
            return s.battery.isCharging ? "bolt.fill" : "pause.fill"
        case .limiterOff: return s.battery.isCharging ? "bolt.fill" : nil
        case .notPluggedIn: return nil
        case .unsupported: return "exclamationmark"
        }
    }
}

/// The Simmer icon as a monochrome menu bar glyph: a jar that fills with the charge, with steam while charging.
struct SimmerJarGlyph: View {
    var fraction: Double
    var steaming: Bool
    var alert: Bool = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let line = max(1.2, w * 0.12)
            let steamH = h * 0.22
            let cap = CGRect(x: w * 0.30, y: steamH + line * 0.3, width: w * 0.40, height: h * 0.065)
            let body = CGRect(x: line / 2, y: cap.maxY + h * 0.025, width: w - line, height: h - cap.maxY - h * 0.025 - line / 2)
            ctx.fill(Path(roundedRect: cap, cornerRadius: cap.height / 2), with: .color(.black))
            ctx.stroke(Path(roundedRect: body, cornerRadius: w * 0.24), with: .color(.black), lineWidth: line)
            let inner = body.insetBy(dx: line * 1.15, dy: line * 1.15)
            let f = min(1, max(0.06, fraction))
            let level = CGRect(x: inner.minX, y: inner.maxY - inner.height * f, width: inner.width, height: inner.height * f)
            ctx.fill(Path(roundedRect: level, cornerRadius: w * 0.08), with: .color(.black))
            if alert {
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.38, y: 0, width: w * 0.24, height: w * 0.24)), with: .color(.black))
            } else if steaming {
                for (i, x) in [w * 0.3, w * 0.5, w * 0.7].enumerated() {
                    var p = Path()
                    let top: CGFloat = i == 1 ? 0 : steamH * 0.25
                    p.move(to: CGPoint(x: x, y: steamH))
                    p.addCurve(to: CGPoint(x: x, y: top), control1: CGPoint(x: x + w * 0.13, y: steamH * 0.65),
                               control2: CGPoint(x: x - w * 0.13, y: steamH * 0.35 + top / 2))
                    ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: line * 0.8, lineCap: .round))
                }
            }
        }
    }
}

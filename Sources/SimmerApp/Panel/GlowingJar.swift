import SwiftUI
import AppKit
import SimmerShared

/// What the battery jar shows: the glow colour and which effects run.
enum JarMood: Equatable {
    case charging, holding, onBattery, discharging, heat, idle

    init(status s: SimmerStatus?, battery b: BatterySnapshot) {
        guard let s else {
            self = b.externalConnected ? (b.isCharging ? .charging : .holding) : .onBattery
            return
        }
        switch s.state {
        case .charging, .topUp: self = .charging
        case .limitReached, .sailing: self = .holding
        case .notPluggedIn: self = .onBattery
        case .discharging: self = .discharging
        case .heatProtection: self = .heat
        case .calibration:
            self = s.adapterDisabled ? .discharging : (s.battery.isCharging ? .charging : .holding)
        case .limiterOff:
            self = s.battery.isCharging ? .charging : (s.battery.externalConnected ? .holding : .onBattery)
        case .unsupported: self = .idle
        }
    }

    /// Frames per second. Each frame costs a SwiftUI update of the panel, so calm states use fewer frames:
    /// their motion is slow enough to look smooth at 12–15 fps.
    var fps: Double {
        switch self {
        case .charging, .heat: return 24
        case .discharging: return 20
        case .holding: return 15
        case .onBattery: return 12
        case .idle: return 0
        }
    }

    var label: String {
        switch self {
        case .charging: return "charging"
        case .holding: return "holding at the limit"
        case .onBattery: return "on battery"
        case .discharging: return "discharging"
        case .heat: return "paused to cool down"
        case .idle: return "idle"
        }
    }
}

/// The website's glowing battery jar: liquid at the current charge, a dashed line at the limit, a soft glow in the
/// colour of the state, bubbles and steam while charging and a low flame under it while plugged in.
///
/// It animates only while its window is on screen (TimelineView, at most 24 fps) and draws one still frame when
/// Reduce Motion is on or the panel is closed.
struct GlowingJar: View {
    let percent: Int
    /// Dashed line at this level; nil hides it (limiter off).
    let limit: Int?
    let mood: JarMood

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = false

    /// Extra room around the layout frame for the glow.
    private static let bleed: CGFloat = 16

    private var still: Bool { reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        let paused = still || !onScreen || mood.fps == 0
        TimelineView(.animation(minimumInterval: 1 / max(mood.fps, 1), paused: paused)) { tl in
            let t = still ? 1.35 : tl.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: false) { ctx, size in
                JarPainter(percent: Double(percent), limit: limit.map(Double.init), mood: mood,
                           dark: scheme == .dark, t: t, motion: !still).draw(&ctx, size: size, bleed: Self.bleed)
            }
        }
        .padding(-Self.bleed)
        .allowsHitTesting(false)
        .background(WindowVisibilityReader { onScreen = $0 })
        .onDisappear { onScreen = false }
        .accessibilityElement()
        .accessibilityLabel("Battery \(percent) percent, \(mood.label)")
        .accessibilityAddTraits(.isImage)
    }
}

/// Draws the jar in the website's 320 × 400 coordinates (the jar is x 90...230, y 98...330, the burner at y 370).
private struct JarPainter {
    let percent: Double
    let limit: Double?
    let mood: JarMood
    let dark: Bool
    let t: Double
    let motion: Bool

    // The part of the website drawing that the layout frame shows.
    static let crop = CGRect(x: 62, y: 34, width: 196, height: 352)
    static let inner = CGRect(x: 104, y: 132, width: 112, height: 184)
    static let jar = CGRect(x: 90, y: 118, width: 140, height: 212)

    private var ink: RGB { dark ? Brand.steam : Brand.plum }
    private func frac(_ x: Double) -> Double { x - floor(x) }
    private func levelY(_ pct: Double) -> CGFloat { Self.inner.minY + Self.inner.height * CGFloat(1 - min(100, max(0, pct)) / 100) }

    private var glowColor: RGB {
        switch mood {
        case .charging: return Brand.amber
        case .holding: return Brand.green.mix(Brand.gold, 0.25)
        case .onBattery: return RGB(0x8b9cff)
        case .discharging: return Brand.ember.mix(Brand.amber, 0.3)
        case .heat: return RGB(0xff4a2a)
        case .idle: return RGB(0x9a9a9a)
        }
    }

    private var glowAlpha: Double {
        let base: Double
        switch mood {
        case .charging: base = 0.50 + 0.06 * sin(t * 2.1)
        case .holding: base = 0.46 + 0.05 * sin(t * 0.9)
        case .onBattery: base = 0.30
        case .discharging: base = 0.16 + 0.30 * (0.5 + 0.5 * sin(t * 4.2))     // a slow pulse
        case .heat: base = 0.50 + 0.10 * sin(t * 9.3) * sin(t * 3.1)
        case .idle: base = 0.0
        }
        return base * (dark ? 1 : 0.9)
    }

    /// Flame height: full while charging, a pilot flame while holding, none otherwise.
    private var flame: Double {
        switch mood {
        case .charging: return 0.55 + 0.45 * min(1, max(0, (percent - 20) / 80))
        case .holding: return 0.28
        default: return 0
        }
    }

    private var liquidColors: (bottom: RGB, top: RGB) {
        var (b, top) = Brand.liquid(level: percent)
        switch mood {
        case .onBattery:
            b = b.mix(RGB(0x9b7fe0), 0.30); top = top.mix(RGB(0xd8d2ff), 0.30)
        case .heat:
            b = b.mix(RGB(0xe3412a), 0.55); top = top.mix(RGB(0xff7a3c), 0.55)
        case .idle:
            b = b.mix(RGB(0x8e8e93), 0.7); top = top.mix(RGB(0xc7c7cc), 0.7)
        default: break
        }
        return (b, top)
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, bleed: CGFloat) {
        let frame = CGRect(x: bleed, y: bleed, width: size.width - 2 * bleed, height: size.height - 2 * bleed)
        let s = min(frame.width / Self.crop.width, frame.height / Self.crop.height)
        var g = ctx
        g.translateBy(x: frame.midX - Self.crop.midX * s, y: frame.midY - Self.crop.midY * s)
        g.scaleBy(x: s, y: s)
        let unit = 1 / s      // one point in drawing units

        glow(&g)
        burner(&g, unit: unit)
        steam(&g)
        glass(&g)
        cap(&g)
    }

    // MARK: glow

    private func glow(_ g: inout GraphicsContext) {
        let a = glowAlpha
        guard a > 0.01 else { return }
        var e = g
        e.translateBy(x: 160, y: 236)
        e.scaleBy(x: 1, y: 1.3)
        let r: CGFloat = 150
        e.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
               with: .radialGradient(Gradient(stops: [
                   .init(color: glowColor.color(a), location: 0),
                   .init(color: glowColor.color(a * 0.45), location: 0.45),
                   .init(color: glowColor.color(0), location: 1),
               ]), center: .zero, startRadius: 0, endRadius: r))
    }

    // MARK: burner and flames

    private func burner(_ g: inout GraphicsContext, unit: CGFloat) {
        let h = flame
        if h > 0 {
            let r: CGFloat = 96
            var e = g
            e.translateBy(x: 160, y: 360)
            e.scaleBy(x: 1, y: 0.42)
            e.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
                   with: .radialGradient(Gradient(colors: [Brand.amber.color(0.55 * h), Brand.ember.color(0)]),
                                         center: .zero, startRadius: 0, endRadius: r))
            let xs: [CGFloat] = [114, 137, 160, 183, 206]
            for (i, x) in xs.enumerated() {
                let edge = abs(Double(i) - 2) / 2
                let ph = Double(i) * 1.7
                let f = 8.0 + Double(i % 3) * 2.3
                let flick = motion ? 1 + 0.16 * sin(t * f + ph) + 0.08 * sin(t * f * 2.3 + ph) : 1
                let sy = (0.35 + h * 0.85) * flick * (1 - edge * 0.35)
                var fc = g
                fc.translateBy(x: x, y: 364)
                fc.scaleBy(x: 1.05, y: CGFloat(sy))
                var p = Path()
                p.move(to: CGPoint(x: -8, y: 0))
                p.addCurve(to: CGPoint(x: 0, y: -32), control1: CGPoint(x: -8, y: -11), control2: CGPoint(x: -2, y: -17))
                p.addCurve(to: CGPoint(x: 8, y: 0), control1: CGPoint(x: 2, y: -17), control2: CGPoint(x: 8, y: -11))
                p.closeSubpath()
                fc.fill(p, with: .linearGradient(Gradient(stops: [
                    .init(color: Brand.gold.color(0.95), location: 0),
                    .init(color: Brand.amber.color(0.9), location: 0.45),
                    .init(color: Brand.ember.color(0), location: 1),
                ]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: -32)))
            }
        }
        // Grate and burner ring: always there, so the jar stands on the stove.
        var grate = Path()
        grate.move(to: CGPoint(x: 84, y: 338)); grate.addLine(to: CGPoint(x: 236, y: 338))
        g.stroke(grate, with: .color(ink.color(dark ? 0.35 : 0.28)), style: StrokeStyle(lineWidth: 1.6 * unit, lineCap: .round))
        let ring = Path(ellipseIn: CGRect(x: 160 - 86, y: 370 - 9, width: 172, height: 18))
        g.stroke(ring, with: .color(ink.color(h > 0 ? (dark ? 0.45 : 0.35) : 0.2)), lineWidth: 1.6 * unit)
    }

    // MARK: steam

    private func steam(_ g: inout GraphicsContext) {
        let intensity: Double
        switch mood {
        case .charging: intensity = 0.45 + 0.45 * min(1, max(0, (percent - 20) / 80))
        case .heat: intensity = 0.8
        default: intensity = 0
        }
        guard intensity > 0 else { return }
        let cols: [(x: CGFloat, off: Double)] = [(160, 0), (134, 0.33), (186, 0.66)]
        let life = mood == .heat ? 2.2 : 3.0
        for (ci, col) in cols.enumerated() {
            for k in 0..<2 {
                let phase = motion ? frac(t / life + col.off + Double(k) * 0.5) : (k == 0 ? 0.35 : 0.75)
                let fade = sin(.pi * phase) * intensity * (ci == 0 ? 0.8 : 0.6)
                guard fade > 0.02 else { continue }
                let sway = motion ? sin(t * 1.3 + Double(ci) * 2.1) * 3 : 0
                let sc = 0.55 + 0.4 * phase
                var w = g
                w.translateBy(x: col.x + CGFloat(sway), y: CGFloat(94 - phase * 40))
                w.scaleBy(x: CGFloat(sc), y: CGFloat(sc))
                var p = Path()
                p.move(to: .zero)
                p.addCurve(to: CGPoint(x: 0, y: -27), control1: CGPoint(x: 9, y: -9), control2: CGPoint(x: -9, y: -18))
                p.addCurve(to: CGPoint(x: 0, y: -54), control1: CGPoint(x: 9, y: -36), control2: CGPoint(x: -9, y: -45))
                w.stroke(p, with: .color(ink.color(fade * (dark ? 0.75 : 0.55))),
                         style: StrokeStyle(lineWidth: 6.5, lineCap: .round))
            }
        }
    }

    // MARK: jar, liquid, bubbles

    private func glass(_ g: inout GraphicsContext) {
        let jar = Path(roundedRect: Self.jar, cornerRadius: 34)
        g.fill(jar, with: .color(dark ? Color.white.opacity(0.07) : Brand.plum.color(0.05)))

        let innerPath = Path(roundedRect: Self.inner, cornerRadius: 20)
        var lq = g
        lq.clip(to: innerPath)

        let y = levelY(percent)
        let amp: Double
        let speed: Double
        switch mood {
        case .charging: amp = 2.2; speed = 1
        case .heat: amp = 2.6; speed = 1.4
        case .discharging: amp = 1.4; speed = 0.8
        case .holding: amp = 1.0; speed = 0.55
        case .onBattery: amp = 0.9; speed = 0.5
        case .idle: amp = 0.5; speed = 0
        }
        var liquid = Path()
        let tt = t * speed
        liquid.move(to: CGPoint(x: 98, y: y + CGFloat(sin(tt * 2.1) * amp)))
        var x: CGFloat = 98
        while x <= 222 {
            let yy = y + CGFloat(sin(Double(x) * 0.09 + tt * 3.1) * amp + sin(Double(x) * 0.05 - tt * 1.7) * amp * 0.6)
            liquid.addLine(to: CGPoint(x: x, y: yy))
            x += 6
        }
        liquid.addLine(to: CGPoint(x: 222, y: 330))
        liquid.addLine(to: CGPoint(x: 98, y: 330))
        liquid.closeSubpath()
        let c = liquidColors
        lq.fill(liquid, with: .linearGradient(Gradient(colors: [c.bottom.color, c.top.color]),
                                             startPoint: CGPoint(x: 0, y: Self.inner.maxY), endPoint: CGPoint(x: 0, y: y)))

        var inLiquid = lq
        inLiquid.clip(to: liquid)
        // A soft band of light that climbs the liquid while charging; a faster red-orange shimmer for heat.
        if mood == .charging || mood == .heat {
            let k = motion ? frac(t * (mood == .heat ? 0.9 : 0.45)) : 0.5
            let span = Self.inner.maxY - y + 54
            let top = Self.inner.maxY - CGFloat(k) * span
            let a = sin(.pi * k) * (mood == .heat ? 0.55 : 0.5)
            let tint: RGB = mood == .heat ? RGB(0xffd0b0) : RGB(0xffffff)
            inLiquid.fill(Path(CGRect(x: 98, y: top, width: 124, height: 54)),
                          with: .linearGradient(Gradient(stops: [
                              .init(color: tint.color(0), location: 0),
                              .init(color: tint.color(a), location: 0.5),
                              .init(color: tint.color(0), location: 1),
                          ]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + 54)))
        }
        // Rising bubbles.
        let bubbles = mood == .charging ? 7 : (mood == .heat ? 5 : 0)
        if bubbles > 0 && y < Self.inner.maxY - 24 {
            let bottom = Self.inner.maxY - 4
            for i in 0..<bubbles {
                let fi = Double(i)
                let speed = 0.28 + 0.2 * frac(fi * 0.618)
                let phase = motion ? frac(t * speed + fi * 0.37) : frac(fi * 0.37 + 0.2)
                let by = bottom - CGFloat(phase) * (bottom - y - 5)
                let bx = 114 + CGFloat(frac(fi * 0.731)) * 92 + CGFloat(motion ? sin(t * 2 + fi) * 2 : 0)
                let r = 2.2 + 3 * CGFloat(frac(fi * 0.43))
                let a = 0.6 * min(1, phase * 6) * min(1, (1 - phase) * 5)
                inLiquid.fill(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: 2 * r, height: 2 * r)),
                              with: .color(.white.opacity(a)))
            }
        }
        // Glass sheen on the left.
        lq.fill(Path(roundedRect: CGRect(x: 110, y: 142, width: 9, height: 120), cornerRadius: 4.5),
                with: .linearGradient(Gradient(colors: [.white.opacity(dark ? 0.22 : 0.4), .white.opacity(0)]),
                                      startPoint: CGPoint(x: 0, y: 142), endPoint: CGPoint(x: 0, y: 262)))

        // Dashed limit line: white over the liquid, ink above it.
        if let limit, limit < 99.5 {
            let ly = levelY(limit)
            var p = Path()
            p.move(to: CGPoint(x: 114, y: ly)); p.addLine(to: CGPoint(x: 206, y: ly))
            let over = percent >= limit - 1.5
            g.stroke(p, with: .color(over ? .white.opacity(0.92) : ink.color(dark ? 0.7 : 0.55)),
                     style: StrokeStyle(lineWidth: 4.5, lineCap: .round, dash: [9, 8]))
        }
    }

    private func cap(_ g: inout GraphicsContext) {
        g.fill(Path(roundedRect: CGRect(x: 128, y: 98, width: 64, height: 15), cornerRadius: 6), with: .color(ink.color))
        g.stroke(Path(roundedRect: Self.jar, cornerRadius: 34), with: .color(ink.color), lineWidth: 9)
    }
}

/// Tells whether the hosting window is on screen (the menu bar panel is open), so animations can stop when it closes.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let v = VisibilityView()
        v.onChange = onChange
        return v
    }

    func updateNSView(_ v: VisibilityView, context: Context) { v.onChange = onChange }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []
        private var last: Bool?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens = []
            guard let w = window else { report(); return }
            let nc = NotificationCenter.default
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                tokens.append(nc.addObserver(forName: name, object: w, queue: .main) { [weak self] n in
                    let closing = n.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated { self?.report(forceHidden: closing) }
                })
            }
            report()
        }

        private func report(forceHidden: Bool = false) {
            var visible = false
            if !forceHidden, let w = window { visible = w.isVisible && w.occlusionState.contains(.visible) }
            guard visible != last else { return }
            last = visible
            let cb = onChange
            DispatchQueue.main.async { cb?(visible) }
        }

        deinit { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}

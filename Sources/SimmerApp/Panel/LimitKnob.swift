import SwiftUI
import AppKit

/// The website's names for a charge limit, from "Barely warm" to "A rolling boil".
enum SimmerLevel {
    static func name(_ v: Int) -> String {
        switch v {
        case ...45: return "Barely warm"
        case ...74: return "A low simmer"
        case ...85: return "A gentle simmer"
        case ...99: return "Close to the boil"
        default: return "A rolling boil"
        }
    }
}

/// The stove knob from the website, as a charge-limit control (20...100, step 1).
///
/// Input: rotary drag around the centre, vertical drag that starts on the cap, scroll wheel or trackpad over the
/// knob, a click on a scale label, the arrow keys (Shift = 5) and VoiceOver increment / decrement.
/// A drag, scroll or key press moves the knob 1:1. Changes from outside (quick limits, Shortcuts, the CLI, the
/// helper) turn it with a 0.45 s ease-in-out, unless Reduce Motion is on.
/// `commit` runs once per gesture: on drag end, on a click, or 0.45 s after the last key / scroll step.
struct LimitKnob<Footer: View>: View {
    let limit: Int
    let enabled: Bool
    let commit: (Int) -> Void
    var size: CGFloat
    /// Screenshots only: draw the knob as if the user were dragging it to this value.
    var dragPreview: Int?
    @ViewBuilder var footer: () -> Footer

    @State private var shown: Double
    @State private var active = false
    /// A focus ring only for keyboard users: macOS may focus the knob when the panel opens or on a click.
    @State private var keyboardUsed = false
    @State private var appeared = Date.distantFuture
    @FocusState private var focused: Bool
    @StateObject private var io = KnobInput()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    init(limit: Int, enabled: Bool, size: CGFloat = 132, dragPreview: Int? = nil,
         commit: @escaping (Int) -> Void, @ViewBuilder footer: @escaping () -> Footer) {
        self.limit = limit
        self.enabled = enabled
        self.size = size
        self.dragPreview = dragPreview
        self.commit = commit
        self.footer = footer
        _shown = State(initialValue: Double(KnobGeometry.clamp(dragPreview ?? limit)))
        _active = State(initialValue: dragPreview != nil)
    }

    private var value: Int { Int(shown.rounded()) }
    private var geo: KnobGeometry { KnobGeometry(size: size) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            dial
            readout
            Spacer(minLength: 0)
        }
        .onAppear {
            io.enabled = enabled
            appeared = Date()
        }
        .onChange(of: enabled) { _, on in io.enabled = on }
        .onChange(of: limit) { _, new in
            // Outside change: animate, unless the user is in the middle of a change.
            guard dragPreview == nil, io.dragStart == nil, io.pending == nil else { return }
            animate(to: new)
        }
        .onDisappear {
            removeMonitor()
            if io.pending != nil { commitNow() }
        }
    }

    // MARK: dial

    private var dial: some View {
        KnobFace(value: shown, size: size, enabled: enabled, active: active,
                 focused: focused && keyboardUsed, scheme: scheme)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(drag, including: enabled ? .all : .none)
            .onHover { inside in
                if inside { installMonitor() } else {
                    removeMonitor()
                    if io.pending != nil { commitNow() }
                }
            }
            .focusable(enabled)
            .focused($focused)
            .focusEffectDisabled()
            .onChange(of: focused) { _, on in
                guard on else { keyboardUsed = false; return }
                // Focus that arrives later than the panel opening and not from a click came from Tab.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    let now = Date()
                    if focused && now.timeIntervalSince(appeared) > 0.5 && now.timeIntervalSince(io.lastPress) > 0.4 {
                        keyboardUsed = true
                    }
                }
            }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .pageUp, .pageDown, .home, .end],
                        phases: [.down, .repeat]) { press in
                guard enabled else { return .ignored }
                let step = press.modifiers.contains(.shift) ? 5 : 1
                var v = value
                switch press.key {
                case .upArrow, .rightArrow: v += step
                case .downArrow, .leftArrow: v -= step
                case .pageUp: v += 10
                case .pageDown: v -= 10
                case .home: v = 20
                case .end: v = 100
                default: return .ignored
                }
                keyboardUsed = true
                setDirect(v)
                commitSoon()
                return .handled
            }
            .help(.chargeLimit)
            .accessibilityElement()
            .accessibilityLabel("Charge limit")
            .accessibilityValue("\(value) percent")
            .accessibilityHint("Charging stops at this level. Swipe up or down to adjust.")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                switch direction {
                case .increment: setDirect(value + 1)
                case .decrement: setDirect(value - 1)
                @unknown default: return
                }
                commitSoon()
            }
            .opacity(enabled ? 1 : 0.55)
    }

    // MARK: readout

    private var readout: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("CHARGE LIMIT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                InfoButton(.chargeLimit)
            }
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                CountingNumber(value: shown)
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                Text("%").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            }
            .foregroundStyle(enabled ? Color.primary : Color.secondary)
            .accessibilityHidden(true)
            Text(SimmerLevel.name(value))
                .font(.callout.weight(.semibold))
                .foregroundStyle(enabled ? Brand.accentText(scheme) : Color.secondary)
                .lineLimit(1)
                .padding(.bottom, 6)
            footer()
        }
    }

    // MARK: drag

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                if io.dragStart == nil { begin(at: g.startLocation) }
                if !io.moved && hypot(g.translation.width, g.translation.height) > 2 { io.moved = true }
                guard io.moved else { return }
                switch io.mode {
                case .rotary:
                    if let v = valueFromAngle(g.location) { setDirect(v) }
                case .vertical:
                    let delta = (-g.translation.height + g.translation.width * 0.5) * 0.4
                    setDirect(Int((io.dragStartValue + delta).rounded()))
                case .label:
                    break
                }
            }
            .onEnded { g in
                let mode = io.mode, moved = io.moved
                io.dragStart = nil
                io.moved = false
                active = false
                switch mode {
                case .label(let v):
                    animate(to: v)
                    commitValue(v)
                case .rotary where !moved:
                    if let v = valueFromAngle(g.location) {
                        animate(to: v)
                        commitValue(v)
                    }
                default:
                    commitNow()
                }
            }
    }

    private func begin(at p: CGPoint) {
        io.dragStart = p
        io.lastPress = Date()
        io.dragStartValue = shown
        io.lastAngle = KnobGeometry.angle(shown)
        io.pending?.cancel()
        io.pending = nil
        active = true
        let g = geo
        if let hit = KnobGeometry.majors.first(where: { hypot(g.point(g.labelR, KnobGeometry.angle(Double($0))).x - p.x,
                                                              g.point(g.labelR, KnobGeometry.angle(Double($0))).y - p.y) < 11 }) {
            io.mode = .label(hit)
        } else if hypot(p.x - g.center.x, p.y - g.center.y) < g.capR * 0.7 {
            io.mode = .vertical
        } else {
            io.mode = .rotary
        }
    }

    private func valueFromAngle(_ p: CGPoint) -> Int? {
        let c = geo.center
        let dx = p.x - c.x, dy = p.y - c.y
        guard hypot(dx, dy) > size * 0.06 else { return nil }
        var a = atan2(dx, -dy) * 180 / .pi
        // The gap at the bottom of the scale: stay at the end the pointer came from.
        if a < KnobGeometry.a0 || a > KnobGeometry.a1 { a = io.lastAngle > 0 ? KnobGeometry.a1 : KnobGeometry.a0 }
        io.lastAngle = a
        return Int((20 + (a - KnobGeometry.a0) / (KnobGeometry.a1 - KnobGeometry.a0) * 80).rounded())
    }

    // MARK: value changes

    private var noMotion: Bool { reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Direct manipulation: 1:1, no tween, with a light detent tap at 20 / 50 / 80 / 100.
    private func setDirect(_ v: Int) {
        let v = KnobGeometry.clamp(v)
        let old = value
        guard v != old || Double(v) != shown else { return }
        KnobGeometry.detentFeedback(from: old, to: v)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { shown = Double(v) }
    }

    /// Discrete or outside change: a smooth ease-in-out turn of the pointer, the arc and the number.
    private func animate(to v: Int) {
        let target = Double(KnobGeometry.clamp(v))
        guard target != shown else { return }
        if noMotion {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { shown = target }
        } else {
            withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.45)) { shown = target }
        }
    }

    private func commitValue(_ v: Int) {
        io.pending?.cancel()
        io.pending = nil
        let v = KnobGeometry.clamp(v)
        if v != limit { commit(v) }
    }

    private func commitNow() { commitValue(value) }

    /// Key presses, scroll steps and VoiceOver adjustments come in bursts: send one change when they stop.
    private func commitSoon() {
        io.pending?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated { commitNow() } }
        io.pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: w)
    }

    // MARK: scroll wheel and trackpad

    private func installMonitor() {
        guard io.monitor == nil else { return }
        // Local monitors run on the main thread.
        io.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            let step = ScrollStep(e)
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard io.enabled else { return false }
                scrolled(step)
                return true
            }
            return handled ? nil : e
        }
    }

    private func removeMonitor() {
        if let m = io.monitor { NSEvent.removeMonitor(m) }
        io.monitor = nil
        io.scrollAccum = 0
    }

    private func scrolled(_ e: ScrollStep) {
        if e.momentum { return }      // no inertia: the knob stops when the fingers stop
        if e.began { io.scrollAccum = 0 }
        let raw = abs(e.dy) >= abs(e.dx) ? e.dy : -e.dx
        // Wheel away from you / fingers up = higher, whatever the "natural scrolling" setting is.
        let d = e.inverted ? -raw : raw
        var steps = 0
        if e.precise {
            io.scrollAccum += d
            steps = Int(io.scrollAccum / 6)
            io.scrollAccum -= CGFloat(steps) * 6
        } else if d != 0 {
            steps = d > 0 ? max(1, Int(d.rounded())) : min(-1, Int(d.rounded()))
        }
        guard steps != 0 else { return }
        setDirect(value + steps)
        commitSoon()
    }
}

/// The parts of a scroll event the knob needs (NSEvent itself is not Sendable).
struct ScrollStep: Sendable {
    let dx: CGFloat, dy: CGFloat
    let precise: Bool, inverted: Bool, began: Bool, momentum: Bool

    init(_ e: NSEvent) {
        dx = e.scrollingDeltaX
        dy = e.scrollingDeltaY
        precise = e.hasPreciseScrollingDeltas
        inverted = e.isDirectionInvertedFromDevice
        began = e.phase == .began
        momentum = e.momentumPhase != []
    }
}

/// Mutable input state that must not trigger a redraw.
@MainActor
final class KnobInput: ObservableObject {
    enum Mode { case rotary, vertical, label(Int) }
    var mode: Mode = .rotary
    var dragStart: CGPoint?
    var dragStartValue = 80.0
    var moved = false
    var lastAngle = 0.0
    var pending: DispatchWorkItem?
    var monitor: Any?
    var scrollAccum: CGFloat = 0
    var enabled = true
    var lastPress = Date.distantPast
}

/// Proportions of the website's knob (240-unit viewBox), with larger labels for the small panel size.
struct KnobGeometry {
    let size: CGFloat
    static let a0 = -135.0, a1 = 135.0
    static let majors = [20, 40, 60, 80, 100]
    static let detents = [20, 50, 80, 100]

    var center: CGPoint { CGPoint(x: size / 2, y: size / 2) }
    var k: CGFloat { size / 240 }
    var skirtR: CGFloat { 72 * k }
    var ridgeR: CGFloat { 63 * k }
    var capR: CGFloat { 51 * k }
    var arcR: CGFloat { 90 * k }
    var tickIn: CGFloat { 76 * k }
    var labelR: CGFloat { 113 * k }
    var labelFont: CGFloat { max(9, 16 * k) }

    static func clamp(_ v: Int) -> Int { min(100, max(20, v)) }
    static func angle(_ v: Double) -> Double { a0 + (v - 20) / 80 * (a1 - a0) }

    /// A point at `r` from the centre, `deg` degrees clockwise from 12 o'clock.
    func point(_ r: CGFloat, _ deg: Double) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: center.x + r * sin(a), y: center.y - r * cos(a))
    }

    func arc(_ r: CGFloat, from: Double, to: Double) -> Path {
        var p = Path()
        let n = max(2, Int(abs(to - from) / 2))
        for i in 0...n {
            let pt = point(r, from + (to - from) * Double(i) / Double(n))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    /// A light trackpad tap when the value lands on or passes 20, 50, 80 or 100.
    static func detentFeedback(from a: Int, to b: Int) {
        guard a != b else { return }
        let lo = min(a, b), hi = max(a, b)
        if detents.contains(where: { $0 != a && $0 >= lo && $0 <= hi }) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}

/// The drawn knob. `value` is animatable, so an outside change turns the pointer, ridges and arc together.
private struct KnobFace: View, Animatable {
    var value: Double
    let size: CGFloat
    let enabled: Bool
    let active: Bool
    let focused: Bool
    let scheme: ColorScheme

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Canvas { ctx, _ in draw(&ctx) }
            .frame(width: size, height: size)
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let g = KnobGeometry(size: size)
        let c = g.center
        let dark = scheme == .dark
        let ink2 = dark ? RGB(0xd2c0d6) : RGB(0x5d4867)
        let ink3 = dark ? RGB(0xa993b0) : RGB(0x7d6a86)
        let angle = KnobGeometry.angle(value)
        let arcW = max(3.5, 7 * g.k)

        // Scale track and the coloured progress arc (gold → amber → ember).
        ctx.stroke(g.arc(g.arcR, from: KnobGeometry.a0, to: KnobGeometry.a1),
                   with: .color(.primary.opacity(dark ? 0.12 : 0.08)),
                   style: StrokeStyle(lineWidth: arcW, lineCap: .round))
        if value > 20.05 {
            let shade: GraphicsContext.Shading
            if enabled {
                let lead = 8.0 / 360
                shade = .conicGradient(Gradient(stops: [
                    .init(color: Brand.gold.color, location: lead),
                    .init(color: Brand.amber.color, location: lead + 0.36),
                    .init(color: Brand.ember.color, location: lead + 0.75),
                    .init(color: Brand.ember.color, location: 1),
                ]), center: c, angle: .degrees(127))
            } else {
                shade = .color(.secondary.opacity(0.6))
            }
            ctx.stroke(g.arc(g.arcR, from: KnobGeometry.a0, to: angle), with: shade,
                       style: StrokeStyle(lineWidth: arcW, lineCap: .round))
        }

        // Ticks every 5, longer at the labelled values.
        for v in stride(from: 20, through: 100, by: 5) {
            let major = v % 20 == 0
            let a = KnobGeometry.angle(Double(v))
            var p = Path()
            p.move(to: g.point(g.tickIn + (major ? 0 : 2.5 * g.k), a))
            p.addLine(to: g.point(g.tickIn + (major ? 9 : 6.5) * g.k, a))
            ctx.stroke(p, with: .color((major ? ink2 : ink3).color(major ? 0.9 : 0.6)),
                       style: StrokeStyle(lineWidth: major ? 1.4 : 1, lineCap: .round))
        }
        let current = Int(value.rounded())
        for v in KnobGeometry.majors {
            let on = enabled && v == current
            let text = Text("\(v)")
                .font(.system(size: g.labelFont, weight: on ? .bold : .semibold, design: .rounded))
                .foregroundColor(on ? Brand.accentText(scheme) : ink2.color(0.9))
            ctx.draw(text, at: g.point(g.labelR, KnobGeometry.angle(Double(v))), anchor: .center)
        }

        // Knob body: skirt with a soft shadow (and an ember glow while held), ridges, domed cap, pointer.
        let skirt = Path(ellipseIn: CGRect(x: c.x - g.skirtR, y: c.y - g.skirtR, width: g.skirtR * 2, height: g.skirtR * 2))
        var s = ctx
        if active && enabled {
            s.addFilter(.shadow(color: Brand.ember.color(dark ? 0.85 : 0.7), radius: 22 * g.k))
        } else {
            s.addFilter(.shadow(color: .black.opacity(dark ? 0.5 : 0.22), radius: 6 * g.k * 2, x: 0, y: 5 * g.k))
        }
        s.fill(skirt, with: .color((dark ? RGB(0x382c44) : RGB(0xe9dfe8)).color))
        if focused {
            let r = g.skirtR + 3
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(Brand.accentText(scheme).opacity(0.6)), lineWidth: 1.5)
        }

        var body = ctx
        body.translateBy(x: c.x, y: c.y)
        body.rotate(by: .degrees(angle))
        let ridge = Path(ellipseIn: CGRect(x: -g.ridgeR, y: -g.ridgeR, width: g.ridgeR * 2, height: g.ridgeR * 2))
        body.stroke(ridge, with: .color(dark ? Color(.sRGB, red: 1, green: 0.94, blue: 0.9, opacity: 0.14) : Brand.plum.color(0.16)),
                    style: StrokeStyle(lineWidth: 14 * g.k, dash: [2 * g.k, 4.5 * g.k]))
        let capRect = CGRect(x: -g.capR, y: -g.capR, width: g.capR * 2, height: g.capR * 2)
        ctx.fill(Path(ellipseIn: capRect.offsetBy(dx: c.x, dy: c.y)),
                 with: .radialGradient(Gradient(colors: [(dark ? RGB(0x6e5d80) : RGB(0xffffff)).color,
                                                         (dark ? RGB(0x3b3047) : RGB(0xf1e8f0)).color]),
                                       center: CGPoint(x: c.x - g.capR * 0.24, y: c.y - g.capR * 0.4),
                                       startRadius: 0, endRadius: g.capR * 1.7))
        ctx.stroke(Path(ellipseIn: capRect.offsetBy(dx: c.x, dy: c.y)), with: .color(.primary.opacity(0.13)), lineWidth: 0.75)
        let pw = 9 * g.k
        let pointer = Path(roundedRect: CGRect(x: -pw / 2, y: -58 * g.k, width: pw, height: 40 * g.k), cornerRadius: pw / 2)
        body.fill(pointer, with: .color(enabled ? Brand.ember.color : Color.secondary))
    }
}

/// A number that counts through the values while it animates.
private struct CountingNumber: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text("\(Int(value.rounded()))") }
}

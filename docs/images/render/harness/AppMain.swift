import SwiftUI
import AppKit
import SimmerShared

// Renders the menu bar panel and Settings pages with mock data into PNGs (2x).
// usage: AppShots <outdir>

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "out")

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor func render<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil, dark: Bool, name: String) {
    let host = NSHostingView(rootView: view.frame(width: width, height: height).environment(\.controlActiveState, .key))
    host.layoutSubtreeIfNeeded()
    let size = CGSize(width: width, height: height ?? max(100, host.fittingSize.height))
    host.frame = CGRect(origin: .zero, size: size)
    let window = KeyWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.backgroundColor = .clear
    window.isOpaque = false
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    window.makeKeyAndOrderFront(nil)
    for _ in 0..<16 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded() }
    // Draw at 2x regardless of the screen the offscreen window sits on.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    let url = outDir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    window.orderOut(nil)
    print("wrote", url.lastPathComponent, rep.pixelsWide, "x", rep.pixelsHigh)
}

// MARK: - Window chrome (the real sidebar is an NSTableView, which does not draw offscreen)

struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34))
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18))
            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
        }
        .frame(height: 12)
        .frame(width: 52, height: 12)
    }
}

struct StaticSidebar: View {
    let selected: SettingsPage
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(SettingsPage.sidebar.indices, id: \.self) { i in
                let group = SettingsPage.sidebar[i]
                if let title = group.title {
                    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.leading, 10).padding(.top, 10).padding(.bottom, 3)
                } else if i > 0 {
                    Spacer().frame(height: 10)
                }
                ForEach(group.pages) { page in
                    HStack(spacing: 8) {
                        PageIcon(page: page, size: 20)
                        Text(page.title).font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(page == selected ? Color.primary.opacity(scheme == .dark ? 0.14 : 0.09) : .clear))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }
}

struct FakeSettingsWindow: View {
    let page: SettingsPage
    let model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var refresh: PageRefresh?
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TrafficLights().padding(.leading, 18).padding(.top, 18).padding(.bottom, 14)
                StaticSidebar(selected: page)
            }
            .frame(width: 222)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(scheme == .dark ? Color(white: 0.17) : Color(white: 0.955))
                .padding(8))
            VStack(spacing: 0) {
                FakeToolbar(title: page.title, refresh: refresh)
                SettingsDetail(page: page, model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onPreferenceChange(PageRefreshKey.self) { r in MainActor.assumeIsolated { refresh = r } }
            }
        }
        .background(scheme == .dark ? Color(white: 0.115) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// The window title and, on pages with live data, the Refresh control that the real window puts in its toolbar.
struct FakeToolbar: View {
    let title: String
    let refresh: PageRefresh?
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            if let refresh {
                PageRefreshControl(refresh: refresh)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
        .padding(.leading, 20).padding(.trailing, 16).frame(height: 50)
    }
}

struct PanelChrome<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        content
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.975))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Mock state

@MainActor func makeModel() -> AppModel {
    let m = AppModel()
    m.status = mockStatus()
    m.localBattery = mockBattery()
    var c = m.config
    c.chargeLimit = 80
    c.limiterEnabled = true
    c.sailingEnabled = true
    c.heatProtectionEnabled = true
    m.config = c
    m.configLoaded = true
    m.reachable = true
    m.helperVersion = Simmer.helperVersion
    return m
}

@MainActor func prepareInsights() {
    let i = InsightsModel.shared
    i.energy = mockEnergy()
    i.energyLoaded = true
    i.history = mockHistory()
    i.conflicts = []
    i.conflictsScanned = true
}

// MARK: - Main

// Render with the default blue accent, whatever this Mac uses (volatile: nothing is written to disk).
// Keyboard navigation off, so no focus ring is drawn on the first focusable control.
UserDefaults.standard.setVolatileDomain(["AppleAccentColor": 4, "AppleHighlightColor": "0.698039 0.843137 1.000000 Blue",
                                         "AppleKeyboardUIMode": 0],
                                        forName: UserDefaults.argumentDomain)

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let only = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
    prepareInsights()
    // Energy page: what the close buttons offer for the demo processes (no real process scan).
    ProcessControl.shared.overrides = [
        "/usr/local/bin/node": .process(name: "node", procs: [ProcRef(pid: 4242, path: "/usr/local/bin/node", uid: 501)]),
        "/usr/local/bin/ffmpeg": .process(name: "ffmpeg", procs: [ProcRef(pid: 5120, path: "/usr/local/bin/ffmpeg", uid: 501)]),
        "/usr/local/bin/python3": .process(name: "python3", procs: [ProcRef(pid: 6001, path: "/usr/local/bin/python3", uid: 501)]),
        "/usr/local/bin/photo-export": .process(name: "photo-export", procs: [ProcRef(pid: 7310, path: "/usr/local/bin/photo-export", uid: 501)]),
        "/usr/local/bin/rsync": .blocked(ProcessControl.otherUserReason),
        "/usr/local/bin/backup-agent": .blocked(ProcessControl.otherUserReason),
    ]
    // The default panel (knob, battery jar, default sections), whatever an earlier run saved.
    PanelLayoutStore.shared.layout = PanelLayout()
    let model = makeModel()
    let history = mockHistory()

    let pages: [(SettingsPage, CGFloat)] = [
        (.general, 820), (.charging, 820), (.smartCharging, 820), (.led, 820), (.schedule, 820),
        (.history, 820), (.energy, 820), (.batteryHealth, 820), (.sleepDrain, 820), (.conflicts, 820),
    ]
    for dark in [false, true] {
        if only.isEmpty || "panel".hasPrefix(only) || only == "panel" {
            render(PanelChrome { PanelView(model: model) }, width: 330, dark: dark, name: "panel")
        }
        if only.isEmpty || only == "variants" {
            renderPanelVariants(dark: dark)
        }
        for (page, h) in pages where only.isEmpty || page.rawValue.hasPrefix(only) {
            let view: AnyView
            if page == .history {
                view = AnyView(FakeSettingsWindowHistory(model: model, history: history))
            } else {
                view = AnyView(FakeSettingsWindow(page: page, model: model))
            }
            render(view, width: 900, height: h, dark: dark, name: "settings-\(page.rawValue)")
        }
    }
}

// MARK: - Panel variants (states, knob mid-drag, slider look); not used by the README

@MainActor func variantModel(_ state: ChargeState, percent: Int, amps: Double = 0, plugged: Bool = true,
                             minutes: Int? = nil, tempC: Double = 30.4) -> AppModel {
    let m = makeModel()
    var b = mockBattery(percent: percent)
    b.externalConnected = plugged
    b.isCharging = amps > 0
    b.amperageA = amps
    b.timeRemainingMin = minutes
    b.temperatureC = tempC
    b.rawCurrentCapacity = Int(Double(b.rawMaxCapacity) * Double(percent) / 100)
    if !plugged { b.adapterWatts = 0; b.adapterName = "" }
    var s = m.status!
    s.state = state
    s.battery = b
    s.chargingInhibited = state != .charging && state != .topUp
    s.adapterDisabled = state == .discharging
    s.smcTemperatureC = tempC
    m.status = s
    m.localBattery = b
    return m
}

@MainActor func renderPanelVariants(dark: Bool) {
    let variants: [(String, AppModel)] = [
        ("panel-charging", variantModel(.charging, percent: 62, amps: 3.1, minutes: 48)),
        ("panel-discharging", variantModel(.discharging, percent: 91, amps: -1.6)),
        ("panel-battery", variantModel(.notPluggedIn, percent: 64, amps: -0.9, plugged: false, minutes: 312)),
        ("panel-heat", variantModel(.heatProtection, percent: 71, tempC: 38.6)),
        ("panel-macos-paused", variantModel(.charging, percent: 62)),
        ("panel-weak-charger", variantModel(.charging, percent: 55, amps: -0.7)),
    ]
    for (name, m) in variants {
        render(PanelChrome { PanelView(model: m) }, width: 330, dark: dark, name: name)
    }
    // The limit knob while the user drags it from 80% to 67%.
    render(PanelChrome {
        LimitKnob(limit: 80, enabled: true, dragPreview: 67, commit: { _ in }) {
            Toggle(isOn: .constant(true)) { Text("Charge Limiter") }.toggleStyle(HarnessSwitch()).controlSize(.small)
        }
        .padding(14)
    }, width: 330, dark: dark, name: "knob-drag")
    // Limiter off: knob disabled.
    let off = makeModel()
    off.config.limiterEnabled = false
    var so = off.status!
    so.state = .limiterOff
    off.status = so
    render(PanelChrome { PanelView(model: off) }, width: 330, dark: dark, name: "panel-limiter-off")
    // The classic look: slider, no illustration.
    let store = PanelLayoutStore.shared
    let saved = store.layout
    store.layout.limitControl = .slider
    store.layout.showIllustration = false
    render(PanelChrome { PanelView(model: makeModel()) }, width: 330, dark: dark, name: "panel-slider")
    store.layout = saved
}

/// The history page with mock data injected (it normally loads from disk).
struct FakeSettingsWindowHistory: View {
    let model: AppModel
    let history: BatteryHistory
    var body: some View {
        FakeSettingsWindowContent(page: .history) {
            HistoryPage(model: model, initial: .loaded(history), autoReload: false)
        }
    }
}

struct FakeSettingsWindowContent<Detail: View>: View {
    let page: SettingsPage
    @ViewBuilder var detail: Detail
    @Environment(\.colorScheme) private var scheme
    @State private var refresh: PageRefresh?
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TrafficLights().padding(.leading, 18).padding(.top, 18).padding(.bottom, 14)
                StaticSidebar(selected: page)
            }
            .frame(width: 222)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(scheme == .dark ? Color(white: 0.17) : Color(white: 0.955))
                .padding(8))
            VStack(spacing: 0) {
                FakeToolbar(title: page.title, refresh: refresh)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onPreferenceChange(PageRefreshKey.self) { r in MainActor.assumeIsolated { refresh = r } }
            }
        }
        .background(scheme == .dark ? Color(white: 0.115) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// Look-alike of the macOS switch that always draws the "active window" colors. The real switch turns
/// gray when the app is not frontmost, which is always the case for an offscreen render.
/// render.sh swaps `.toggleStyle(.switch)` for this style in the harness copy of the sources.
struct HarnessSwitch: ToggleStyle {
    @Environment(\.controlSize) private var controlSize
    func makeBody(configuration: Configuration) -> some View {
        let (w, h): (CGFloat, CGFloat) = switch controlSize {
        case .mini: (26, 15)
        case .small: (32, 18)
        default: (38, 22)
        }
        HStack(spacing: 8) {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                // `.tint` follows the panel's ember tint like the real switch; elsewhere it is the system accent.
                Capsule().fill(configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.13)))
                Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 0.8, y: 0.5)
                    .padding(1.5)
            }
            .frame(width: w, height: h)
            .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

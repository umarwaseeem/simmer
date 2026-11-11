import SwiftUI

/// The Simmer colours from the website and the app icon: plum → wine → ember, with amber, gold and steam.
enum Brand {
    static let plum = RGB(0x2a1636)
    static let wine = RGB(0x7a2938)
    static let ember = RGB(0xee6b33)
    static let amber = RGB(0xff9a3c)
    static let gold = RGB(0xffd35c)
    static let steam = RGB(0xfff6ec)
    static let green = RGB(0x3fbf6a)

    /// Ember text that is dark enough on light backgrounds and bright enough on dark ones.
    static func accentText(_ scheme: ColorScheme) -> Color { (scheme == .dark ? RGB(0xff9a5a) : RGB(0xb23f14)).color }

    /// Jar outline and lid: plum on light, steam-cream on dark.
    static func ink(_ scheme: ColorScheme) -> Color { (scheme == .dark ? steam : plum).color }

    /// Fill for selected chips, active buttons and switches (the website's --accent-fill).
    static let accentFill = ember
    /// Text on an accent fill: plum, 5.4:1 on ember (WCAG AA).
    static let onAccent = RGB(0x2a1636)

    /// Text tones for the panel: primary, secondary, tertiary. All pass WCAG AA (4.5:1) on the panel background.
    static func inks(_ scheme: ColorScheme) -> (Color, Color, Color) {
        scheme == .dark
            ? (RGB(0xfbf1e7).color, RGB(0xd2c0d6).color, RGB(0xa993b0).color)
            : (RGB(0x2a1636).color, RGB(0x5d4867).color, RGB(0x6f5b78).color)
    }

    /// The charge-level gradient of the website's jar: amber and gold that warm toward red near 100%.
    /// `level` is 0...100.
    static func liquid(level: Double) -> (bottom: RGB, top: RGB) {
        let h = min(1, max(0, (level - 20) / 80))
        let h3 = h * h * h
        return (RGB(0xffa53d).mix(RGB(0xe3412a), h3), RGB(0xffe08a).mix(RGB(0xff9a3c), h3))
    }
}

/// A plain sRGB colour that can be mixed (SwiftUI `Color` cannot).
struct RGB: Equatable {
    var r: Double, g: Double, b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xff) / 255
        g = Double((hex >> 8) & 0xff) / 255
        b = Double(hex & 0xff) / 255
    }

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    func mix(_ o: RGB, _ t: Double) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    func color(_ opacity: Double) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: opacity) }
}

/// The warm plum → ember wash behind the menu bar panel, like the website hero. It lies over the window
/// material at low strength, so text stays crisp and the panel still reads as a macOS panel.
struct PanelBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(stops: dark
                           ? [.init(color: Brand.plum.color(0.78), location: 0),
                              .init(color: RGB(0x3a1830).color(0.72), location: 0.62),
                              .init(color: Brand.wine.color(0.48), location: 1)]
                           : [.init(color: RGB(0xf6f0f5).color(0.80), location: 0),
                              .init(color: RGB(0xf8eef0).color(0.80), location: 0.6),
                              .init(color: RGB(0xfbe9df).color(0.85), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            // The glow of the low flame, behind the jar.
            RadialGradient(colors: [Brand.ember.color(dark ? 0.22 : 0.10), Brand.ember.color(0)],
                           center: UnitPoint(x: 0.16, y: 0.10), startRadius: 0, endRadius: 210)
            // A second, softer glow at the bottom edge, as on the website.
            RadialGradient(colors: [Brand.amber.color(dark ? 0.10 : 0.07), Brand.amber.color(0)],
                           center: UnitPoint(x: 0.8, y: 1.05), startRadius: 0, endRadius: 260)
        }
        .allowsHitTesting(false)
    }
}

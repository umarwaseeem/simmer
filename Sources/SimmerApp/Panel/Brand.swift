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

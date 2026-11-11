// Renders the Simmer app icon (1024×1024 PNG): a battery held at 80% with gentle steam above it.
// Usage: swift scripts/make-icon.swift <out.png>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }

// macOS icon grid: 824pt squircle centred in 1024, with a soft drop shadow.
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(color(0.1, 0.1, 0.1)); ctx.fillPath()
ctx.restoreGState()

// Background: deep plum to warm ember gradient.
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [color(0.16, 0.10, 0.24), color(0.47, 0.16, 0.22), color(0.93, 0.42, 0.20)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
// Warm glow under the battery, like a low flame.
let glow = CGGradient(colorsSpace: cs, colors: [color(1, 0.62, 0.25, 0.55), color(1, 0.5, 0.2, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: size / 2, y: 250), startRadius: 0,
                       endCenter: CGPoint(x: size / 2, y: 250), endRadius: 380, options: [])
// Subtle top sheen.
let sheen = CGGradient(colorsSpace: cs, colors: [color(1, 1, 1, 0.14), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.midY), options: [])
ctx.restoreGState()

// Battery body (vertical), centred slightly low to leave room for steam.
let body = CGRect(x: 362, y: 210, width: 300, height: 450)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 64, cornerHeight: 64, transform: nil)
let cap = CGRect(x: 452, y: body.maxY + 14, width: 120, height: 42)
let capPath = CGPath(roundedRect: cap, cornerWidth: 18, cornerHeight: 18, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0.1, 0, 0.05, 0.45))
ctx.addPath(bodyPath); ctx.setFillColor(color(1, 1, 1, 0.16)); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(bodyPath); ctx.setStrokeColor(color(1, 0.97, 0.93)); ctx.setLineWidth(26); ctx.strokePath()
ctx.addPath(capPath); ctx.setFillColor(color(1, 0.97, 0.93)); ctx.fillPath()

// Charge level at 80% (the default limit), amber-to-gold fill.
let pad: CGFloat = 34
let inner = body.insetBy(dx: pad, dy: pad)
let level = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height * 0.8)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: level, cornerWidth: 34, cornerHeight: 34, transform: nil)); ctx.clip()
let fill = CGGradient(colorsSpace: cs, colors: [color(1, 0.55, 0.18), color(1, 0.84, 0.36)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: level.minY), end: CGPoint(x: 0, y: level.maxY), options: [])
ctx.restoreGState()
// Limit tick at 80%.
ctx.setStrokeColor(color(1, 0.97, 0.93, 0.9)); ctx.setLineWidth(10); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: inner.minX + 18, y: level.maxY + 1)); ctx.addLine(to: CGPoint(x: inner.maxX - 18, y: level.maxY + 1)); ctx.strokePath()

// Steam: three soft S-curves rising from the cap.
func wisp(x: CGFloat, height: CGFloat, alpha: CGFloat) {
    let p = CGMutablePath()
    let y0 = cap.maxY + 34
    p.move(to: CGPoint(x: x, y: y0))
    p.addCurve(to: CGPoint(x: x, y: y0 + height * 0.5), control1: CGPoint(x: x + 34, y: y0 + height * 0.18), control2: CGPoint(x: x - 34, y: y0 + height * 0.32))
    p.addCurve(to: CGPoint(x: x, y: y0 + height), control1: CGPoint(x: x + 34, y: y0 + height * 0.68), control2: CGPoint(x: x - 34, y: y0 + height * 0.82))
    ctx.addPath(p); ctx.setStrokeColor(color(1, 0.97, 0.93, alpha)); ctx.setLineWidth(20); ctx.setLineCap(.round); ctx.strokePath()
}
wisp(x: 442, height: 120, alpha: 0.55)
wisp(x: 512, height: 150, alpha: 0.85)
wisp(x: 582, height: 120, alpha: 0.55)

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

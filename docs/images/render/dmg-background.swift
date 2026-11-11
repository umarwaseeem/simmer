// Renders the DMG window background (640x400 pt) at 1x and 2x.
// usage: swift dmgbg.swift <outdir>
import SwiftUI
import AppKit

struct Arrow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 4, y: r.midY), control: CGPoint(x: r.midX, y: r.minY - 18))
        return p
    }
}
struct Head: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        return p
    }
}

struct BG: View {
    let ember = Color(red: 0.93, green: 0.42, blue: 0.20)
    let plum = Color(red: 0.30, green: 0.13, blue: 0.24)
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 1.0, green: 0.975, blue: 0.95), Color(red: 1.0, green: 0.93, blue: 0.87)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [ember.opacity(0.16), .clear], center: UnitPoint(x: 0.5, y: 1.15), startRadius: 0, endRadius: 360)
            // Soft wells under the two icons.
            ForEach([170.0, 470.0], id: \.self) { x in
                Circle().fill(Color.white.opacity(0.75)).frame(width: 176, height: 176)
                    .shadow(color: plum.opacity(0.10), radius: 14, y: 4)
                    .position(x: x, y: 200)
            }
            // Arrow from the app to Applications.
            Arrow().stroke(ember.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 9]))
                .frame(width: 120, height: 30).position(x: 320, y: 190)
            Head().fill(ember.opacity(0.9)).frame(width: 12, height: 14).position(x: 378, y: 190)
            VStack(spacing: 4) {
                Text("Drag Simmer to Applications")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(plum)
                Text("Keep it below the boil.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(plum.opacity(0.55))
            }
            .frame(width: 640).position(x: 320, y: 335)
            Text("First launch: right-click Simmer \u{2192} Open")
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundStyle(plum.opacity(0.45))
                .frame(width: 640).position(x: 320, y: 382)
        }
        .frame(width: 640, height: 400)
    }
}

@MainActor func save(_ scale: CGFloat, _ url: URL) {
    let r = ImageRenderer(content: BG())
    r.scale = scale
    guard let cg = r.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = NSSize(width: 640, height: 400)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print(url.path, cg.width, cg.height)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
MainActor.assumeIsolated {
    save(1, out.appendingPathComponent("background.png"))
    save(2, out.appendingPathComponent("background@2x.png"))
}

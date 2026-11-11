import Foundation

/// Turns a LED notification into timed ACLC writes. Pure, unit tested; simmerd plays the steps.
public enum LEDPatternPlayer {
    public struct Step: Equatable, Sendable {
        public var color: LEDColor
        public var seconds: Double
        public init(_ color: LEDColor, _ seconds: Double) { self.color = color; self.seconds = seconds }
    }

    /// Longest notification; longer patterns are cut.
    public static let maxSeconds = 20.0
    public static let maxRepeats = 10

    /// Steps for one notification. Writes stay at 2–4 per second (0.25–0.5 s per step).
    /// `percent` is used by `.chargeLevel` (one green blink per 10 %, rounded, at least one).
    public static func steps(_ pattern: LEDPattern, repeats: Int, percent: Int) -> [Step] {
        let n = min(maxRepeats, max(1, repeats))
        var one: [Step]
        switch pattern {
        case .blinkGreen: one = [Step(.green, 0.4), Step(.off, 0.4)]
        case .blinkOrange: one = [Step(.orange, 0.4), Step(.off, 0.4)]
        case .alternate: one = [Step(.green, 0.4), Step(.orange, 0.4)]
        case .heartbeat: one = [Step(.orange, 0.25), Step(.off, 0.25), Step(.orange, 0.25), Step(.off, 0.5)]
        case .chargeLevel:
            let blinks = max(1, min(10, Int((Double(percent) / 10).rounded())))
            one = Array(repeating: [Step(.green, 0.3), Step(.off, 0.3)], count: blinks).flatMap { $0 }
            one[one.count - 1] = Step(.off, 1.0)   // pause between repeats
        }
        var out: [Step] = []
        var total = 0.0
        for _ in 0..<n {
            for s in one {
                guard total + s.seconds <= maxSeconds + 0.001 else { return out }
                out.append(s); total += s.seconds
            }
        }
        return out
    }
}

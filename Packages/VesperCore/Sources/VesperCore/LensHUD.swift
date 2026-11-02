import Foundation

/// What the Ray-Ban Display lens shows while driving: three short lines, read at a glance.
/// Live speed and revs between laps; the lap time flashes up when you cross the line.
public struct LensHUD: Equatable, Sendable {
    public var headline: String
    public var detail: String?
    public var footnote: String?
    /// Detail colour hint: true when the news is good (a faster lap).
    public var positive: Bool

    public init(headline: String, detail: String? = nil, footnote: String? = nil, positive: Bool = false) {
        self.headline = headline; self.detail = detail; self.footnote = footnote; self.positive = positive
    }

    /// Shown while armed, before the car moves.
    public static func armed() -> LensHUD { LensHUD(headline: "VESPER ARMED", detail: "Recording starts when you do") }

    /// Shown for a few seconds after crossing the line.
    public static func lapComplete(_ lap: Lap, previousBest: Lap?, unit: SpeedUnit) -> LensHUD {
        var detail: String?
        var positive = false
        if let best = previousBest {
            let delta = lap.duration - best.duration
            positive = delta < 0
            detail = String(format: "%@%.2f %@", delta < 0 ? "−" : "+", abs(delta), delta < 0 ? "NEW BEST" : "TO BEST")
        }
        return LensHUD(headline: "L\(lap.number)  \(Format.lapTime(lap.duration))", detail: detail,
                       footnote: "TOP \(Format.speed(lap.topSpeed, unit))", positive: positive)
    }

    /// Live gauges: big speed, revs underneath, lap and best at the bottom.
    /// Values are rounded (1 mph, 100 rpm) so the lens only refreshes when a reading really moves.
    public static func live(speed: Double, rpm: Double?, unit: SpeedUnit, lap: Int, best: Lap?) -> LensHUD {
        let shownSpeed = Int(unit.convert(max(0, speed)).rounded())
        let revs = rpm.map { "\((Int(($0 / 100).rounded()) * 100).formatted(.number.grouping(.automatic))) RPM" } ?? "— RPM"
        var foot = lap > 0 ? "LAP \(lap)" : "OUT LAP"
        if let best { foot += " · BEST \(Format.lapTime(best.duration))" }
        return LensHUD(headline: "\(shownSpeed) \(unit.label)", detail: revs, footnote: foot)
    }

    /// Resting state between laps: lap number and the best so far. No running clock to stare at.
    public static func onLap(_ number: Int, best: Lap?) -> LensHUD {
        LensHUD(headline: number > 0 ? "LAP \(number)" : "OUT LAP",
                detail: best.map { "BEST \(Format.lapTime($0.duration))" })
    }

    public static func complete(best: Lap?) -> LensHUD {
        LensHUD(headline: "MISSION COMPLETE", detail: best.map { "BEST \(Format.lapTime($0.duration))" },
                footnote: "Debrief ready on your phone")
    }
}

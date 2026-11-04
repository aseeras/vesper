import Foundation

/// What the Ray-Ban Display lens shows while driving: three short lines, read at a glance.
/// Live speed between laps; the lap time flashes up when you cross the line.
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

    /// Live gauges: big speed, the lap underneath, the best lap at the bottom. No revs: the
    /// driver asked for a cleaner lens. Speed is rounded to 1 mph/kmh so the lens only
    /// refreshes when the reading really moves.
    public static func live(speed: Double, unit: SpeedUnit, lap: Int, best: Lap?) -> LensHUD {
        LensHUD(headline: speedLine(speed, unit), detail: lap > 0 ? "LAP \(lap)" : "OUT LAP",
                footnote: best.map { "BEST \(Format.lapTime($0.duration))" })
    }

    static func speedLine(_ speed: Double, _ unit: SpeedUnit) -> String {
        "\(Int(unit.convert(max(0, speed)).rounded())) \(unit.label)"
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

extension LensHUD {
    /// Grand tour gauges: speed, with trip distance and time underneath.
    public static func liveRoad(speed: Double, unit: SpeedUnit, distance: Double, elapsed: Double) -> LensHUD {
        LensHUD(headline: speedLine(speed, unit), detail: "TRIP \(Format.distance(distance, unit))",
                footnote: Format.duration(elapsed))
    }
}

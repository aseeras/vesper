import Foundation

public enum MomentKind: String, Codable, Sendable, CaseIterable {
    case launch, corner, braking, topSpeed, fastestLap

    /// Seconds of footage to keep before and after the peak.
    var window: (before: Double, after: Double) {
        switch self {
        case .launch: return (1.0, 3.0)
        case .corner: return (2.5, 2.0)
        case .braking: return (1.0, 2.5)
        case .topSpeed: return (2.0, 1.5)
        case .fastestLap: return (2.5, 1.5)
        }
    }

    var earnsSlowMotion: Bool { self == .corner || self == .topSpeed || self == .fastestLap }
}

/// Something worth putting in the film.
public struct Moment: Codable, Hashable, Sendable {
    public var kind: MomentKind
    /// Mission time of the peak.
    public var t: Double
    /// 0...1, higher is more exciting.
    public var score: Double
    public var caption: String
}

public struct EditSegment: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case intro, action, slowMotion, outro }

    public var role: Role
    public var sourceStart: Double
    public var sourceEnd: Double
    /// Playback speed: 1 is real time, 0.5 is half-speed slow motion.
    public var rate: Double
    public var caption: String?

    public var sourceDuration: Double { sourceEnd - sourceStart }
    public var outputDuration: Double { sourceDuration / rate }
}

public struct HighlightOptions: Codable, Hashable, Sendable {
    public var targetDuration: Double = 60
    public var bpm: Double = 124
    public var introDuration: Double = 4
    public var outroDuration: Double = 3
    public var slowMotion = true
    public var maxSlowMotionMoments = 3
    public var unit: SpeedUnit = .mph
    /// Mission times covered by the recorded video.
    public var videoStart: Double = 0
    public var videoEnd: Double = .infinity

    public init() {}

    var beat: Double { 60 / bpm }
}

/// The cut list for one highlight film. Times are mission times.
public struct HighlightPlan: Codable, Hashable, Sendable {
    public var segments: [EditSegment]
    public var moments: [Moment]

    public var totalDuration: Double { segments.reduce(0) { $0 + $1.outputDuration } }

    /// Which segment plays at `outputTime`, and the matching mission time.
    public func source(atOutput outputTime: Double) -> (index: Int, segment: EditSegment, missionTime: Double)? {
        var cursor = 0.0
        for (i, s) in segments.enumerated() {
            if outputTime < cursor + s.outputDuration || i == segments.count - 1 {
                let local = min(max(0, outputTime - cursor), s.outputDuration)
                return (i, s, s.sourceStart + local * s.rate)
            }
            cursor += s.outputDuration
        }
        return nil
    }

    /// Output time at which segment `index` begins.
    public func outputStart(ofSegment index: Int) -> Double {
        segments.prefix(index).reduce(0) { $0 + $1.outputDuration }
    }
}

public enum HighlightEngine {
    // MARK: Detection

    public static func detectMoments(track: TelemetryTrack, laps: [Lap], unit: SpeedUnit = .mph) -> [Moment] {
        var moments: [Moment] = []
        let g = track.gforces

        for i in peaks(g.map { abs($0.lateral) }, times: g.map(\.t), minimum: 0.5, separation: 5) {
            let v = abs(g[i].lateral)
            moments.append(Moment(kind: .corner, t: g[i].t, score: min(1, v / 1.4), caption: "LATERAL \(Format.g(v))"))
        }
        for i in peaks(g.map { -$0.longitudinal }, times: g.map(\.t), minimum: 0.5, separation: 5) {
            let v = -g[i].longitudinal
            moments.append(Moment(kind: .braking, t: g[i].t, score: 0.9 * min(1, v / 1.2), caption: "BRAKING \(Format.g(v))"))
        }
        let launches = peaks(g.map { $0.longitudinal }, times: g.map(\.t), minimum: 0.3, separation: 10)
            .filter { track.speed(at: g[$0].t - 1.5) < 8 }
        for i in launches {
            moments.append(Moment(kind: .launch, t: g[i].t, score: 0.7, caption: "LAUNCH \(Format.g(g[i].longitudinal))"))
        }

        if let top = track.fixes.max(by: { $0.speed < $1.speed }), top.speed > 0 {
            moments.append(Moment(kind: .topSpeed, t: top.t, score: 1, caption: "V-MAX \(Format.speed(top.speed, unit))"))
        }
        if let best = laps.min(by: { $0.duration < $1.duration }), laps.count > 1 || best.duration > 0 {
            moments.append(Moment(kind: .fastestLap, t: best.end, score: 0.95,
                                  caption: "FASTEST LAP \(Format.lapTime(best.duration))"))
        }
        return moments.sorted { $0.t < $1.t }
    }

    /// Local maxima above `minimum`, at most one per `separation` seconds (strongest wins).
    static func peaks(_ values: [Double], times: [Double], minimum: Double, separation: Double) -> [Int] {
        let candidates = values.indices.filter { i in
            values[i] >= minimum
                && (i == 0 || values[i] >= values[i - 1])
                && (i == values.count - 1 || values[i] > values[i + 1])
        }
        var kept: [Int] = []
        for i in candidates.sorted(by: { values[$0] > values[$1] })
        where !kept.contains(where: { abs(times[$0] - times[i]) < separation }) {
            kept.append(i)
        }
        return kept.sorted()
    }

    // MARK: Planning

    public static func plan(track: TelemetryTrack, laps: [Lap], options: HighlightOptions) -> HighlightPlan {
        let videoEnd = min(options.videoEnd, max(options.videoStart, track.duration))
        let videoStart = options.videoStart
        let moments = detectMoments(track: track, laps: laps, unit: options.unit)
            .filter { $0.t >= videoStart && $0.t <= videoEnd }
        let beat = options.beat
        let budget = max(beat * 4, options.targetDuration - options.introDuration - options.outroDuration)

        // Pick the most exciting, non-overlapping windows that fit the budget.
        struct Pick { var moment: Moment; var start: Double; var end: Double; var slow: Bool }
        var picks: [Pick] = []
        var used = 0.0
        var slowCount = 0
        for m in moments.sorted(by: { $0.score > $1.score }) {
            let w = m.kind.window
            let start = max(videoStart, m.t - w.before)
            let end = min(videoEnd, m.t + w.after)
            guard end - start >= 1 else { continue }
            if picks.contains(where: { start < $0.end + 0.5 && end > $0.start - 0.5 }) { continue }
            let slow = options.slowMotion && m.kind.earnsSlowMotion && m.score >= 0.75
                && slowCount < options.maxSlowMotionMoments
            let cost = (end - start) + (slow ? 1 : 0)
            guard used + cost <= budget else { continue }
            picks.append(Pick(moment: m, start: start, end: end, slow: slow))
            used += cost
            if slow { slowCount += 1 }
        }

        // Nothing dramatic happened: sample the drive evenly instead.
        if picks.isEmpty, videoEnd - videoStart > 2 {
            let clip = beat * 8
            let count = max(1, min(Int(budget / clip), Int((videoEnd - videoStart) / clip)))
            let gap = (videoEnd - videoStart - clip * Double(count)) / Double(count + 1)
            for k in 0..<count {
                let s = videoStart + gap + Double(k) * (clip + gap)
                let m = Moment(kind: .corner, t: s + clip / 2, score: 0, caption: "")
                picks.append(Pick(moment: m, start: s, end: min(videoEnd, s + clip), slow: false))
            }
        }

        picks.sort { $0.start < $1.start }

        // Snap each clip to whole beats so cuts land on the music.
        for i in picks.indices {
            let p = picks[i]
            let extra = p.slow ? 1.0 : 0
            let length = (p.end - p.start) + extra
            let beats = max(2, (length / beat).rounded())
            let ceiling = i + 1 < picks.count ? picks[i + 1].start - 0.25 : videoEnd
            var end = p.start + beats * beat - extra
            if end > ceiling { end = p.start + (((ceiling - p.start + extra) / beat).rounded(.down)) * beat - extra }
            picks[i].end = max(p.start + 0.5, min(end, ceiling))
        }

        var segments: [EditSegment] = []
        if let first = picks.first {
            let start = max(videoStart, first.start - options.introDuration)
            if first.start - start > 0.5 {
                segments.append(EditSegment(role: .intro, sourceStart: start, sourceEnd: first.start, rate: 1))
            }
        }
        for p in picks {
            let caption = p.moment.caption.isEmpty ? nil : p.moment.caption
            if p.slow, p.moment.t - 0.5 > p.start, p.moment.t + 0.5 < p.end {
                segments.append(EditSegment(role: .action, sourceStart: p.start, sourceEnd: p.moment.t - 0.5, rate: 1, caption: caption))
                segments.append(EditSegment(role: .slowMotion, sourceStart: p.moment.t - 0.5, sourceEnd: p.moment.t + 0.5, rate: 0.5, caption: caption))
                segments.append(EditSegment(role: .action, sourceStart: p.moment.t + 0.5, sourceEnd: p.end, rate: 1, caption: caption))
            } else {
                segments.append(EditSegment(role: .action, sourceStart: p.start, sourceEnd: p.end, rate: 1, caption: caption))
            }
        }
        if let last = picks.last {
            let end = min(videoEnd, last.end + options.outroDuration)
            if end - last.end > 0.5 {
                segments.append(EditSegment(role: .outro, sourceStart: last.end, sourceEnd: end, rate: 1))
            }
        }
        return HighlightPlan(segments: segments, moments: picks.map(\.moment))
    }
}

import Foundation

/// A start/finish line: a segment across the track, perpendicular to the direction of travel.
public struct Gate: Codable, Hashable, Sendable {
    public var center: GeoPoint
    /// Direction of travel across the line, degrees clockwise from north.
    public var heading: Double
    /// Width of the line in metres.
    public var width: Double

    public init(center: GeoPoint, heading: Double, width: Double = 40) {
        self.center = center; self.heading = heading; self.width = width
    }

    /// Time at which the car crossed this gate going forward between two fixes, if it did.
    public func crossing(from a: GPSFix, to b: GPSFix) -> Double? {
        let projection = LocalProjection(origin: center)
        let pa = projection.project(a.point), pb = projection.project(b.point)
        let forward = Vec2.heading(heading)
        let across = Vec2(x: forward.y, y: -forward.x)
        let sa = pa.dot(forward), sb = pb.dot(forward)
        guard sa < 0, sb >= 0 else { return nil }
        let f = -sa / (sb - sa)
        let hit = pa + (pb - pa) * f
        guard abs(hit.dot(across)) <= width / 2 else { return nil }
        return a.t + (b.t - a.t) * f
    }
}

public struct Lap: Codable, Hashable, Sendable, Identifiable {
    public var id: Int { number }
    public var number: Int
    public var start: Double
    public var end: Double
    /// Highest speed in the lap, m/s.
    public var topSpeed: Double

    public var duration: Double { end - start }
}

public enum LapDetector {
    /// Every forward crossing of the gate, ignoring re-crossings closer than `minLapTime`.
    public static func crossings(of gate: Gate, in fixes: [GPSFix], minLapTime: Double = 20) -> [Double] {
        var times: [Double] = []
        for (a, b) in zip(fixes, fixes.dropFirst()) {
            guard let t = gate.crossing(from: a, to: b) else { continue }
            if let last = times.last, t - last < minLapTime { continue }
            times.append(t)
        }
        return times
    }

    public static func laps(gate: Gate, fixes: [GPSFix], minLapTime: Double = 20) -> [Lap] {
        let times = crossings(of: gate, in: fixes, minLapTime: minLapTime)
        return zip(times, times.dropFirst()).enumerated().map { i, pair in
            let top = fixes.filter { $0.t >= pair.0 && $0.t <= pair.1 }.map(\.speed).max() ?? 0
            return Lap(number: i + 1, start: pair.0, end: pair.1, topSpeed: top)
        }
    }

    /// Guesses a start/finish line when none was set: the first point where the car is at
    /// racing speed, kept only if the car comes back through it at least once.
    public static func autoGate(for fixes: [GPSFix], minLapTime: Double = 20) -> Gate? {
        guard fixes.count > 3 else { return nil }
        let threshold = max(8, 0.5 * (fixes.map(\.speed).max() ?? 0))
        guard let i = fixes.indices.dropFirst().dropLast().first(where: { fixes[$0].speed >= threshold }) else { return nil }
        let fix = fixes[i]
        let heading: Double
        if fix.course >= 0 {
            heading = fix.course
        } else {
            let p = LocalProjection(origin: fix.point)
            heading = (p.project(fixes[i + 1].point) - p.project(fixes[i - 1].point)).heading
        }
        // Nudge the line half a metre back so the first pass registers as a crossing.
        let p = LocalProjection(origin: fix.point)
        let center = p.unproject(Vec2.heading(heading) * -0.5)
        let gate = Gate(center: center, heading: heading)
        return crossings(of: gate, in: fixes, minLapTime: minLapTime).count >= 2 ? gate : nil
    }
}

/// Lap timing while driving, for voice call-outs.
public struct LiveLapTimer: Sendable {
    public var gate: Gate
    public var minLapTime: Double
    public private(set) var lastCrossing: Double?
    public private(set) var completed: [Lap] = []
    private var previous: GPSFix?
    private var topSpeed: Double = 0

    public init(gate: Gate, minLapTime: Double = 20) {
        self.gate = gate; self.minLapTime = minLapTime
    }

    public var bestLap: Lap? { completed.min { $0.duration < $1.duration } }

    /// Feed a fix. Returns a lap when one was just completed.
    public mutating func add(_ fix: GPSFix) -> Lap? {
        defer { previous = fix }
        topSpeed = max(topSpeed, fix.speed)
        guard let prev = previous, let t = gate.crossing(from: prev, to: fix) else { return nil }
        if let last = lastCrossing, t - last < minLapTime { return nil }
        defer { lastCrossing = t; topSpeed = fix.speed }
        guard let last = lastCrossing else { return nil }
        let lap = Lap(number: completed.count + 1, start: last, end: t, topSpeed: topSpeed)
        completed.append(lap)
        return lap
    }
}

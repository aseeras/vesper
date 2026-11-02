import Foundation

/// One GPS reading. `t` is seconds since the mission clock started.
public struct GPSFix: Codable, Hashable, Sendable {
    public var t: Double
    public var point: GeoPoint
    /// Metres per second, negative when unknown.
    public var speed: Double
    /// Degrees clockwise from north, negative when unknown.
    public var course: Double
    /// Horizontal accuracy in metres.
    public var accuracy: Double

    public init(t: Double, point: GeoPoint, speed: Double, course: Double = -1, accuracy: Double = 5) {
        self.t = t; self.point = point; self.speed = speed; self.course = course; self.accuracy = accuracy
    }
}

/// Car-frame acceleration in g. Lateral is positive to the left, longitudinal positive when accelerating.
public struct GForceSample: Codable, Hashable, Sendable {
    public var t: Double
    public var lateral: Double
    public var longitudinal: Double

    public init(t: Double, lateral: Double, longitudinal: Double) {
        self.t = t; self.lateral = lateral; self.longitudinal = longitudinal
    }

    public var combined: Double { (lateral * lateral + longitudinal * longitudinal).squareRoot() }
}

/// Engine speed estimated from the cabin microphone.
public struct RPMSample: Codable, Hashable, Sendable {
    public var t: Double
    public var rpm: Double
    public init(t: Double, rpm: Double) { self.t = t; self.rpm = rpm }
}

/// Everything recorded during a mission, on one clock.
public struct TelemetryTrack: Codable, Sendable {
    public var fixes: [GPSFix]
    public var gforces: [GForceSample]
    public var rpm: [RPMSample]

    public init(fixes: [GPSFix] = [], gforces: [GForceSample] = [], rpm: [RPMSample] = []) {
        self.fixes = fixes; self.gforces = gforces; self.rpm = rpm
    }

    public var duration: Double {
        max(fixes.last?.t ?? 0, gforces.last?.t ?? 0, rpm.last?.t ?? 0)
    }

    /// Distance driven in metres.
    public var distance: Double {
        zip(fixes, fixes.dropFirst()).reduce(0) { total, pair in
            let p = LocalProjection(origin: pair.0.point)
            return total + p.project(pair.1.point).length
        }
    }

    public var maxSpeed: Double { fixes.map(\.speed).max() ?? 0 }
    public var peakLateralG: Double { gforces.map { abs($0.lateral) }.max() ?? 0 }
    public var peakBrakingG: Double { gforces.map { -$0.longitudinal }.max() ?? 0 }

    /// Speed in m/s at time `t`, linearly interpolated.
    public func speed(at t: Double) -> Double {
        interpolate(fixes, at: t, time: \.t) { a, b, f in a.speed + (b.speed - a.speed) * f }.map { max(0, $0) } ?? 0
    }

    public func gforce(at t: Double) -> GForceSample {
        interpolate(gforces, at: t, time: \.t) { a, b, f in
            GForceSample(t: t,
                         lateral: a.lateral + (b.lateral - a.lateral) * f,
                         longitudinal: a.longitudinal + (b.longitudinal - a.longitudinal) * f)
        } ?? GForceSample(t: t, lateral: 0, longitudinal: 0)
    }

    public func rpm(at t: Double) -> Double? {
        interpolate(rpm, at: t, time: \.t) { a, b, f in a.rpm + (b.rpm - a.rpm) * f }
    }
}

/// Index of the last element whose time is <= t, or nil when t is before the first element.
func lastIndex<T>(in items: [T], atOrBefore t: Double, time: (T) -> Double) -> Int? {
    var lo = 0, hi = items.count - 1, found: Int? = nil
    while lo <= hi {
        let mid = (lo + hi) / 2
        if time(items[mid]) <= t { found = mid; lo = mid + 1 } else { hi = mid - 1 }
    }
    return found
}

func interpolate<T, R>(_ items: [T], at t: Double, time: (T) -> Double, blend: (T, T, Double) -> R) -> R? {
    guard let first = items.first, let last = items.last else { return nil }
    if t <= time(first) { return blend(first, first, 0) }
    if t >= time(last) { return blend(last, last, 0) }
    guard let i = lastIndex(in: items, atOrBefore: t, time: time) else { return nil }
    let a = items[i], b = items[min(i + 1, items.count - 1)]
    let span = time(b) - time(a)
    return blend(a, b, span > 0 ? (t - time(a)) / span : 0)
}

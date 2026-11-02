import Foundation
@testable import VesperCore

/// A synthetic circuit: an oval-ish loop driven at varying speed, sampled like an iPhone GPS.
enum Fixtures {
    static let origin = GeoPoint(latitude: 51.5560, longitude: -1.0000)

    /// Circle of `radius` metres driven anticlockwise at `speed` m/s for `laps` laps, sampled at `hz`.
    static func circle(radius: Double = 200, speed: Double = 30, laps: Int = 4, hz: Double = 5,
                       leadIn: Double = 10) -> [GPSFix] {
        let projection = LocalProjection(origin: origin)
        let lapTime = 2 * .pi * radius / speed
        var fixes: [GPSFix] = []
        // Parked for a while first.
        var t = 0.0
        while t < leadIn {
            fixes.append(GPSFix(t: t, point: projection.unproject(Vec2(x: radius, y: 0)), speed: 0))
            t += 1 / hz
        }
        let total = lapTime * Double(laps)
        var s = 0.0
        while s <= total {
            let angle = s / lapTime * 2 * .pi
            let p = Vec2(x: radius * cos(angle), y: radius * sin(angle))
            // Anticlockwise travel direction is +90° from the radius vector.
            let dir = Vec2(x: -sin(angle), y: cos(angle))
            fixes.append(GPSFix(t: leadIn + s, point: projection.unproject(p), speed: speed, course: dir.heading))
            s += 1 / hz
        }
        return fixes
    }

    /// G-forces with sharp spikes at the given times.
    static func gforces(duration: Double, spikes: [(t: Double, lateral: Double, longitudinal: Double)], hz: Double = 20) -> [GForceSample] {
        var out: [GForceSample] = []
        var t = 0.0
        while t <= duration {
            var lat = 0.1, lon = 0.0
            for s in spikes {
                let k = exp(-pow((t - s.t) / 0.6, 2))
                lat += s.lateral * k
                lon += s.longitudinal * k
            }
            out.append(GForceSample(t: t, lateral: lat, longitudinal: lon))
            t += 1 / hz
        }
        return out
    }
}

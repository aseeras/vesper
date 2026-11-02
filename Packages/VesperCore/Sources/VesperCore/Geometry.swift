import Foundation

/// A latitude/longitude pair in degrees.
public struct GeoPoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A 2D vector in local metres: x points east, y points north.
public struct Vec2: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) { self.x = x; self.y = y }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x - b.x, y: a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(x: a.x * s, y: a.y * s) }
    public func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    public var length: Double { (x * x + y * y).squareRoot() }

    /// Unit vector for a compass heading (degrees clockwise from north).
    public static func heading(_ degrees: Double) -> Vec2 {
        let r = degrees * .pi / 180
        return Vec2(x: sin(r), y: cos(r))
    }

    /// Compass heading of this vector, 0..<360.
    public var heading: Double {
        let d = atan2(x, y) * 180 / .pi
        return d < 0 ? d + 360 : d
    }
}

/// A 3D vector, used for raw motion sensor values in the phone's frame.
public struct Vec3: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }

    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(x: a.x * s, y: a.y * s, z: a.z * s) }
    public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    public var length: Double { dot(self).squareRoot() }
    public var normalized: Vec3 { let l = length; return l > 0 ? self * (1 / l) : self }
}

/// Flat-earth projection around an origin. Accurate to centimetres over a race circuit.
public struct LocalProjection: Sendable {
    public let origin: GeoPoint
    private let metresPerDegLat: Double
    private let metresPerDegLon: Double

    public init(origin: GeoPoint) {
        self.origin = origin
        let lat = origin.latitude * .pi / 180
        metresPerDegLat = 111_132.92 - 559.82 * cos(2 * lat) + 1.175 * cos(4 * lat)
        metresPerDegLon = 111_412.84 * cos(lat) - 93.5 * cos(3 * lat)
    }

    public func project(_ p: GeoPoint) -> Vec2 {
        Vec2(x: (p.longitude - origin.longitude) * metresPerDegLon,
             y: (p.latitude - origin.latitude) * metresPerDegLat)
    }

    public func unproject(_ v: Vec2) -> GeoPoint {
        GeoPoint(latitude: origin.latitude + v.y / metresPerDegLat,
                 longitude: origin.longitude + v.x / metresPerDegLon)
    }
}

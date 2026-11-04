import Foundation

/// A fixed enforcement camera from OpenStreetMap.
public struct EnforcementCamera: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case speed, redLight }

    public var id: Int64
    public var kind: Kind
    public var point: GeoPoint
    /// Posted limit in metres per second, when OSM records it.
    public var limit: Double?

    public init(id: Int64, kind: Kind, point: GeoPoint, limit: Double? = nil) {
        self.id = id; self.kind = kind; self.point = point; self.limit = limit
    }
}

/// Fetches speed and red-light cameras around a point from OpenStreetMap's Overpass API.
/// Data © OpenStreetMap contributors, ODbL. Coverage is community-mapped, so it is never complete.
public enum CameraSource {
    public static let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    /// Overpass QL for cameras within `radius` metres: tagged camera nodes, plus enforcement
    /// relations (whose `device` member is the camera) for speed and traffic-signal enforcement.
    public static func query(around p: GeoPoint, radius: Double) -> String {
        let a = "around:\(Int(radius)),\(p.latitude),\(p.longitude)"
        return """
        [out:json][timeout:25];
        (
          node["highway"="speed_camera"](\(a));
          node["enforcement"~"^(maxspeed|traffic_signals)$"](\(a));
          relation["type"="enforcement"]["enforcement"~"^(maxspeed|traffic_signals)$"](\(a));
        );
        out body;
        >;
        out skel qt;
        """
    }

    /// Parses an Overpass JSON response.
    public static func parse(_ data: Data) throws -> [EnforcementCamera] {
        struct Member: Decodable { var type: String; var ref: Int64; var role: String }
        struct Element: Decodable {
            var type: String
            var id: Int64
            var lat: Double?
            var lon: Double?
            var tags: [String: String]?
            var members: [Member]?
        }
        struct Response: Decodable { var elements: [Element] }

        let elements = try JSONDecoder().decode(Response.self, from: data).elements
        var nodes: [Int64: GeoPoint] = [:]
        for e in elements where e.type == "node" {
            if let lat = e.lat, let lon = e.lon { nodes[e.id] = GeoPoint(latitude: lat, longitude: lon) }
        }

        var cameras: [Int64: EnforcementCamera] = [:]
        for e in elements {
            let tags = e.tags ?? [:]
            let enforcement = tags["enforcement"]
            let kind: EnforcementCamera.Kind?
            if enforcement == "traffic_signals" { kind = .redLight }
            else if enforcement == "maxspeed" || tags["highway"] == "speed_camera" { kind = .speed }
            else { kind = nil }
            guard let kind else { continue }
            let limit = tags["maxspeed"].flatMap(parseSpeed)

            switch e.type {
            case "node":
                guard let p = nodes[e.id] else { continue }
                cameras[e.id] = EnforcementCamera(id: e.id, kind: kind, point: p, limit: limit)
            case "relation":
                // The camera is the "device"; fall back to the enforced spot.
                let members = e.members ?? []
                let ref = members.first { $0.type == "node" && $0.role == "device" }
                    ?? members.first { $0.type == "node" && ($0.role == "from" || $0.role == "force") }
                guard let ref, let p = nodes[ref.ref] else { continue }
                // A relation describes its device node better than the node's own tags.
                cameras[ref.ref] = EnforcementCamera(id: ref.ref, kind: kind, point: p, limit: limit ?? cameras[ref.ref]?.limit)
            default:
                continue
            }
        }
        return cameras.values.sorted { $0.id < $1.id }
    }

    /// "50", "50 mph", "80 km/h" → metres per second. Numbers alone are km/h, as in OSM.
    static func parseSpeed(_ s: String) -> Double? {
        let t = s.lowercased().trimmingCharacters(in: .whitespaces)
        let digits = t.prefix { $0.isNumber || $0 == "." }
        guard let v = Double(digits), v > 0 else { return nil }
        return t.contains("mph") ? v * 0.44704 : v / 3.6
    }
}

/// Decides when to warn about a camera: once per pass, when it's close and roughly straight
/// ahead along the direction of travel. Cameras behind or off to the side stay quiet.
public struct CameraAlerter: Sendable {
    /// Warn this many seconds before reaching the camera, within the distance bounds below.
    public var leadTime: Double = 15
    public var minDistance: Double = 250
    public var maxDistance: Double = 800
    /// How far off the direction of travel (degrees) a camera may be and still count as ahead.
    public var coneHalfAngle: Double = 30
    /// A camera can warn again once you're this far from it.
    public var rearmDistance: Double = 1_500

    private var warned: Set<Int64> = []

    public init() {}

    public struct Alert: Equatable, Sendable {
        public var camera: EnforcementCamera
        public var distance: Double
    }

    /// The camera to warn about now, if any. Needs a valid course from GPS.
    public mutating func update(fix: GPSFix, cameras: [EnforcementCamera]) -> Alert? {
        let projection = LocalProjection(origin: fix.point)
        var best: Alert?
        let trigger = min(maxDistance, max(minDistance, max(0, fix.speed) * leadTime))
        for camera in cameras {
            let offset = projection.project(camera.point)
            let distance = offset.length
            if distance > rearmDistance { warned.remove(camera.id); continue }
            guard fix.course >= 0, fix.speed > 2, distance <= trigger, !warned.contains(camera.id) else { continue }
            var off = abs(offset.heading - fix.course).truncatingRemainder(dividingBy: 360)
            if off > 180 { off = 360 - off }
            guard off <= coneHalfAngle else { continue }
            if best == nil || distance < best!.distance { best = Alert(camera: camera, distance: distance) }
        }
        if let best { warned.insert(best.camera.id) }
        return best
    }
}

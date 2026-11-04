import Foundation
import VesperCore

/// Speed and red-light camera warnings for a drive.
///
/// Camera locations come from OpenStreetMap (community-mapped, so coverage varies by area)
/// and are fetched for the area around you, again whenever you've driven well away from it.
/// Each camera is announced once per pass, on the lens and by voice, when it's just ahead.
@MainActor
final class CameraWatch {
    private(set) var cameras: [EnforcementCamera] = []
    private var alerter = CameraAlerter()
    private var fetchedAround: GeoPoint?
    private var fetching = false
    private var lastFailure: Date?
    /// Fetch this far around you, and again once you're more than `refetchDistance` from that spot.
    private let radius: Double = 20_000
    private let refetchDistance: Double = 12_000

    /// Feed every GPS fix; returns a camera to warn about now.
    func update(fix: GPSFix) -> CameraAlerter.Alert? {
        refreshIfNeeded(around: fix.point)
        return alerter.update(fix: fix, cameras: cameras)
    }

    private func refreshIfNeeded(around point: GeoPoint) {
        guard !fetching else { return }
        if let lastFailure, Date().timeIntervalSince(lastFailure) < 120 { return }
        if let fetchedAround, LocalProjection(origin: fetchedAround).project(point).length < refetchDistance { return }
        fetching = true
        Task {
            defer { fetching = false }
            do {
                cameras = try await Self.fetch(around: point, radius: radius)
                fetchedAround = point
                lastFailure = nil
            } catch {
                print("Camera fetch failed: \(error)")
                lastFailure = Date()
            }
        }
    }

    nonisolated private static func fetch(around point: GeoPoint, radius: Double) async throws -> [EnforcementCamera] {
        var request = URLRequest(url: CameraSource.endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Vesper/1.0 (personal iOS driving app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let query = CameraSource.query(around: point, radius: radius)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        request.httpBody = Data("data=\(encoded)".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try CameraSource.parse(data)
    }
}

import Foundation
import VesperCore

/// One drive, stored in its own folder under Documents/Missions.
struct Mission: Codable, Identifiable, Hashable {
    var id = UUID()
    var codename: String
    var trackName: String
    var car: String
    /// The car's engine and redline when the drive was recorded. Optional for older missions.
    var carCylinders: Int?
    var carRedline: Double?
    /// Track day or grand tour. Optional so missions saved before modes existed still load.
    var driveMode: DriveMode?
    var date: Date
    var unit: SpeedUnit
    /// Mission time (seconds) of the first video frame and first audio sample.
    var videoStart: Double?
    var audioStart: Double?
    var gate: Gate?
    var laps: [Lap] = []
    var hasVideo = false
    var hasEngineAudio = false
    var hasFilm = false

    var bestLap: Lap? { laps.min { $0.duration < $1.duration } }
    var mode: DriveMode { driveMode ?? .track }
}

@MainActor
@Observable
final class MissionStore {
    private(set) var missions: [Mission] = []

    nonisolated static let root: URL = {
        let url = URL.documentsDirectory.appending(path: "Missions", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    nonisolated static func folder(for id: UUID) -> URL {
        let url = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated static func videoURL(_ id: UUID) -> URL { folder(for: id).appending(path: "glasses.mp4") }
    nonisolated static func audioURL(_ id: UUID) -> URL { folder(for: id).appending(path: "engine.m4a") }
    nonisolated static func filmURL(_ id: UUID) -> URL { folder(for: id).appending(path: "film.mp4") }
    nonisolated static func telemetryURL(_ id: UUID) -> URL { folder(for: id).appending(path: "telemetry.json") }
    nonisolated static func missionURL(_ id: UUID) -> URL { folder(for: id).appending(path: "mission.json") }

    init() { reload() }

    func reload() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? []
        missions = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appending(path: "mission.json")) else { return nil }
            return try? JSONDecoder().decode(Mission.self, from: data)
        }.sorted { $0.date > $1.date }
    }

    func save(_ mission: Mission, telemetry: TelemetryTrack? = nil) {
        let enc = JSONEncoder()
        if let telemetry, let data = try? enc.encode(telemetry) {
            try? data.write(to: Self.telemetryURL(mission.id), options: .atomic)
        }
        if let data = try? enc.encode(mission) {
            try? data.write(to: Self.missionURL(mission.id), options: .atomic)
        }
        reload()
    }

    func telemetry(for mission: Mission) -> TelemetryTrack {
        guard let data = try? Data(contentsOf: Self.telemetryURL(mission.id)),
              let t = try? JSONDecoder().decode(TelemetryTrack.self, from: data) else { return TelemetryTrack() }
        return t
    }

    func delete(_ mission: Mission) {
        try? FileManager.default.removeItem(at: Self.folder(for: mission.id))
        reload()
    }
}

import Foundation
import Observation
import VesperCore

/// Shared state for the phone UI and the CarPlay screen.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let glasses = GlassesManager()
    let store = MissionStore()
    let settings = DriverSettings()
    /// The mission in progress, whichever screen started it.
    var activeMission: MissionController?
    /// Set when a mission finishes so the phone can jump to its debrief.
    var finishedMissionID: UUID?

    func arm(trackName: String, mode: DriveMode) async {
        guard activeMission == nil else { return }
        settings.lastMode = mode
        let c = MissionController(glasses: glasses, store: store, settings: settings)
        activeMission = c
        let lastSameMode = store.missions.first { $0.mode == mode }?.trackName ?? ""
        await c.arm(trackName: trackName.isEmpty ? lastSameMode : trackName, mode: mode, gate: nil)
    }

    func close(finished: UUID?) {
        activeMission = nil
        finishedMissionID = finished
        store.reload()
    }
}

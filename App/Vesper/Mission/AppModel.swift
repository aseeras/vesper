import Foundation
import Observation

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

    func arm(trackName: String) async {
        guard activeMission == nil else { return }
        let c = MissionController(glasses: glasses, store: store, settings: settings)
        activeMission = c
        await c.arm(trackName: trackName.isEmpty ? (store.missions.first?.trackName ?? "") : trackName, gate: nil)
    }

    func close(finished: UUID?) {
        activeMission = nil
        finishedMissionID = finished
        store.reload()
    }
}

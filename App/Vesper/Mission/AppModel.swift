import Foundation
import Observation
import VesperCore

/// Shared state for the phone UI and the CarPlay screen.
@MainActor
@Observable
final class AppModel {
    /// Configures the Meta toolkit first, whichever scene (phone or CarPlay) asks for the model.
    static let shared: AppModel = {
        GlassesManager.configureAtLaunch()
        return AppModel()
    }()

    let glasses = GlassesManager()
    let store = MissionStore()
    let settings = DriverSettings()
    /// The mission in progress, whichever screen started it.
    var activeMission: MissionController?
    /// Set when a mission finishes so the phone can jump to its debrief.
    var finishedMissionID: UUID?

    private let announcer = Announcer()

    init() {
        let settings = self.settings
        glasses.lensEnabled = { settings.lensDisplay }
        glasses.voiceEnabled = { settings.voiceCommands }
        glasses.welcomeLine = {
            settings.voiceCommands ? "\(settings.car) \u{00B7} Say \u{201C}Vesper, track day\u{201D}" : "Ready when you are"
        }
        glasses.onHeard = { [weak self] text in self?.heard(text) }
        glasses.onVoiceLaunch = { [weak self] in self?.voiceLaunched() }
    }

    // MARK: Voice commands

    /// "Hey Meta, start Vesper": the app is open, so say what it can do next.
    private func voiceLaunched() {
        glasses.wake()
        if let m = activeMission, m.phase != .idle { return }
        speak("Ready. \(settings.car).")
    }

    private func heard(_ text: String) {
        // Our own spoken replies come out of the glasses' speakers; don't act on them.
        guard settings.voiceCommands, !announcer.isSpeaking,
              let command = VoiceCommandParser.parse(text, cars: settings.cars.map(\.name)) else { return }
        perform(command)
    }

    func perform(_ command: VoiceCommand) {
        // A finished drive is waiting on the phone or CarPlay "Done"; voice can move past it.
        if let m = activeMission, case .done(let id) = m.phase { close(finished: id) }

        switch command {
        case .start(let mode):
            guard activeMission == nil else { speak("Already armed."); return }
            Task { await arm(trackName: "", mode: mode ?? settings.lastMode) }
        case .end:
            guard let m = activeMission else { speak("No mission running."); return }
            switch m.phase {
            case .rolling: m.finishNow()
            case .idle, .armed: standDown(m)
            default: break
            }
        case .standDown:
            guard let m = activeMission else { return }
            if m.phase == .idle || m.phase == .armed { standDown(m) } else { speak("Still recording.") }
        case .nextCar:
            let cars = settings.cars
            let i = cars.firstIndex { $0.id == settings.activeCarID } ?? 0
            choose(car: (i + 1) % cars.count)
        case .selectCar(let i):
            choose(car: i)
        }
    }

    private func standDown(_ m: MissionController) {
        m.abort()
        close(finished: nil)
        speak("Standing down.")
    }

    private func choose(car index: Int) {
        guard settings.cars.indices.contains(index) else { return }
        guard activeMission == nil else { speak("Change cars before you arm."); return }
        settings.activeCarID = settings.cars[index].id
        speak("\(settings.car) selected.")
        glasses.lens.show(LensHUD(headline: settings.car.uppercased(), detail: "Selected",
                                  footnote: "Say \u{201C}Vesper, track day\u{201D}"), hold: 4)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.activeMission == nil else { return }
            self.glasses.wake()
        }
    }

    private func speak(_ text: String) {
        announcer.enabled = settings.voiceCallouts
        announcer.say(text)
    }

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

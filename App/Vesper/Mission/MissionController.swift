import Foundation
import Observation
import UIKit
import VesperCore

/// Runs a drive from "armed in the paddock" to "debrief ready", hands-free.
///
/// Armed: glasses camera, GPS, motion and mic are live but nothing is saved.
/// Rolling: once the car holds speed, video and engine audio are recorded and laps are called out.
/// Finished: after the car has been parked a while, everything is saved and the film can be made.
@MainActor
@Observable
final class MissionController {
    enum Phase: Equatable { case idle, armed, rolling, saving, done(UUID) }

    private(set) var phase: Phase = .idle
    private(set) var speed: Double = 0
    private(set) var gforce = GForceSample(t: 0, lateral: 0, longitudinal: 0)
    private(set) var rpm: Double?
    private(set) var currentLapStart: Double?
    private(set) var lastLap: Lap?
    private(set) var bestLap: Lap?
    private(set) var lapCount = 0
    private(set) var missionTime: Double = 0
    private(set) var error: String?

    let glasses: GlassesManager
    private let store: MissionStore
    private let settings: DriverSettings
    private let announcer = Announcer()
    private let telemetry = TelemetryRecorder()
    private let recorder = FrameRecorder()
    private var engineAudio: EngineAudio?
    private var auto = AutoRecordController()
    private var lapTimer: LiveLapTimer?
    private var mission: Mission?
    private var startUptime: TimeInterval = 0
    private var clock: Timer?
    private let frameGate = FrameGate()
    private var recordingFrames: Bool {
        get { frameGate.isOpen }
        set { frameGate.isOpen = newValue }
    }
    private var fixesSinceRolling: [GPSFix] = []

    init(glasses: GlassesManager, store: MissionStore, settings: DriverSettings) {
        self.glasses = glasses
        self.store = store
        self.settings = settings
    }

    /// Safety interlock: the screen only accepts input when the car is (nearly) stopped.
    var isStationary: Bool { speed < 10 / 3.6 }

    func arm(trackName: String, gate: Gate?) async {
        guard phase == .idle else { return }
        error = nil
        announcer.enabled = settings.voiceCallouts
        startUptime = ProcessInfo.processInfo.systemUptime
        mission = Mission(codename: Format.codename(for: .now), trackName: trackName.isEmpty ? "Unnamed circuit" : trackName,
                          car: settings.car, date: .now, unit: settings.unit, gate: gate)
        auto = AutoRecordController(policy: settings.policy)
        lapTimer = gate.map { LiveLapTimer(gate: $0) }
        lapCount = 0; lastLap = nil; bestLap = nil; currentLapStart = nil; fixesSinceRolling = []
        UIApplication.shared.isIdleTimerDisabled = true

        do { try EngineAudio.configureSession() } catch { self.error = "Audio: \(error.localizedDescription)" }
        let audio = EngineAudio(cylinders: settings.cylinders)
        audio.onRPM = { [weak self] in self?.rpm = $0 }
        do { try audio.startMonitoring(missionStartUptime: startUptime) } catch { self.error = "Microphone unavailable" }
        engineAudio = audio

        telemetry.onFix = { [weak self] fix in Task { @MainActor in self?.handle(fix) } }
        telemetry.onGForce = { [weak self] in self?.gforce = $0 }
        telemetry.requestPermission()
        telemetry.start(missionStartUptime: startUptime)

        let recorder = self.recorder
        let gate = self.frameGate
        let latency = settings.glassesLatency
        glasses.onFrame = { sample, uptime in
            guard gate.isOpen else { return }
            recorder.append(sample, uptime: uptime - latency)
        }
        glasses.setPreview(enabled: true)
        await glasses.start(lensDisplay: settings.lensDisplay)
        glasses.lens.show(.armed())

        clock = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.missionTime = ProcessInfo.processInfo.systemUptime - self.startUptime
            }
        }
        phase = .armed
        announcer.say("Vesper armed. Recording begins when you do.")
    }

    /// Driver pressed the big button in the paddock.
    func startNow() { if let e = auto.forceStart() { react(to: e) } }
    func finishNow() { if let e = auto.forceFinish() { react(to: e) } }

    func abort() {
        recordingFrames = false
        clock?.invalidate()
        glasses.stop()
        _ = telemetry.stop()
        _ = engineAudio?.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        if let mission { try? FileManager.default.removeItem(at: MissionStore.folder(for: mission.id)) }
        mission = nil
        phase = .idle
    }

    func reset() { phase = .idle }

    private func handle(_ fix: GPSFix) {
        speed = max(0, fix.speed)
        if let e = auto.update(speed: speed, at: fix.t) { react(to: e) }
        guard phase == .rolling else { return }
        fixesSinceRolling.append(fix)

        // No start line set: work one out once we've seen enough of the circuit.
        if lapTimer == nil, fixesSinceRolling.count % 25 == 0, let gate = LapDetector.autoGate(for: fixesSinceRolling) {
            var timer = LiveLapTimer(gate: gate)
            for f in fixesSinceRolling { _ = timer.add(f) }
            lapTimer = timer
            mission?.gate = gate
            currentLapStart = timer.lastCrossing
        }
        guard var timer = lapTimer else { return }
        let lap = timer.add(fix)
        if currentLapStart == nil { currentLapStart = timer.lastCrossing }
        lapTimer = timer
        if let lap { announce(lap, best: timer.bestLap) }
    }

    private func announce(_ lap: Lap, best: Lap?) {
        lastLap = lap
        lapCount = lap.number
        currentLapStart = lap.end
        let isBest = best?.number == lap.number && lap.number > 1
        glasses.lens.show(.lapComplete(lap, previousBest: bestLap, unit: settings.unit),
                          revertTo: .onLap(lap.number + 1, best: best))
        bestLap = best
        var line = "Lap \(lap.number). \(Format.spokenLapTime(lap.duration))."
        if isBest { line += " Fastest lap." }
        announcer.say(line)
    }

    private func react(to event: AutoRecordEvent) {
        switch event {
        case .startRecording:
            guard let mission else { return }
            recorder.start(url: MissionStore.videoURL(mission.id))
            recordingFrames = true
            glasses.setPreview(enabled: false)
            try? engineAudio?.startRecording(to: MissionStore.audioURL(mission.id))
            phase = .rolling
            glasses.lens.show(.onLap(0, best: nil))
            announcer.say("Rolling. Good hunting.")
        case .finishMission:
            Task { await finish() }
        }
    }

    private func finish() async {
        guard var mission, phase == .rolling || phase == .armed else { return }
        phase = .saving
        recordingFrames = false
        clock?.invalidate()
        glasses.lens.show(.complete(best: bestLap))
        try? await Task.sleep(for: .seconds(1))
        glasses.stop()
        let videoURL = await recorder.finish()
        let videoUptime = recorder.startUptime
        var track = telemetry.stop()
        track.rpm = engineAudio?.stop() ?? []
        let audioUptime = engineAudio?.recordingStartUptime
        UIApplication.shared.isIdleTimerDisabled = false

        mission.hasVideo = videoURL != nil
        mission.videoStart = videoUptime.map { $0 - startUptime }
        mission.hasEngineAudio = audioUptime != nil
        mission.audioStart = audioUptime.map { $0 - startUptime }
        if mission.gate == nil { mission.gate = LapDetector.autoGate(for: track.fixes) }
        if let gate = mission.gate { mission.laps = LapDetector.laps(gate: gate, fixes: track.fixes) }
        store.save(mission, telemetry: track)
        self.mission = nil
        phase = .done(mission.id)
        announcer.say("Mission complete. Your debrief is ready.")
    }
}

/// Thread-safe on/off switch read by the frame callback on the Bluetooth queue.
final class FrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    var isOpen: Bool {
        get { lock.withLock { open } }
        set { lock.withLock { open = newValue } }
    }
}

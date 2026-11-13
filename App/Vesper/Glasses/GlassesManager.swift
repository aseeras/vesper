import AVFoundation
import Foundation
import Observation
import UIKit
import MWDATCamera
import MWDATCore
import MWDATSpeech

/// Talks to the Meta glasses through the Wearables Device Access Toolkit:
/// registration, the device session, the POV camera stream and the in-lens display.
///
/// Modelled on Meta's CameraAccess and DisplayAccess samples (DAT 1.0). The camera runs
/// in compressed HEVC mode, which keeps streaming while the phone is locked in a pocket,
/// and frames are written to disk without re-encoding.
@MainActor
@Observable
final class GlassesManager {
    enum Link: Equatable {
        case notRegistered, registering, waitingForGlasses, connecting, ready, streaming
        case failed(String)

        var label: String {
            switch self {
            case .notRegistered: return "Not paired"
            case .registering: return "Pairing…"
            case .waitingForGlasses: return "Waiting for glasses"
            case .connecting: return "Connecting…"
            case .ready: return "Glasses ready"
            case .streaming: return "Camera live"
            case .failed(let why): return why
            }
        }
    }

    private(set) var link: Link = .notRegistered
    private(set) var isRegistered = false
    private(set) var hasDevice = false

    /// Every compressed frame, with the phone's uptime at arrival. Called off the main thread.
    @ObservationIgnored nonisolated(unsafe) var onFrame: (@Sendable (CMSampleBuffer, TimeInterval) -> Void)?
    /// Live pit-lane preview. Renders compressed frames directly.
    @ObservationIgnored let previewLayer = AVSampleBufferDisplayLayer()
    /// The in-lens screen on Meta Ray-Ban Display glasses.
    @ObservationIgnored let lens = LensDisplay()

    @ObservationIgnored private let wearables = Wearables.shared
    @ObservationIgnored private var session: DeviceSession?
    @ObservationIgnored private var camera: MWDATCamera.Camera?
    @ObservationIgnored private let streamTokens = ListenerTokenBag()
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var wantsLens = false
    /// Long-lived selectors, as in Meta's samples: an AutoDeviceSelector learns the active
    /// device from the device stream, so one created on the spot has no device yet and
    /// createSession throws noEligibleDevice.
    @ObservationIgnored private let anySelector: AutoDeviceSelector
    @ObservationIgnored private let displaySelector: AutoDeviceSelector
    /// Ray-Ban Display glasses connected and selectable right now.
    private(set) var hasDisplayDevice = false
    @ObservationIgnored private var hasAnyActiveDevice = false
    /// Last connection problem, kept on screen instead of being replaced by "Glasses ready".
    private(set) var lastError: String?
    @ObservationIgnored private var wantsCamera = false
    @ObservationIgnored private var sessionIsStarted = false
    @ObservationIgnored private var errorTask: Task<Void, Never>?
    /// Whether to light up the lens (racetrack welcome, live gauges). Set by AppModel from settings.
    @ObservationIgnored var lensEnabled: () -> Bool = { true }
    @ObservationIgnored nonisolated(unsafe) private var previewEnabled = true
    /// Whether Vesper is on screen on the phone. Vesper only puts itself on the glasses
    /// while it's open (or when asked: the Lens button, "Hey Meta", arming a drive), so it
    /// never takes over the lens just because the glasses connected.
    @ObservationIgnored private var appIsActive = false

    // MARK: Voice
    /// Whether "Hey Meta" and spoken commands are on. Set by AppModel from settings.
    @ObservationIgnored var voiceEnabled: () -> Bool = { true }
    /// Every final transcript heard through the glasses' microphone.
    @ObservationIgnored var onHeard: ((String) -> Void)?
    /// "Hey Meta, start Vesper".
    @ObservationIgnored var onVoiceLaunch: (() -> Void)?
    /// Second line under the racetrack on the lens.
    @ObservationIgnored var welcomeLine: () -> String = { "Ready when you are" }
    private(set) var voiceStatus = "Waiting for glasses"
    private(set) var needsMicrophone = false
    @ObservationIgnored private var speech: Speech?
    @ObservationIgnored private var speechHasStarted = false
    @ObservationIgnored private let speechTokens = ListenerTokenBag()
    @ObservationIgnored private var invocations: VoiceInvocationsStream?
    @ObservationIgnored private let invocationTokens = ListenerTokenBag()
    @ObservationIgnored private var invocationDevice: DeviceIdentifier?
    @ObservationIgnored private var activeDeviceID: DeviceIdentifier?

    private static var configured = false

    /// Must run before the first use of `Wearables.shared`. Safe to call more than once.
    static func configureAtLaunch() {
        guard !configured else { return }
        configured = true
        do { try Wearables.configure() } catch { print("Wearables.configure failed: \(error)") }
    }

    init() {
        previewLayer.videoGravity = .resizeAspect
        anySelector = AutoDeviceSelector(wearables: Wearables.shared)
        displaySelector = AutoDeviceSelector(wearables: Wearables.shared, filter: { device in device.supportsDisplay() })
    }

    func observe() async {
        apply(wearables.registrationState)
        for await state in wearables.registrationStateStream() { apply(state) }
    }

    func observeDevices() async {
        for await devices in wearables.devicesStream() {
            hasDevice = !devices.isEmpty
            if isRegistered, session == nil { link = hasDevice ? .ready : .waitingForGlasses }
        }
    }

    /// Whether any glasses are selectable for a recording session.
    func observeActiveDevice() async {
        for await id in anySelector.activeDeviceStream() {
            hasAnyActiveDevice = id != nil
            activeDeviceID = id
            listenForHeyMeta()
        }
    }

    /// Whether Ray-Ban Display glasses are selectable; the welcome goes up when they appear,
    /// but only while Vesper is open on the phone.
    func observeActiveDisplayDevice() async {
        for await id in displaySelector.activeDeviceStream() {
            hasDisplayDevice = id != nil
            if appIsActive { showWelcomeIfPossible() }
        }
    }

    /// Vesper was opened on the phone: put the welcome on the lens.
    func appBecameActive() {
        appIsActive = true
        showWelcomeIfPossible()
    }

    /// Vesper left the screen: hand the glasses back unless a drive is using them.
    func appWentToBackground(driveInProgress: Bool) {
        appIsActive = false
        guard !driveInProgress, !wantsCamera, session != nil else { return }
        lens.detach()
        speech?.stop()
        session?.stop()
        cleanUp()
    }

    private func apply(_ state: RegistrationState) {
        switch state {
        case .registered:
            isRegistered = true
            if session == nil { link = hasDevice ? .ready : .waitingForGlasses }
            if appIsActive { showWelcomeIfPossible() }
            listenForHeyMeta()
        case .registering:
            link = .registering
        default:
            isRegistered = false
            link = .notRegistered
        }
    }

    /// Opens the Meta AI app so Alvin can approve Vesper; it comes back through `handle(url:)`.
    func register() async {
        do { try await wearables.startRegistration() } catch { link = .failed("Pairing failed") }
    }

    func unregister() async {
        try? await wearables.startUnregistration()
    }

    func handle(url: URL) async {
        _ = try? await wearables.handleUrl(url)
    }

    /// Hide the preview once the car is moving; nobody should be watching it.
    func setPreview(enabled: Bool) {
        previewEnabled = enabled
        if !enabled { previewLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil) }
    }

    /// As soon as the app is open and paired Ray-Ban Display glasses are on, put the
    /// racetrack welcome on the lens. The session stays open, and arming a drive adds the
    /// camera to it.
    /// Manual retry from the home screen.
    func retryWelcome() {
        lastError = nil
        showWelcomeIfPossible()
        if !hasDisplayDevice { lastError = "No Ray-Ban Display glasses available to Vesper. Are they on and connected in Meta AI?" }
    }

    /// Put the welcome back up and reopen the glasses session, e.g. after "Hey Meta, start Vesper".
    func wake() {
        if session == nil { showWelcomeIfPossible() } else if !wantsCamera { lens.showWelcome(line: welcomeLine()) }
    }

    private func showWelcomeIfPossible() {
        guard isRegistered, hasDisplayDevice, session == nil, lensEnabled() || voiceEnabled() else { return }
        wantsLens = lensEnabled()
        if wantsLens { lens.showWelcome(line: welcomeLine()) }
        openSession(displayOnly: true)
    }

    /// Starts the camera (720×1280 @ 30 fps, HEVC) and, on Ray-Ban Display glasses, the lens
    /// display. Reuses the welcome session when it is already open.
    func start(lensDisplay: Bool) async {
        wantsLens = lensDisplay
        do {
            if try await wearables.checkPermissionStatus(.camera) != .granted {
                guard try await wearables.requestPermission(.camera) == .granted else {
                    link = .failed("Camera permission denied in Meta AI"); return
                }
            }
        } catch {
            link = .failed("Glasses: \(error.localizedDescription)"); return
        }
        wantsCamera = true
        if let session {
            // Welcome session already open: add the camera now, or when it finishes starting.
            if sessionIsStarted { sessionStarted(session) }
            return
        }
        // Give the selector a moment to pick up the glasses if they've only just connected.
        for _ in 0..<20 where !(hasAnyActiveDevice || hasDisplayDevice) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        openSession(displayOnly: false)
    }

    private func openSession(displayOnly: Bool) {
        do {
            lastError = nil
            // Prefer the Display glasses whenever the lens is wanted and they're available.
            let selector = (displayOnly || (wantsLens && hasDisplayDevice)) ? displaySelector : anySelector
            let session = try wearables.createSession(deviceSelector: selector)
            self.session = session
            link = .connecting
            let states = session.stateStream()
            sessionTask = Task { [weak self] in
                for await state in states {
                    guard let self else { return }
                    switch state {
                    case .started: self.sessionStarted(session)
                    case .stopped: self.cleanUp()
                    default: break
                    }
                }
            }
            let errors = session.errorStream()
            errorTask = Task { [weak self] in
                for await error in errors {
                    print("Glasses session error: \(error)")
                    self?.lastError = "\(error)"
                    if error == .datAppOnTheGlassesUpdateRequired {
                        self?.link = .failed("Update Vesper on the glasses in the Meta AI app")
                    }
                }
            }
            try session.start()
        } catch {
            link = .failed("Glasses: \(error.localizedDescription)")
            lastError = "\(error)"
            cleanUp()
        }
    }

    private func sessionStarted(_ session: DeviceSession) {
        sessionIsStarted = true
        // The lens doesn't depend on the camera, so bring it up first: a camera problem
        // must not leave the driver without speed and revs.
        if wantsLens { lens.attach(to: session) }
        if voiceEnabled() { attachSpeech(to: session) }
        if !wantsCamera { link = .ready }
        guard wantsCamera, camera == nil else { return }
        let config = StreamConfiguration(videoCodec: VideoCodec.hvc1, resolution: StreamingResolution.high, frameRate: 30)
        do {
            guard let camera = try session.addCamera(config: config) else { link = .failed("Camera unavailable"); return }
            self.camera = camera
            let stream = camera.stream
            stream.statePublisher.listen { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .streaming: self.link = .streaming
                    case .waitingForDevice: self.link = .waitingForGlasses
                    case .stopped: self.link = self.isRegistered ? .ready : .notRegistered
                    default: break
                    }
                }
            }.store(in: streamTokens)

            let layer = previewLayer
            stream.videoFramePublisher.listen { [weak self] frame in
                let arrival = ProcessInfo.processInfo.systemUptime
                let sample = frame.sampleBuffer
                self?.onFrame?(sample, arrival)
                if self?.previewEnabled == true { Self.enqueuePreview(sample, on: layer) }
            }.store(in: streamTokens)

            stream.start()
        } catch {
            link = .failed("Camera: \(error.localizedDescription)")
        }
    }

    nonisolated private static func enqueuePreview(_ sample: CMSampleBuffer, on layer: AVSampleBufferDisplayLayer) {
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary],
           let first = attachments.first {
            first[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        if renderer.isReadyForMoreMediaData { renderer.enqueue(sample) }
    }

    func stop() {
        lens.detach()
        speech?.stop()
        camera?.stop()
        session?.stop()
        cleanUp()
        // Back to the welcome (and listening) once the finish card has had its moment,
        // if Vesper is still open on the phone; otherwise the glasses go back to normal.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, self.appIsActive else { return }
            self.showWelcomeIfPossible()
        }
    }

    // MARK: Voice

    /// Turns voice on: asks Meta AI for the glasses' microphone if needed, then starts listening.
    func enableVoice() async {
        do {
            if try await wearables.checkPermissionStatus(.microphone) != .granted {
                guard try await wearables.requestPermission(.microphone) == .granted else {
                    needsMicrophone = true
                    voiceStatus = "Microphone not allowed in Meta AI"
                    return
                }
            }
            needsMicrophone = false
        } catch {
            voiceStatus = "Glasses: \(error.localizedDescription)"
            return
        }
        listenForHeyMeta()
        if let session, sessionIsStarted { attachSpeech(to: session) } else { showWelcomeIfPossible() }
    }

    func disableVoice() {
        speech?.stop()
        try? session?.removeSpeech()
        speech = nil
        speechTokens.clear()
        invocations?.stop()
        invocationDevice = nil
        voiceStatus = "Off"
    }

    /// "Hey Meta, start Vesper" arrives here. It needs no session or microphone, only
    /// Voice Invocation switched on for Vesper in Meta's Wearables Developer Center.
    private func listenForHeyMeta() {
        guard voiceEnabled(), isRegistered, let id = activeDeviceID, id != invocationDevice else { return }
        do {
            if invocations == nil {
                let stream = try VoiceInvocationsStream(wearables: wearables)
                stream.invocationsPublisher.listen { [weak self] invocation in
                    // Meta AI waits for an answer to every invocation; answer each exactly once.
                    guard let launch = invocation as? LaunchApp else { return }
                    Task {
                        _ = await launch.responseHandle.sendSuccess(actionOutput: nil)
                        await MainActor.run { self?.onVoiceLaunch?() }
                    }
                }.store(in: invocationTokens)
                stream.errorPublisher.listen { error in
                    print("Hey Meta: \(error)")
                }.store(in: invocationTokens)
                invocations = stream
            }
            try invocations?.start(deviceIdentifier: id)
            invocationDevice = id
        } catch {
            print("Hey Meta unavailable: \(error)")
        }
    }

    /// On-device speech recognition through the glasses' microphone, for "Vesper, …" commands.
    private func attachSpeech(to session: DeviceSession) {
        guard speech == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let granted = (try? await self.wearables.checkPermissionStatus(.microphone)) == .granted
            guard granted else {
                self.needsMicrophone = true
                self.voiceStatus = "Allow the glasses microphone"
                return
            }
            self.needsMicrophone = false
            // The session may have ended while we asked.
            guard self.sessionIsStarted, self.session != nil, self.speech == nil, self.voiceEnabled() else { return }
            do {
                guard let speech = try session.addSpeech() else {
                    self.voiceStatus = "These glasses can't take voice commands"
                    return
                }
                self.speech = speech
                self.speechHasStarted = false
                speech.transcriptionPublisher.listen { [weak self] result in
                    guard result.isFinal else { return }
                    let text = result.text
                    Task { @MainActor in self?.onHeard?(text) }
                }.store(in: self.speechTokens)
                speech.statePublisher.listen { [weak self] state in
                    Task { @MainActor in self?.speechStateChanged(state) }
                }.store(in: self.speechTokens)
                speech.errorPublisher.listen { error in
                    print("Speech: \(error)")
                }.store(in: self.speechTokens)
                speech.start()
            } catch {
                self.voiceStatus = "Voice: \(error.localizedDescription)"
            }
        }
    }

    private func speechStateChanged(_ state: SpeechState) {
        switch state {
        case .started:
            speechHasStarted = true
            voiceStatus = "Listening for \u{201C}Vesper\u{201D}"
        case .stopped:
            // Stopped is also the state it starts in; only restart one that was listening.
            guard speechHasStarted, speech != nil else { break }
            voiceStatus = "Voice paused"
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let current = self?.speech, current.state == .stopped else { return }
                current.start()
            }
        default:
            break
        }
    }

    private func cleanUp() {
        streamTokens.clear()
        sessionTask?.cancel()
        sessionTask = nil
        errorTask?.cancel()
        errorTask = nil
        lens.detach()
        speechTokens.clear()
        speech = nil
        speechHasStarted = false
        if voiceEnabled() { voiceStatus = "Paused until the glasses reconnect" }
        sessionIsStarted = false
        wantsCamera = false
        camera = nil
        session = nil
        if isRegistered { link = hasDevice ? .ready : .waitingForGlasses }
    }
}

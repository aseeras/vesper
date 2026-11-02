import AVFoundation
import Foundation
import Observation
import UIKit
import MWDATCamera
import MWDATCore

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
    @ObservationIgnored nonisolated(unsafe) private var previewEnabled = true

    static func configureAtLaunch() {
        do { try Wearables.configure() } catch { print("Wearables.configure failed: \(error)") }
    }

    init() {
        previewLayer.videoGravity = .resizeAspect
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

    private func apply(_ state: RegistrationState) {
        switch state {
        case .registered:
            isRegistered = true
            if session == nil { link = hasDevice ? .ready : .waitingForGlasses }
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

    /// Opens a session, then starts the camera (720×1280 @ 30 fps, HEVC) and, on
    /// Ray-Ban Display glasses, the lens display.
    func start(lensDisplay: Bool) async {
        guard session == nil else { return }
        wantsLens = lensDisplay
        do {
            if try await wearables.checkPermissionStatus(.camera) != .granted {
                guard try await wearables.requestPermission(.camera) == .granted else {
                    link = .failed("Camera permission denied in Meta AI"); return
                }
            }
            let session = try wearables.createSession(deviceSelector: AutoDeviceSelector(wearables: wearables))
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
            try session.start()
        } catch {
            link = .failed("Glasses: \(error.localizedDescription)")
            cleanUp()
        }
    }

    private func sessionStarted(_ session: DeviceSession) {
        guard camera == nil else { return }
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
        if wantsLens { lens.attach(to: session) }
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
        camera?.stop()
        session?.stop()
        cleanUp()
    }

    private func cleanUp() {
        streamTokens.clear()
        sessionTask?.cancel()
        sessionTask = nil
        camera = nil
        session = nil
        if isRegistered { link = hasDevice ? .ready : .waitingForGlasses }
    }
}

import AVFoundation
import Foundation
import VesperCore

/// Records the cabin through the phone's own microphone (the soundtrack of that V12)
/// and reads engine RPM from it in real time.
final class EngineAudio: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var estimator: EngineRPMEstimator
    private var window: [Float] = []
    private let lock = NSLock()
    private var samples: [RPMSample] = []
    private var missionStartUptime: TimeInterval = 0
    private(set) var recordingStartUptime: TimeInterval?
    private var isRecording = false

    var onRPM: ((Double) -> Void)?

    init(cylinders: Int) {
        estimator = EngineRPMEstimator(cylinders: cylinders)
    }

    /// Audio routing: play voice call-outs to the glasses' open-ear speakers over A2DP,
    /// but keep recording from the phone mic (HFP would switch the mic to the glasses).
    static func configureSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default,
                          options: [.allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers])
        try s.setActive(true)
        if let builtIn = s.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try s.setPreferredInput(builtIn)
        }
    }

    func startMonitoring(missionStartUptime: TimeInterval) throws {
        self.missionStartUptime = missionStartUptime
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        estimator.sampleRate = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            self?.process(buffer, hostTime: time.hostTime)
        }
        try engine.start()
    }

    func startRecording(to url: URL) throws {
        let format = engine.inputNode.outputFormat(forBus: 0)
        let f = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ])
        lock.withLock { file = f; isRecording = true; recordingStartUptime = nil }
    }

    func stop() -> [RPMSample] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { isRecording = false; file = nil; return samples }
    }

    private func process(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let uptime = AVAudioTime.seconds(forHostTime: hostTime)
        let frames = Int(buffer.frameLength)
        lock.withLock {
            if isRecording, let file {
                if recordingStartUptime == nil { recordingStartUptime = uptime }
                try? file.write(from: buffer)
            }
        }
        window.append(contentsOf: UnsafeBufferPointer(start: data, count: frames))
        while window.count >= 2048 {
            let chunk = Array(window.prefix(2048))
            window.removeFirst(1024)
            if let rpm = estimator.estimate(chunk) {
                let s = RPMSample(t: uptime - missionStartUptime, rpm: rpm)
                lock.withLock { samples.append(s) }
                DispatchQueue.main.async { self.onRPM?(rpm) }
            }
        }
    }
}

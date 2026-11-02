import AVFoundation
import CoreImage
import UIKit
import VesperCore

/// Builds the finished film: picks the moments, cuts the glasses footage to the beat,
/// lays the engine sound under the music, and burns in the overlay.
enum HighlightComposer {
    struct Input {
        var mission: Mission
        var track: TelemetryTrack
        var options: HighlightOptions
        var style: FilmOverlay.Style
        var music: URL?
    }

    enum Failure: LocalizedError {
        case noVideo, nothingToCut, exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .noVideo: return "This mission has no glasses footage."
            case .nothingToCut: return "Not enough footage to make a film."
            case .exportFailed(let why): return "Export failed: \(why)"
            }
        }
    }

    static func render(_ input: Input, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let mission = input.mission
        guard mission.hasVideo, let videoStart = mission.videoStart else { throw Failure.noVideo }
        let videoAsset = AVURLAsset(url: MissionStore.videoURL(mission.id))
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first else { throw Failure.noVideo }
        let videoDuration = try await videoAsset.load(.duration).seconds

        var options = input.options
        options.videoStart = videoStart
        options.videoEnd = videoStart + videoDuration
        let plan = HighlightEngine.plan(track: input.track, laps: mission.laps, options: options)
        guard !plan.segments.isEmpty else { throw Failure.nothingToCut }

        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.exportFailed("no video track")
        }

        var engineSource: AVAssetTrack?
        var engineDuration = 0.0
        var eTrack: AVMutableCompositionTrack?
        if mission.hasEngineAudio, mission.audioStart != nil {
            let a = AVURLAsset(url: MissionStore.audioURL(mission.id))
            engineSource = try? await a.loadTracks(withMediaType: .audio).first
            engineDuration = (try? await a.load(.duration).seconds) ?? 0
            if engineSource != nil {
                eTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            }
        }

        func time(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

        var cursor = CMTime.zero
        for seg in plan.segments {
            let start = max(0, seg.sourceStart - videoStart)
            let duration = min(seg.sourceDuration, videoDuration - start)
            guard duration > 0.05 else { continue }
            let range = CMTimeRange(start: time(start), duration: time(duration))
            try vTrack.insertTimeRange(range, of: sourceVideo, at: cursor)

            if let eTrack, let engineSource, let audioStart = mission.audioStart {
                let aStart = seg.sourceStart - audioStart
                if aStart >= 0, aStart + duration <= engineDuration {
                    try? eTrack.insertTimeRange(CMTimeRange(start: time(aStart), duration: time(duration)),
                                                of: engineSource, at: cursor)
                }
            }

            var out = time(duration)
            if seg.rate != 1 {
                out = time(duration / seg.rate)
                vTrack.scaleTimeRange(CMTimeRange(start: cursor, duration: time(duration)), toDuration: out)
                eTrack?.scaleTimeRange(CMTimeRange(start: cursor, duration: time(duration)), toDuration: out)
            }
            cursor = cursor + out
        }
        let total = cursor

        // Music bed, looped if the track is shorter than the film.
        var mixParams: [AVMutableAudioMixInputParameters] = []
        if let musicURL = input.music {
            let m = AVURLAsset(url: musicURL)
            if let mSource = try? await m.loadTracks(withMediaType: .audio).first,
               let mTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let mDuration = try await m.load(.duration)
                var at = CMTime.zero
                while at < total, mDuration.seconds > 1 {
                    let length = CMTimeMinimum(mDuration, total - at)
                    try mTrack.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: mSource, at: at)
                    at = at + length
                }
                let p = AVMutableAudioMixInputParameters(track: mTrack)
                p.setVolume(0.9, at: .zero)
                p.setVolumeRamp(fromStartVolume: 0.9, toEndVolume: 0,
                                timeRange: CMTimeRange(start: total - time(min(2.5, total.seconds)), duration: time(min(2.5, total.seconds))))
                mixParams.append(p)
            }
        }
        if let eTrack {
            let p = AVMutableAudioMixInputParameters(track: eTrack)
            p.setVolume(0.6, at: .zero)
            mixParams.append(p)
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParams

        // Overlay, drawn per frame.
        let natural = try await sourceVideo.load(.naturalSize)
        let renderSize = CGSize(width: abs(natural.width), height: abs(natural.height))
        let overlay = FilmOverlay(plan: plan, track: input.track, laps: mission.laps, style: input.style, size: renderSize,
                                  introDuration: options.introDuration, outroDuration: options.outroDuration)
        let videoComposition = AVMutableVideoComposition(asset: comp) { request in
            let source = request.sourceImage.clampedToExtent().cropped(to: CGRect(origin: .zero, size: renderSize))
            let graded = grade(source)
            let frame = overlay.image(at: request.compositionTime.seconds).composited(over: graded)
            request.finish(with: frame, context: nil)
        }
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let outURL = MissionStore.filmURL(mission.id)
        try? FileManager.default.removeItem(at: outURL)
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            throw Failure.exportFailed("no export session")
        }
        export.outputURL = outURL
        export.outputFileType = .mp4
        export.videoComposition = videoComposition
        export.audioMix = audioMix

        let ticker = Task {
            while !Task.isCancelled {
                progress(Double(export.progress))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        await export.export()
        ticker.cancel()
        guard export.status == .completed else {
            throw Failure.exportFailed(export.error?.localizedDescription ?? "status \(export.status.rawValue)")
        }
        progress(1)
        return outURL
    }

    /// A cool, high-contrast grade: deeper shadows, a touch of teal, slightly richer colour.
    private static func grade(_ image: CIImage) -> CIImage {
        image
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.12, kCIInputSaturationKey: 1.08])
            .applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 7100, y: 0),
            ])
            .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.6, kCIInputRadiusKey: 1.6])
    }
}

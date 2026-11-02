import AVFoundation
import CoreMedia

/// Writes the glasses' HEVC stream straight to an .mp4, without re-encoding.
///
/// Timestamps are rebased so the file starts at zero, and we remember the phone uptime of
/// the first frame so the editor can line the footage up with GPS, g-force and engine audio.
final class FrameRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "vesper.frame-recorder", qos: .userInitiated)
    private var url: URL?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var firstPTS: CMTime?
    private var lastDTS: CMTime?
    private var firstUptime: TimeInterval?
    private var waitingForKeyframe = true

    /// Phone uptime of the first frame written.
    var startUptime: TimeInterval? { queue.sync { firstUptime } }

    func start(url: URL) {
        queue.sync {
            try? FileManager.default.removeItem(at: url)
            self.url = url
            writer = nil; input = nil; firstPTS = nil; lastDTS = nil; firstUptime = nil
            waitingForKeyframe = true
        }
    }

    func append(_ sample: CMSampleBuffer, uptime: TimeInterval) {
        queue.async { [self] in
            guard let url, let format = CMSampleBufferGetFormatDescription(sample),
                  CMFormatDescriptionGetMediaType(format) == kCMMediaType_Video else { return }
            let key = sample.isKeyframe
            // A file must open on a keyframe or the first second is garbage.
            if waitingForKeyframe { guard key else { return }; waitingForKeyframe = false }

            if writer == nil {
                guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
                let i = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
                i.expectsMediaDataInRealTime = true
                guard w.canAdd(i) else { return }
                w.add(i)
                guard w.startWriting() else { return }
                w.startSession(atSourceTime: .zero)
                writer = w; input = i
            }
            guard let writer, let input, writer.status == .writing, input.isReadyForMoreMediaData else { return }

            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let start = firstPTS ?? pts
            if firstPTS == nil { firstPTS = pts; firstUptime = uptime }
            let given = CMSampleBufferGetDuration(sample)
            let duration = given.isValid && given > .zero ? given : CMTime(value: 1, timescale: 30)
            let rawDTS = CMSampleBufferGetDecodeTimeStamp(sample)
            var dts = (rawDTS.isValid ? rawDTS : pts) - start
            if let lastDTS, dts <= lastDTS { dts = lastDTS + duration }
            let outPTS = max(pts - start, dts)

            var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: outPTS, decodeTimeStamp: dts)
            var copy: CMSampleBuffer?
            guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
                                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                                        sampleBufferOut: &copy) == noErr, let copy else { return }
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(copy, createIfNecessary: true) as? [NSMutableDictionary],
               let first = attachments.first {
                first[kCMSampleAttachmentKey_NotSync] = !key
                first[kCMSampleAttachmentKey_DependsOnOthers] = !key
            }
            if input.append(copy) { lastDTS = dts }
        }
    }

    func finish() async -> URL? {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                defer { self.writer = nil; self.input = nil }
                guard let writer, let input, writer.status == .writing else { cont.resume(returning: nil); return }
                input.markAsFinished()
                let url = self.url
                writer.finishWriting { cont.resume(returning: writer.status == .completed ? url : nil) }
            }
        }
    }
}

extension CMSampleBuffer {
    /// True for HEVC IRAP frames (NAL types 16–21), which a decoder can start from.
    var isKeyframe: Bool {
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[CFString: Any]],
           let notSync = attachments.first?[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync
        }
        guard let data = CMSampleBufferGetDataBuffer(self) else { return false }
        let length = CMBlockBufferGetDataLength(data)
        var offset = 0
        while offset + 5 <= length {
            var size: UInt32 = 0
            guard CMBlockBufferCopyDataBytes(data, atOffset: offset, dataLength: 4, destination: &size) == kCMBlockBufferNoErr else { break }
            let nalLength = Int(UInt32(bigEndian: size))
            offset += 4
            guard nalLength > 0, offset + nalLength <= length else { break }
            var header: UInt8 = 0
            guard CMBlockBufferCopyDataBytes(data, atOffset: offset, dataLength: 1, destination: &header) == kCMBlockBufferNoErr else { break }
            let type = (header >> 1) & 0x3F
            if (16...21).contains(type) { return true }
            offset += nalLength
        }
        return false
    }
}

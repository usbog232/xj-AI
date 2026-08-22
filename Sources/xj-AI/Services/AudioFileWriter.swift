import AVFoundation
import CoreMedia
import Foundation

final class AudioFileWriter {
    private let url: URL
    private var file: AVAudioFile?
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            }
            try file?.write(from: buffer)
        } catch {
            // Recording remains usable even if the optional audio archive cannot be written.
        }
    }

    func write(_ sampleBuffer: CMSampleBuffer) {
        guard let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        write(pcm)
    }

    func finish() {
        lock.lock()
        file = nil
        lock.unlock()
    }

    static func level(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0.05 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            let value = channels[0][index]
            sum += value * value
        }
        let rms = sqrt(sum / Float(count))
        return min(1, max(0.02, Double(rms) * 5.5))
    }

    static func level(from sampleBuffer: CMSampleBuffer) -> Double {
        guard let pcm = pcmBuffer(from: sampleBuffer) else { return 0.05 }
        return level(from: pcm)
    }

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard
            let description = CMSampleBufferGetFormatDescription(sampleBuffer),
            let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description),
            let format = AVAudioFormat(streamDescription: basic)
        else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}

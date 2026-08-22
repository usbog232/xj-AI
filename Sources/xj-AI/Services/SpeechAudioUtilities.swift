import AVFoundation
import Foundation

enum SpeechAudioUtilities {
    enum ConversionError: LocalizedError {
        case unsupportedFormat
        case conversionFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: "语音识别无法读取当前音频格式。"
            case .conversionFailed: "无法把音频转换为 16 kHz 单声道。"
            }
        }
    }

    static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let destination = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: source.frameLength
        ) else { return nil }
        destination.frameLength = source.frameLength

        let sourceList = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationList = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
        guard sourceList.count == destinationList.count else { return nil }
        for index in 0..<sourceList.count {
            guard let sourceData = sourceList[index].mData,
                  let destinationData = destinationList[index].mData else { continue }
            let byteCount = min(sourceList[index].mDataByteSize, destinationList[index].mDataByteSize)
            memcpy(destinationData, sourceData, Int(byteCount))
            destinationList[index].mDataByteSize = byteCount
        }
        return destination
    }

    static func mono16KSamples(from input: AVAudioPCMBuffer) throws -> [Float] {
        try SpeechPCMConverter().convert(input)
    }

    static func whisperLanguage(from localeIdentifier: String) -> String {
        guard localeIdentifier != "auto" else { return "auto" }
        return Locale(identifier: localeIdentifier).language.languageCode?.identifier
            ?? localeIdentifier.split(separator: "-").first.map(String.init)
            ?? "auto"
    }
}

final class SpeechPCMConverter {
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    func convert(_ input: AVAudioPCMBuffer) throws -> [Float] {
        if inputFormat != input.format || converter == nil {
            inputFormat = input.format
            converter = AVAudioConverter(from: input.format, to: outputFormat)
            converter?.primeMethod = .none
        }
        guard let converter else {
            throw SpeechAudioUtilities.ConversionError.unsupportedFormat
        }

        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = max(1, AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw SpeechAudioUtilities.ConversionError.unsupportedFormat
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return input
        }

        guard status != .error, conversionError == nil,
              let samples = output.floatChannelData?[0] else {
            throw conversionError ?? SpeechAudioUtilities.ConversionError.conversionFailed
        }
        return Array(UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
    }
}

extension SpeechAudioUtilities {
    static func wavData(from samples: [Float]) -> Data {
        let pcmBytes = samples.count * MemoryLayout<Int16>.size
        let fileSize = 36 + pcmBytes
        var data = Data(capacity: 44 + pcmBytes)

        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(fileSize))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(16_000))
        data.appendLittleEndian(UInt32(32_000))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(UInt32(pcmBytes))

        for sample in samples {
            let clamped = max(-1, min(1, sample))
            data.appendLittleEndian(Int16(clamped * Float(Int16.max)))
        }
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

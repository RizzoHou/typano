import Accelerate
import AVFoundation

/// Records exactly what the instrument produces, by tapping the graph's own
/// main mixer.
///
/// It cannot hear any other app, it needs no permission, and it does not care
/// which output device is selected — which is the whole reason this is not a
/// system-audio capture. The signal is taken before the hardware, so a
/// Bluetooth codec never touches it.
final class AudioRecorder {
    enum Container: String, CaseIterable {
        case aac, wav

        var fileExtension: String { self == .aac ? "m4a" : "wav" }
        var label: String { self == .aac ? "AAC (.m4a)" : "Lossless (.wav)" }
    }

    enum Failure: LocalizedError {
        case engineNotRunning
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case .engineNotRunning:
                return "The audio engine is not running, so there is nothing to record."
            case .unsupportedFormat(let detail):
                return "Unsupported audio format: \(detail)"
            }
        }
    }

    /// ~85 ms at 48 kHz: about twelve file writes a second, small enough that a
    /// copy per callback costs nothing measurable.
    static let bufferSize: AVAudioFrameCount = 4096

    private let audio: AudioEngine
    /// Every byte of file I/O happens here. The tap block runs on a thread the
    /// render cycle is waiting on; encoding AAC on it is how a recorder glitches
    /// the thing it is recording.
    private let writer = DispatchQueue(label: "com.rizzohou.typano.recording.audio",
                                       qos: .userInitiated)

    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var framesWritten: AVAudioFramePosition = 0
    private var failure: Error?

    /// Peak of the most recent buffer, for the HUD. Written on the tap thread
    /// and read on main; a torn `Float` is not worth a lock.
    private(set) var peak: Float = 0
    private(set) var url: URL?

    init(audio: AudioEngine) { self.audio = audio }

    var duration: TimeInterval {
        guard let file, file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(framesWritten) / file.processingFormat.sampleRate
    }

    // MARK: - Lifecycle

    func start(url destination: URL, container: Container) throws {
        guard audio.isRunning else { throw Failure.engineNotRunning }

        let tap = audio.recordingFormat
        guard tap.sampleRate > 0, tap.channelCount > 0 else {
            throw Failure.unsupportedFormat("\(tap)")
        }

        // Clamped to stereo: an aggregate or HDMI device can present six or
        // eight channels on the main mixer, and nothing downstream wants an
        // eight-channel take of a piano.
        let channels = min(tap.channelCount, 2)
        let settings = Self.settings(container: container,
                                     sampleRate: tap.sampleRate,
                                     channels: channels)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        file = try AVAudioFile(forWriting: destination, settings: settings)
        url = destination
        framesWritten = 0
        failure = nil
        converter = nil
        peak = 0

        audio.installRecordingTap(bufferSize: Self.bufferSize) { [weak self] buffer, _ in
            guard let self, let copy = buffer.copiedForRecording() else { return }
            self.peak = copy.peakAmplitude()
            self.writer.async { self.append(copy) }
        }
    }

    /// `removeTap` does not promise that a callback already in flight has
    /// returned, so the file is closed *on the writer queue* — ordered behind
    /// whatever that callback enqueued — rather than here.
    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        audio.removeRecordingTap()
        let destination = url
        writer.async { [weak self] in
            guard let self else { return }
            let error = self.failure
            self.file = nil          // deinit closes and finalises the container
            self.converter = nil
            self.peak = 0
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else if let destination {
                    completion(.success(destination))
                }
            }
        }
    }

    // MARK: - Writing (writer queue only)

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let file, failure == nil else { return }
        do {
            if buffer.format == file.processingFormat {
                try file.write(from: buffer)
                framesWritten += AVAudioFramePosition(buffer.frameLength)
            } else {
                framesWritten += try writeConverted(buffer, to: file)
            }
        } catch {
            failure = error
        }
    }

    /// The mid-recording format change.
    ///
    /// A route switch reconnects the graph and the main mixer comes back at the
    /// new device's rate — 44.1 kHz on one interface, 48 kHz on another. Writing
    /// that buffer straight into a file opened at the old rate raises an
    /// exception rather than throwing, so the mismatch is caught before the
    /// write and resampled into the format the file was opened with. The take
    /// survives switching headphones; only its rate stays pinned to where it
    /// started.
    private func writeConverted(_ buffer: AVAudioPCMBuffer,
                                to file: AVAudioFile) throws -> AVAudioFramePosition {
        let output = file.processingFormat
        if converter?.inputFormat != buffer.format || converter?.outputFormat != output {
            converter = AVAudioConverter(from: buffer.format, to: output)
            converter?.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        }
        guard let converter else { throw Failure.unsupportedFormat("\(buffer.format)") }

        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else {
            return 0
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let conversionError { throw conversionError }
        guard status != .error, converted.frameLength > 0 else { return 0 }
        try file.write(from: converted)
        return AVAudioFramePosition(converted.frameLength)
    }

    private static func settings(container: Container,
                                 sampleRate: Double,
                                 channels: AVAudioChannelCount) -> [String: Any] {
        switch container {
        case .aac:
            return [AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: 256_000]
        case .wav:
            return [AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVLinearPCMBitDepthKey: 24,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false]
        }
    }
}

private extension AVAudioPCMBuffer {
    /// A tap's buffer is valid only for the duration of the callback, so the
    /// writer queue gets its own. Stereo float at 4096 frames is 32 KB — far
    /// cheaper than doing file I/O on the thread that handed it over.
    func copiedForRecording() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength),
              let source = floatChannelData,
              let destination = copy.floatChannelData
        else { return nil }
        copy.frameLength = frameLength
        let planes = Int(format.isInterleaved ? 1 : format.channelCount)
        let stride = Int(format.isInterleaved ? format.channelCount : 1)
        let bytes = Int(frameLength) * stride * MemoryLayout<Float>.size
        for plane in 0..<planes {
            memcpy(destination[plane], source[plane], bytes)
        }
        return copy
    }

    func peakAmplitude() -> Float {
        guard let data = floatChannelData else { return 0 }
        var peak: Float = 0
        let planes = Int(format.isInterleaved ? 1 : format.channelCount)
        let stride = format.isInterleaved ? Int(format.channelCount) : 1
        let count = vDSP_Length(Int(frameLength) * stride)
        for plane in 0..<planes {
            var value: Float = 0
            vDSP_maxmgv(data[plane], 1, &value, count)
            peak = max(peak, value)
        }
        return peak
    }
}

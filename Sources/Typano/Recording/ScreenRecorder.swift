import AVFoundation
import AppKit
import ScreenCaptureKit

/// Records the instrument window to a file, picture and sound together.
///
/// Window-scoped rather than display-scoped: anything overlapping Typano is not
/// captured, so a Finder window dragged across mid-take does not end up in the
/// video, and the capture keeps working while the window is not frontmost.
final class ScreenRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {

    enum Failure: LocalizedError {
        case notPermitted
        case windowNotShareable

        var errorDescription: String? {
            switch self {
            case .notPermitted:
                return "Typano needs Screen Recording permission to record its own window."
            case .windowNotShareable:
                return "The instrument window is not available for capture — is it minimised?"
            }
        }
    }

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var destination: URL?
    private var finished: ((Result<URL, Error>) -> Void)?

    /// Fired when the stream dies on its own: the window closed, the display
    /// went away, permission was revoked mid-take.
    var onUnexpectedStop: ((Error) -> Void)?

    var recordedDuration: TimeInterval {
        guard let output else { return 0 }
        return CMTimeGetSeconds(output.recordedDuration)
    }

    // MARK: - Lifecycle

    func start(window: NSWindow, to url: URL, fps: Int, showsCursor: Bool) async throws {
        guard CGPreflightScreenCaptureAccess() else { throw Failure.notPermitted }

        // NSWindow.windowNumber *is* the CGWindowID — this is the join between
        // AppKit's idea of our window and ScreenCaptureKit's.
        let id = CGWindowID(window.windowNumber)
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)
        guard let target = content.windows.first(where: { $0.windowID == id }) else {
            throw Failure.windowNotShareable
        }

        let filter = SCContentFilter(desktopIndependentWindow: target)

        let configuration = SCStreamConfiguration()
        // contentRect is in points and pointPixelScale is 2 on a Retina
        // display. Multiplying is what makes the video pixel-exact instead of a
        // soft upscale of a 1180x600 logical frame.
        configuration.width  = Int(filter.contentRect.width  * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.showsCursor = showsCursor
        configuration.scalesToFit = false
        configuration.queueDepth = 6
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        // A sheet is a child window, and the save panel is a sheet. Excluding
        // them keeps the panel's dismissal out of the opening frames.
        configuration.includeChildWindows = false

        configuration.capturesAudio = true
        // False, emphatically: our own audio is the entire point of the video.
        configuration.excludesCurrentProcessAudio = false
        // The microphone is never captured — the user asked for the instrument,
        // not the sound of the keys being struck. Leaving this off also keeps
        // Typano out of microphone TCC altogether.
        configuration.captureMicrophone = false
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mp4
        recording.videoCodecType = .h264

        let output = SCRecordingOutput(configuration: recording, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        // Must be added before startCapture, or the first samples are dropped.
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        self.stream = stream
        self.output = output
        self.destination = url
    }

    /// The file is not complete when this returns — it is complete when
    /// `recordingOutputDidFinishRecording` arrives.
    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        guard let stream, let output else {
            completion(.failure(Failure.windowNotShareable))
            return
        }
        finished = completion
        Task {
            try? stream.removeRecordingOutput(output)
            try? await stream.stopCapture()
            self.stream = nil
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        DispatchQueue.main.async {
            guard let finished = self.finished else {
                if case .failure(let error) = result { self.onUnexpectedStop?(error) }
                return
            }
            self.finished = nil
            self.output = nil
            finished(result)
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        finish(.failure(error))
    }

    // MARK: - SCRecordingOutputDelegate

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        guard let destination else { return }
        finish(.success(destination))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finish(.failure(error))
    }
}

/// Screen Recording permission, and the one honest thing to say about it.
enum ScreenPermission {
    /// Never prompts.
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Prompts, but only ever once per app identity — macOS does not re-ask.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

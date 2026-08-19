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
        case notRecording
        case didNotFinalise

        var errorDescription: String? {
            switch self {
            case .notPermitted:
                return "Typano needs Screen Recording permission to record its own window."
            case .windowNotShareable:
                return "The instrument window is not available for capture — is it minimised?"
            case .notRecording:
                return "There is no video recording to stop."
            case .didNotFinalise:
                return "The video did not finish writing, so the file may be incomplete."
            }
        }
    }

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    /// Non-nil for exactly as long as a take is live. Doubles as the guard that
    /// makes result delivery happen once: two of the three callbacks below can
    /// arrive for the same take.
    private var destination: URL?
    private var finished: ((Result<URL, Error>) -> Void)?
    /// Set the moment a deliberate stop begins, so a stream that reports its
    /// own shutdown is not mistaken for a take that died.
    private var isStopping = false
    private var watchdog: DispatchWorkItem?

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
        self.isStopping = false
    }

    /// Stops the take by stopping the capture, and nothing else.
    ///
    /// Removing the recording output *and* stopping the stream is one teardown
    /// too many. `removeRecordingOutput` is itself a stop: it ends the
    /// recording and starts finalising the file, asynchronously, over the
    /// connection the stream owns. Calling `stopCapture` in the next breath
    /// pulls that connection out from under the finalisation, and the take dies
    /// with `RPRecordingErrorDomain -5814`
    /// (`failedApplicationConnectionInvalid`) on footage that was otherwise
    /// perfectly good. Stopping the capture alone ends the recording and
    /// finalises the file.
    ///
    /// The file is not complete when this returns — it is complete when
    /// `recordingOutputDidFinishRecording` arrives.
    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        guard let stream, destination != nil else {
            completion(.failure(Failure.notRecording))
            return
        }
        // A second press while the file is still finalising is not a second
        // stop. The one already in flight is what reports.
        guard !isStopping else { return }
        finished = completion
        isStopping = true
        // Nothing else reports a stop that hangs, and the UI would sit on
        // "recording" forever.
        armWatchdog(after: 12, reporting: nil)
        Task {
            do {
                try await stream.stopCapture()
            } catch {
                // Usually "already stopped", in which case a delegate callback
                // is on its way; give it a moment before believing the throw.
                self.armWatchdogOnMain(after: 2, reporting: error)
            }
        }
    }

    /// Every result funnels through here, and only the first one for a given
    /// take is delivered — `didStopWithError` and one of the two recording-output
    /// callbacks can both fire for the same stop.
    private func finish(_ result: Result<URL, Error>) {
        DispatchQueue.main.async {
            guard self.destination != nil else { return }
            self.watchdog?.cancel()
            self.watchdog = nil
            self.destination = nil
            self.stream = nil
            self.output = nil
            self.isStopping = false

            guard let finished = self.finished else {
                if case .failure(let error) = result { self.onUnexpectedStop?(error) }
                return
            }
            self.finished = nil
            finished(result)
        }
    }

    private func armWatchdogOnMain(after seconds: TimeInterval, reporting error: Error?) {
        DispatchQueue.main.async { self.armWatchdog(after: seconds, reporting: error) }
    }

    private func armWatchdog(after seconds: TimeInterval, reporting error: Error?) {
        watchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.finish(.failure(error ?? Failure.didNotFinalise))
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    // MARK: - SCStreamDelegate

    /// A stream reports its own shutdown whether or not anyone asked for it, so
    /// during a deliberate stop this says nothing about the file — the
    /// recording output does. Only an unasked-for stop is a failure.
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            guard !self.isStopping else { return }
            self.finish(.failure(error))
        }
    }

    // MARK: - SCRecordingOutputDelegate

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async {
            guard let destination = self.destination else { return }
            self.finish(.success(destination))
        }
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

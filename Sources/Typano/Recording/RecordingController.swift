import AppKit
import Combine
import UniformTypeIdentifiers

/// Owns both recorders and the save panel, and is the only thing the UI talks
/// to. Lives on `AppDelegate` rather than `Instrument` because it needs the
/// window — for the sheet parent and for ScreenCaptureKit's window filter.
final class RecordingController: ObservableObject {

    enum Mode: Equatable {
        case idle
        case choosingLocation
        case audio(started: Date)
        case video(started: Date)

        var isRecording: Bool {
            switch self {
            case .audio, .video: return true
            case .idle, .choosingLocation: return false
            }
        }

        var startedAt: Date? {
            switch self {
            case .audio(let at), .video(let at): return at
            case .idle, .choosingLocation: return nil
            }
        }
    }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastRecording: URL?

    private let instrument: Instrument
    private let settings: Settings
    private let audioRecorder: AudioRecorder
    private let screenRecorder = ScreenRecorder()
    private weak var window: NSWindow?
    private var ticker: Timer?

    init(instrument: Instrument, settings: Settings) {
        self.instrument = instrument
        self.settings = settings
        self.audioRecorder = AudioRecorder(audio: instrument.audioEngine)

        screenRecorder.onUnexpectedStop = { [weak self] error in
            self?.failed(error)
        }
    }

    func attach(window: NSWindow) { self.window = window }

    var isRecordingVideo: Bool { if case .video = mode { return true }; return false }

    // MARK: - Commands

    func toggleAudio() {
        if case .audio = mode { stop() } else if mode == .idle { startAudio() }
    }

    func toggleVideo() {
        if case .video = mode { stop() } else if mode == .idle { startVideo() }
    }

    private func startAudio() {
        let container = settings.recordingContainer
        chooseLocation(suggested: "Typano \(Self.stamp()).\(container.fileExtension)",
                       type: container == .aac ? .mpeg4Audio : .wav) { [weak self] url in
            guard let self, let url else { return }
            do {
                try self.audioRecorder.start(url: url, container: container)
                self.began(.audio(started: Date()))
            } catch {
                self.failed(error)
            }
        }
    }

    private func startVideo() {
        guard ScreenPermission.isGranted else {
            requestScreenPermission()
            return
        }
        chooseLocation(suggested: "Typano \(Self.stamp()).mp4", type: .mpeg4Movie) { [weak self] url in
            guard let self, let url, let window = self.window else { return }
            // A beat after the sheet closes, so its dismissal animation is not
            // in the opening frames.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                Task { @MainActor in
                    do {
                        try await self.screenRecorder.start(
                            window: window,
                            to: url,
                            fps: self.settings.recordingVideoFPS,
                            showsCursor: self.settings.recordingShowsCursor)
                        self.began(.video(started: Date()))
                    } catch {
                        self.failed(error)
                    }
                }
            }
        }
    }

    func stop() {
        switch mode {
        case .audio:
            audioRecorder.stop { [weak self] result in self?.ended(result) }
        case .video:
            screenRecorder.stop { [weak self] result in self?.ended(result) }
        case .idle, .choosingLocation:
            return
        }
    }

    /// Called when the app is about to quit. An unfinalised MPEG-4 has no
    /// `moov` atom and will not open at all, so a take in progress has to be
    /// closed before the process goes away.
    func finishBeforeTermination(_ completion: @escaping () -> Void) {
        guard mode.isRecording else { completion(); return }
        let done = DispatchWorkItem(block: completion)
        switch mode {
        case .audio: audioRecorder.stop { [weak self] result in self?.ended(result); done.perform() }
        case .video: screenRecorder.stop { [weak self] result in self?.ended(result); done.perform() }
        default: done.perform()
        }
        // Never hang the quit on a recorder that does not call back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if !done.isCancelled { done.perform() }
        }
    }

    // MARK: - Save panel

    /// Presented as a sheet, never `runModal()`. A sheet keeps the run loop
    /// turning, so the instrument keeps sounding and the HUD keeps updating;
    /// a modal loop would freeze both.
    private func chooseLocation(suggested: String,
                                type: UTType,
                                completion: @escaping (URL?) -> Void) {
        guard let window else { completion(nil); return }

        let panel = NSSavePanel()
        panel.prompt = "Record"          // the button says what it starts
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = settings.recordingFolderURL

        // Without this the keyboard belongs to the instrument, so typing a
        // filename plays a scale and the text field never sees a character.
        instrument.setNoteInputSuspended(true)
        mode = .choosingLocation

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.instrument.setNoteInputSuspended(false)
            if self.mode == .choosingLocation { self.mode = .idle }

            guard response == .OK, let url = panel.url else { completion(nil); return }
            self.settings.recordingFolder = url.deletingLastPathComponent().path
            completion(url)
        }
    }

    private func requestScreenPermission() {
        ScreenPermission.request()

        let alert = NSAlert()
        alert.messageText = "Typano needs permission to record its window."
        alert.informativeText = """
            macOS puts window recording behind Screen & System Audio Recording. \
            Grant it in System Settings, then quit and reopen Typano — the \
            permission does not reach an app that is already running.

            Audio-only recording needs no permission and works now.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenPermission.openSettings()
        }
    }

    // MARK: - State

    private func began(_ newMode: Mode) {
        mode = newMode
        lastError = nil
        elapsed = 0
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let started = self.mode.startedAt else { return }
            self.elapsed = Date().timeIntervalSince(started)
        }
    }

    private func ended(_ result: Result<URL, Error>) {
        ticker?.invalidate()
        ticker = nil
        mode = .idle
        elapsed = 0
        switch result {
        case .success(let url):
            lastRecording = url
            lastError = nil
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    private func failed(_ error: Error) {
        ticker?.invalidate()
        ticker = nil
        mode = .idle
        elapsed = 0
        lastError = error.localizedDescription
    }

    func revealLastRecording() {
        guard let lastRecording else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastRecording])
    }

    /// Dots rather than colons: the Finder displays a colon in a filename as a
    /// slash.
    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }

    var elapsedLabel: String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

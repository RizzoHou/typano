import Combine
import Foundation

/// User preferences. Every property persists to `UserDefaults` on write and is
/// applied to the running engine immediately — there is no apply button,
/// because balance is something you find by ear while playing.
final class Settings: ObservableObject {

    /// Per-hand levels. 0.5 is the tuned baseline, not unity — see
    /// `AudioEngine.gainDelta(for:)` for the curve.
    ///
    /// Their stored keys are still `melodyLevel` / `chordLevel`: the zones were
    /// named for what they played before the right hand stopped being the chord
    /// hand, and renaming the key would silently reset a balance the user tuned
    /// by ear.
    @Published var leftLevel: Double  { didSet { store(leftLevel, .melodyLevel) } }
    @Published var rightLevel: Double { didSet { store(rightLevel, .chordLevel) } }

    /// Which keyboard is being played. Stored raw so an unknown value degrades
    /// to the built-in default rather than trapping.
    @Published var keyboardModelID: String { didSet { store(keyboardModelID, .keyboardModel) } }

    var keyboardModel: KeyboardModel {
        get { KeyboardModel(rawValue: keyboardModelID) ?? .macBook }
        set { keyboardModelID = newValue.rawValue }
    }

    /// Sustain can come from three independent sources; `Instrument` ORs them.
    @Published var sustainLatchEnabled: Bool    { didSet { store(sustainLatchEnabled, .sustainLatchEnabled) } }
    @Published var sustainSpaceEnabled: Bool    { didSet { store(sustainSpaceEnabled, .sustainSpaceEnabled) } }
    @Published var trackpadSustainEnabled: Bool { didSet { store(trackpadSustainEnabled, .trackpadSustainEnabled) } }

    /// Vertical split of the trackpad, as a fraction of its width from the left.
    @Published var trackpadDivider: Double { didSet { store(trackpadDivider, .trackpadDivider) } }
    /// Swaps which half sustains. The other half is unassigned for now — its
    /// job is to be somewhere the other thumb can rest without sustaining.
    @Published var trackpadSwapped: Bool   { didSet { store(trackpadSwapped, .trackpadSwapped) } }

    /// Recording. The container is stored as a raw string so an unknown value
    /// degrades to the default rather than trapping.
    @Published var recordingFormat: String { didSet { store(recordingFormat, .recordingFormat) } }
    @Published var recordingVideoFPS: Int  { didSet { store(recordingVideoFPS, .recordingVideoFPS) } }
    @Published var recordingShowsCursor: Bool { didSet { store(recordingShowsCursor, .recordingShowsCursor) } }
    /// The recording badge lives inside the captured window, so it lands in the
    /// video. Off by default: a demo of an instrument should show the
    /// instrument, not a readout about itself.
    @Published var recordingBadgeInVideo: Bool { didSet { store(recordingBadgeInVideo, .recordingBadgeInVideo) } }
    @Published var recordingFolder: String { didSet { store(recordingFolder, .recordingFolder) } }

    var recordingContainer: AudioRecorder.Container {
        AudioRecorder.Container(rawValue: recordingFormat) ?? .aac
    }

    var recordingFolderURL: URL {
        if !recordingFolder.isEmpty {
            let url = URL(fileURLWithPath: recordingFolder)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/Typano")
    }

    /// Re-apply the key remaps at launch. Off by default: starting the app
    /// should not silently change system-wide keyboard behaviour. On, it saves
    /// a trip to Preferences after every reboot, since the remaps are per-boot.
    @Published var applyRemapsOnLaunch: Bool { didSet { store(applyRemapsOnLaunch, .applyRemapsOnLaunch) } }

    /// Take the remaps back down when the app quits. On by default, and the
    /// counterpart to `applyRemapsOnLaunch`: the mapping is a system-wide,
    /// per-boot setting that outlives the process, so without this a quit
    /// leaves Caps Lock and right ⌘ rewired for every other app until the next
    /// reboot. Only what this run turned on is undone — a remap set from
    /// `Scripts/remap.sh` before launch is left alone.
    @Published var restoreRemapsOnQuit: Bool { didSet { store(restoreRemapsOnQuit, .restoreRemapsOnQuit) } }

    /// Which remaps to re-apply, remembered from the last time they were
    /// changed in-app. Stored as raw strings so the set survives a schema
    /// change in `KeyRemap.Feature` without crashing on an unknown case.
    var remapsOnLaunch: Set<KeyRemap.Feature> {
        get {
            let raw = defaults.stringArray(forKey: Key.remapsOnLaunch.rawValue) ?? []
            return Set(raw.compactMap(KeyRemap.Feature.init(rawValue:)))
        }
        set {
            defaults.set(newValue.map(\.rawValue).sorted(), forKey: Key.remapsOnLaunch.rawValue)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Key.registrationDefaults)

        leftLevel = defaults.double(forKey: Key.melodyLevel.rawValue)
        rightLevel = defaults.double(forKey: Key.chordLevel.rawValue)
        keyboardModelID = defaults.string(forKey: Key.keyboardModel.rawValue) ?? KeyboardModel.macBook.rawValue
        sustainLatchEnabled = defaults.bool(forKey: Key.sustainLatchEnabled.rawValue)
        sustainSpaceEnabled = defaults.bool(forKey: Key.sustainSpaceEnabled.rawValue)
        trackpadSustainEnabled = defaults.bool(forKey: Key.trackpadSustainEnabled.rawValue)
        trackpadDivider = defaults.double(forKey: Key.trackpadDivider.rawValue)
        trackpadSwapped = defaults.bool(forKey: Key.trackpadSwapped.rawValue)
        applyRemapsOnLaunch = defaults.bool(forKey: Key.applyRemapsOnLaunch.rawValue)
        restoreRemapsOnQuit = defaults.bool(forKey: Key.restoreRemapsOnQuit.rawValue)
        recordingFormat = defaults.string(forKey: Key.recordingFormat.rawValue) ?? "aac"
        recordingVideoFPS = defaults.integer(forKey: Key.recordingVideoFPS.rawValue)
        recordingShowsCursor = defaults.bool(forKey: Key.recordingShowsCursor.rawValue)
        recordingBadgeInVideo = defaults.bool(forKey: Key.recordingBadgeInVideo.rawValue)
        recordingFolder = defaults.string(forKey: Key.recordingFolder.rawValue) ?? ""
    }

    func resetLevels() {
        leftLevel = 0.5
        rightLevel = 0.5
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private enum Key: String, CaseIterable {
        case melodyLevel = "melodyLevel"
        case chordLevel = "chordLevel"
        case keyboardModel = "keyboardModel"
        case sustainLatchEnabled = "sustainLatchEnabled"
        case sustainSpaceEnabled = "sustainSpaceEnabled"
        case trackpadSustainEnabled = "trackpadSustainEnabled"
        case trackpadDivider = "trackpadDivider"
        case trackpadSwapped = "trackpadSwapped"
        case applyRemapsOnLaunch = "applyRemapsOnLaunch"
        case restoreRemapsOnQuit = "restoreRemapsOnQuit"
        case remapsOnLaunch = "remapsOnLaunch"
        case recordingFormat = "recordingFormat"
        case recordingVideoFPS = "recordingVideoFPS"
        case recordingShowsCursor = "recordingShowsCursor"
        case recordingBadgeInVideo = "recordingBadgeInVideo"
        case recordingFolder = "recordingFolder"

        static let registrationDefaults: [String: Any] = [
            Key.melodyLevel.rawValue: 0.5,
            Key.chordLevel.rawValue: 0.5,
            Key.keyboardModel.rawValue: KeyboardModel.macBook.rawValue,
            Key.sustainLatchEnabled.rawValue: true,
            Key.sustainSpaceEnabled.rawValue: true,
            Key.trackpadSustainEnabled.rawValue: true,
            Key.trackpadDivider.rawValue: 0.5,
            Key.trackpadSwapped.rawValue: false,
            Key.applyRemapsOnLaunch.rawValue: false,
            Key.restoreRemapsOnQuit.rawValue: true,
            Key.recordingFormat.rawValue: "aac",
            Key.recordingVideoFPS.rawValue: 60,
            Key.recordingShowsCursor.rawValue: false,
            Key.recordingBadgeInVideo.rawValue: false,
            Key.recordingFolder.rawValue: "",
        ]
    }
}

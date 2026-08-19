import Combine
import Foundation

/// User preferences. Every property persists to `UserDefaults` on write and is
/// applied to the running engine immediately — there is no apply button,
/// because balance is something you find by ear while playing.
final class Settings: ObservableObject {

    /// Zone levels. 0.5 is the tuned baseline, not unity — see
    /// `AudioEngine.gainDelta(for:)` for the curve.
    @Published var melodyLevel: Double { didSet { store(melodyLevel, .melodyLevel) } }
    @Published var chordLevel: Double  { didSet { store(chordLevel, .chordLevel) } }

    /// Sustain can come from three independent sources; `Instrument` ORs them.
    @Published var sustainLatchEnabled: Bool    { didSet { store(sustainLatchEnabled, .sustainLatchEnabled) } }
    @Published var sustainSpaceEnabled: Bool    { didSet { store(sustainSpaceEnabled, .sustainSpaceEnabled) } }
    @Published var trackpadSustainEnabled: Bool { didSet { store(trackpadSustainEnabled, .trackpadSustainEnabled) } }

    /// Vertical split of the trackpad, as a fraction of its width from the left.
    @Published var trackpadDivider: Double { didSet { store(trackpadDivider, .trackpadDivider) } }
    /// Swaps which half sustains. The other half is unassigned for now — its
    /// job is to be somewhere the other thumb can rest without sustaining.
    @Published var trackpadSwapped: Bool   { didSet { store(trackpadSwapped, .trackpadSwapped) } }

    /// Re-apply the key remaps at launch. Off by default: starting the app
    /// should not silently change system-wide keyboard behaviour. On, it saves
    /// a trip to Preferences after every reboot, since the remaps are per-boot.
    @Published var applyRemapsOnLaunch: Bool { didSet { store(applyRemapsOnLaunch, .applyRemapsOnLaunch) } }

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

        melodyLevel = defaults.double(forKey: Key.melodyLevel.rawValue)
        chordLevel = defaults.double(forKey: Key.chordLevel.rawValue)
        sustainLatchEnabled = defaults.bool(forKey: Key.sustainLatchEnabled.rawValue)
        sustainSpaceEnabled = defaults.bool(forKey: Key.sustainSpaceEnabled.rawValue)
        trackpadSustainEnabled = defaults.bool(forKey: Key.trackpadSustainEnabled.rawValue)
        trackpadDivider = defaults.double(forKey: Key.trackpadDivider.rawValue)
        trackpadSwapped = defaults.bool(forKey: Key.trackpadSwapped.rawValue)
        applyRemapsOnLaunch = defaults.bool(forKey: Key.applyRemapsOnLaunch.rawValue)
    }

    func resetLevels() {
        melodyLevel = 0.5
        chordLevel = 0.5
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private enum Key: String, CaseIterable {
        case melodyLevel = "melodyLevel"
        case chordLevel = "chordLevel"
        case sustainLatchEnabled = "sustainLatchEnabled"
        case sustainSpaceEnabled = "sustainSpaceEnabled"
        case trackpadSustainEnabled = "trackpadSustainEnabled"
        case trackpadDivider = "trackpadDivider"
        case trackpadSwapped = "trackpadSwapped"
        case applyRemapsOnLaunch = "applyRemapsOnLaunch"
        case remapsOnLaunch = "remapsOnLaunch"

        static let registrationDefaults: [String: Any] = [
            Key.melodyLevel.rawValue: 0.5,
            Key.chordLevel.rawValue: 0.5,
            Key.sustainLatchEnabled.rawValue: true,
            Key.sustainSpaceEnabled.rawValue: true,
            Key.trackpadSustainEnabled.rawValue: true,
            Key.trackpadDivider.rawValue: 0.5,
            Key.trackpadSwapped.rawValue: false,
            Key.applyRemapsOnLaunch.rawValue: false,
        ]
    }
}

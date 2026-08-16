import AppKit
import Combine

/// Counts how many keys the hardware actually reports at once. The keyboard
/// matrix blocks certain combinations, and which ones is a property of this
/// specific keyboard — worth measuring rather than assuming.
struct RolloverStats {
    var current = 0
    var maxOverall = 0
    var maxLeft = 0
    var maxRight = 0

    mutating func record(_ held: Set<UInt16>) {
        current = held.count
        maxOverall = max(maxOverall, held.count)
        maxLeft = max(maxLeft, held.intersection(Layouts.melodyKeys).count)
        maxRight = max(maxRight, held.intersection(Layouts.chordKeys).count)
    }

    mutating func reset() { self = RolloverStats() }
}

final class Instrument: ObservableObject {
    struct Caption {
        let primary: String
        let secondary: String?
    }

    @Published private(set) var held: Set<UInt16> = []
    @Published private(set) var transpose = 0
    @Published private(set) var octaveShift = 0
    @Published private(set) var accidental = 0
    @Published private(set) var pedalDown = false
    @Published private(set) var layoutIndex = 0
    @Published private(set) var timbreIndex = 0
    @Published private(set) var soundSource = "loading…"
    @Published private(set) var capsLockRemapped = true
    @Published private(set) var stats = RolloverStats()
    @Published var showRollover = false

    private let audio = AudioEngine()
    private lazy var performer = Performer(audio: audio)
    private let monitor = KeyboardMonitor()

    var layout: Layout { Layouts.all[layoutIndex] }

    /// Tonic of the current key, e.g. "D major" after transposing up two.
    var keyName: String { Pitch.rootName(pitchClass: transpose) + " major" }

    var transposeLabel: String { transpose == 0 ? "0" : (transpose > 0 ? "+\(transpose)" : "\(transpose)") }

    var octaveLabel: String { octaveShift == 0 ? "0" : (octaveShift > 0 ? "+\(octaveShift)" : "\(octaveShift)") }

    func start() {
        audio.start()
        soundSource = audio.sourceLabel

        monitor.onKeyDown = { [weak self] in self?.keyDown($0) }
        monitor.onKeyUp = { [weak self] in self?.keyUp($0) }
        monitor.onRawCapsLock = { [weak self] in self?.capsLockRemapped = false }
        monitor.start()
    }

    // MARK: - Key handling

    private func keyDown(_ code: UInt16) {
        guard !held.contains(code) else { return }
        held.insert(code)
        stats.record(held)
        refreshAccidental()

        guard let action = layout.actions[code] else { return }
        switch action {
        case .note(let base):
            performer.noteOn(key: code, midi: base + pitchOffset)
        case .chord(let spec):
            performer.playChord(spec, key: code, transpose: transpose + accidental)
        case .pedal:
            pedalDown = true
            performer.setPedal(true)
        case .transpose(let delta):
            transpose = max(-12, min(12, transpose + delta))
        case .octave(let delta):
            octaveShift = max(-2, min(2, octaveShift + delta))
        case .accidental:
            break   // handled by refreshAccidental
        }
    }

    private func keyUp(_ code: UInt16) {
        held.remove(code)
        stats.current = held.count
        refreshAccidental()

        guard let action = layout.actions[code] else { return }
        switch action {
        case .note:
            performer.noteOff(key: code)
        case .chord:
            performer.releaseChord(key: code)
        case .pedal:
            pedalDown = false
            performer.setPedal(false)
        default:
            break
        }
    }

    /// Derived from the held set rather than tracked per event, so releasing
    /// one arrow while the other is still down falls back correctly.
    private func refreshAccidental() {
        if held.contains(KC.up) { accidental = 1 }
        else if held.contains(KC.down) { accidental = -1 }
        else { accidental = 0 }
    }

    /// Semitones added to every melody note as currently configured.
    private var pitchOffset: Int { transpose + 12 * octaveShift + accidental }

    // MARK: - Commands

    func switchLayout() {
        performer.allNotesOff()
        layoutIndex = (layoutIndex + 1) % Layouts.all.count
    }

    func selectTimbre(_ index: Int) {
        guard SoundLibrary.timbres.indices.contains(index) else { return }
        performer.allNotesOff()
        timbreIndex = index
        soundSource = audio.load(timbre: index)
    }

    func resetTranspose() {
        transpose = 0
        octaveShift = 0
    }

    func resetStats() { stats.reset() }

    // MARK: - Display

    func action(for code: UInt16) -> KeyAction? { layout.actions[code] }

    func caption(for code: UInt16) -> Caption? {
        guard let action = layout.actions[code] else { return nil }
        switch action {
        case .note(let base):
            return Caption(primary: Pitch.noteName(midi: base + transpose + 12 * octaveShift),
                           secondary: nil)
        case .chord(let spec):
            return Caption(primary: spec.symbol(transpose: transpose), secondary: spec.degree)
        case .pedal:
            return Caption(primary: "sustain", secondary: "pedal")
        case .accidental(let delta):
            return Caption(primary: delta > 0 ? "♯" : "♭", secondary: "hold")
        case .transpose(let delta):
            return Caption(primary: delta > 0 ? "key ♯" : "key ♭", secondary: "transpose")
        case .octave(let delta):
            return Caption(primary: delta > 0 ? "8va" : "8vb", secondary: "octave")
        }
    }
}

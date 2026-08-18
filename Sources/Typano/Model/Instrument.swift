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
    /// Which of the three sustain sources are holding the pedal, for the HUD.
    @Published private(set) var sustainSource = ""
    @Published private(set) var sustainLatched = false
    @Published private(set) var trackpadContacts: [CGPoint] = []
    @Published private(set) var layoutIndex = 0
    @Published private(set) var timbreIndex = 0
    @Published private(set) var soundSource = "loading…"
    @Published private(set) var capsLockRemapped = true
    @Published private(set) var stats = RolloverStats()
    @Published var showRollover = false

    let settings: Settings

    private let audio = AudioEngine()
    private lazy var performer = Performer(audio: audio)
    private let monitor = KeyboardMonitor()
    private weak var trackpad: TrackpadSurface?
    private var cancellables: Set<AnyCancellable> = []

    /// Sustain is an OR of three independent sources, so releasing one must not
    /// lift the pedal while another still holds it.
    private var latchOn = false
    private var trackpadSustain = false
    private var spaceHeld = false

    /// True only while the instrument window is key. The trackpad is a pointing
    /// device everywhere else — including in our own Preferences window, which
    /// is what makes its sliders draggable while the instrument keeps sounding.
    private var instrumentFocused = false

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

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
        monitor.onSustainLatchToggle = { [weak self] in self?.toggleLatch() }
        monitor.shouldSwallowPointer = { [weak self] in self?.shouldSwallowPointer($0) ?? false }
        monitor.start()

        observeSettings()
    }

    /// Wired by the app delegate once the window exists.
    func attach(trackpad: TrackpadSurface) {
        self.trackpad = trackpad
        trackpad.onContactsChanged = { [weak self] contacts in
            self?.updateTrackpad(contacts.map(\.position))
        }
    }

    // MARK: - Settings

    private func observeSettings() {
        // `@Published` replays the current value on subscribe, so this is also
        // the initial apply.
        settings.$melodyLevel
            .sink { [weak self] in self?.audio.setMelodyLevel($0) }
            .store(in: &cancellables)
        settings.$chordLevel
            .sink { [weak self] in self?.audio.setChordLevel($0) }
            .store(in: &cancellables)

        settings.$sustainLatchEnabled
            .sink { [weak self] enabled in
                guard let self, !enabled else { return }
                self.latchOn = false
                self.sustainLatched = false
                self.refreshPedal()
            }
            .store(in: &cancellables)
        settings.$sustainSpaceEnabled
            .sink { [weak self] enabled in
                guard let self, !enabled else { return }
                self.spaceHeld = false
                self.refreshPedal()
            }
            .store(in: &cancellables)
        settings.$trackpadSustainEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled { self.trackpadSustain = false; self.refreshPedal() }
                self.updateCursorVisibility()
            }
            .store(in: &cancellables)

        // The zone boundary moved under the fingers currently on the pad.
        settings.$trackpadDivider
            .sink { [weak self] _ in self?.reevaluateTrackpadZones() }
            .store(in: &cancellables)
        settings.$trackpadSwapped
            .sink { [weak self] _ in self?.reevaluateTrackpadZones() }
            .store(in: &cancellables)
    }

    // MARK: - Focus

    /// The local monitor only sees events while the app is active, so
    /// ⌘-Tabbing away mid-note would otherwise strand the note and leave CC64
    /// latched at 127 forever.
    func setAppActive(_ value: Bool) {
        guard !value else { return }
        setInstrumentFocused(false)
        panic()
    }

    /// Instrument window key or not. Deliberately non-destructive: moving focus
    /// to Preferences must not cut off a chord that is still ringing.
    func setInstrumentFocused(_ value: Bool) {
        guard instrumentFocused != value else { return }
        instrumentFocused = value
        if value {
            trackpad?.window?.makeFirstResponder(trackpad)
        } else {
            trackpad?.clearContacts()
            trackpadContacts = []
            setTrackpadSustain(false)
        }
        updateCursorVisibility()
    }

    private var cursorHidden = false

    /// Hidden only while a thumb is actually on the pad, because that thumb
    /// drags the pointer across the screen for the whole phrase. Lifting it
    /// brings the cursor straight back — hiding it for the entire session would
    /// make the menu bar unusable.
    private func updateCursorVisibility() {
        let shouldHide = instrumentFocused
            && settings.trackpadSustainEnabled
            && !showRollover
            && !trackpadContacts.isEmpty
        guard shouldHide != cursorHidden else { return }
        cursorHidden = shouldHide
        if shouldHide { NSCursor.hide() } else { NSCursor.unhide() }
    }

    /// A tap on the trackpad must not press whatever the cursor happens to be
    /// sitting on.
    ///
    /// Scoped to the instrument window: events with another window — the menu
    /// bar above all — are left alone, or turning trackpad sustain on would
    /// make the menus unclickable. The rollover overlay is exempt too, so its
    /// reset button keeps working.
    private func shouldSwallowPointer(_ event: NSEvent) -> Bool {
        guard instrumentFocused, settings.trackpadSustainEnabled, !showRollover else { return false }
        guard let surface = trackpad, let window = surface.window else { return false }
        return event.window === window
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
            guard settings.sustainSpaceEnabled else { return }
            spaceHeld = true
            refreshPedal()
        case .sustainLatch:
            break   // driven by the monitor's tap detection, not by the press
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
            spaceHeld = false
            refreshPedal()
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

    // MARK: - Sustain

    private func toggleLatch() {
        guard settings.sustainLatchEnabled else { return }
        latchOn.toggle()
        sustainLatched = latchOn
        refreshPedal()
    }

    private func updateTrackpad(_ contacts: [CGPoint]) {
        trackpadContacts = contacts
        reevaluateTrackpadZones()
        updateCursorVisibility()
    }

    private func reevaluateTrackpadZones() {
        guard instrumentFocused, settings.trackpadSustainEnabled else {
            setTrackpadSustain(false)
            return
        }
        let divider = settings.trackpadDivider
        setTrackpadSustain(trackpadContacts.contains { point in
            (point.x < divider) != settings.trackpadSwapped
        })
    }

    private func setTrackpadSustain(_ value: Bool) {
        guard trackpadSustain != value else { return }
        trackpadSustain = value
        refreshPedal()
    }

    /// CC64 is sent only on the combined transition, so three sources cannot
    /// fight over one pedal.
    private func refreshPedal() {
        var sources: [String] = []
        if latchOn { sources.append("latch") }
        if trackpadSustain { sources.append("trackpad") }
        if spaceHeld { sources.append("space") }

        sustainSource = sources.joined(separator: " + ")
        let down = !sources.isEmpty
        guard down != pedalDown else { return }
        pedalDown = down
        performer.setPedal(down)
    }

    // MARK: - Commands

    /// Everything off, including `held` — which `Performer.allNotesOff` cannot
    /// clear, and which used to leave keys permanently dead after a stranded
    /// key-up.
    func panic() {
        performer.allNotesOff()
        monitor.resetTransientState()
        held = []
        stats.current = 0
        accidental = 0
        latchOn = false
        sustainLatched = false
        trackpadSustain = false
        spaceHeld = false
        trackpadContacts = []
        sustainSource = ""
        pedalDown = false
    }

    func switchLayout() {
        panic()
        layoutIndex = (layoutIndex + 1) % Layouts.all.count
    }

    func selectTimbre(_ index: Int) {
        guard SoundLibrary.timbres.indices.contains(index) else { return }
        panic()
        timbreIndex = index
        soundSource = audio.load(timbre: index)
    }

    func resetTranspose() {
        transpose = 0
        octaveShift = 0
    }

    func resetStats() { stats.reset() }

    func toggleRollover() {
        showRollover.toggle()
        updateCursorVisibility()
    }

    // MARK: - Display

    func action(for code: UInt16) -> KeyAction? { layout.actions[code] }

    /// Right ⌘ lights while latched, not only while physically down — the
    /// whole point of a latch is that the finger has left the key.
    func isLit(_ code: UInt16) -> Bool {
        held.contains(code) || (code == KC.rightCommand && sustainLatched)
    }

    func caption(for code: UInt16) -> Caption? {
        guard let action = layout.actions[code] else { return nil }
        switch action {
        case .note(let base):
            return Caption(primary: Pitch.noteName(midi: base + transpose + 12 * octaveShift),
                           secondary: nil)
        case .chord(let spec):
            return Caption(primary: spec.symbol(transpose: transpose), secondary: spec.degree)
        case .pedal:
            return Caption(primary: "sustain", secondary: "hold")
        case .sustainLatch:
            return Caption(primary: "sustain", secondary: "latch")
        case .accidental(let delta):
            return Caption(primary: delta > 0 ? "♯" : "♭", secondary: "hold")
        case .transpose(let delta):
            return Caption(primary: delta > 0 ? "key ♯" : "key ♭", secondary: "transpose")
        case .octave(let delta):
            return Caption(primary: delta > 0 ? "8va" : "8vb", secondary: "octave")
        }
    }
}

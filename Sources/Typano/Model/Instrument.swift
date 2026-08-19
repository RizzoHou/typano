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
    /// What `hidutil` actually reports, re-read whenever the app becomes
    /// active. The table survives app restarts and is cleared by a reboot, so
    /// it can only be read, never remembered.
    @Published private(set) var activeRemaps: Set<KeyRemap.Feature> = []
    /// Set when a raw Caps Lock arrives — i.e. this keyboard is sending the
    /// unremapped key. Distinct from `activeRemaps`: `hidutil` covers only the
    /// devices attached when it ran, so a keyboard plugged in afterwards
    /// reports the mapping while not obeying it.
    @Published private(set) var sawRawCapsLock = false

    var capsLockRemapped: Bool { activeRemaps.contains(.capsLock) && !sawRawCapsLock }
    var rightCommandRemapped: Bool { activeRemaps.contains(.rightCommand) }
    /// The mapping is set but this keyboard is not honouring it — the one case
    /// the table alone cannot describe.
    var capsLockRemapStale: Bool { activeRemaps.contains(.capsLock) && sawRawCapsLock }
    @Published private(set) var remapError: String?
    @Published private(set) var stats = RolloverStats()
    @Published var showRollover = false

    let settings: Settings

    private let audio = AudioEngine()
    /// Exposed only so `RecordingController` can install its tap. The engine
    /// itself stays private; `AudioEngine` publishes just the tap seam.
    var audioEngine: AudioEngine { audio }
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
        // Wired before `start()` so a launch-time failure publishes through the
        // same channel a later route failure does.
        //
        // A route change strands every sounding note and re-initialises the
        // samplers out from under a latched CC64 — and `refreshPedal()` only
        // sends CC64 on a transition, so without this the pedal would read down
        // and behave up, permanently. `panic()` is the only thing that clears
        // `held` as well as the sound.
        audio.onRouteChange = { [weak self] in self?.panic() }
        audio.onStatusChange = { [weak self] in self?.soundSource = $0 }
        audio.start()
        soundSource = audio.statusLabel

        monitor.onKeyDown = { [weak self] in self?.keyDown($0) }
        monitor.onKeyUp = { [weak self] in self?.keyUp($0) }
        monitor.onRawCapsLock = { [weak self] in self?.sawRawCapsLock = true }
        monitor.onSustainLatchToggle = { [weak self] in self?.toggleLatch() }
        monitor.shouldSwallowPointer = { [weak self] in self?.shouldSwallowPointer($0) ?? false }
        monitor.start()

        observeSettings()

        refreshRemapState()
        if settings.applyRemapsOnLaunch, !settings.remapsOnLaunch.isEmpty {
            setRemaps(settings.remapsOnLaunch)
        }
    }

    /// Hands the keyboard to a panel that accepts typing. Deliberately not
    /// `panic()`: a chord ringing when the save panel opens should keep
    /// ringing, exactly as it does when Preferences takes focus.
    func setNoteInputSuspended(_ suspended: Bool) {
        monitor.setNoteInputSuspended(suspended)
    }

    // MARK: - Key remaps

    /// Re-read the live table. Cheap enough to call on every activation, and it
    /// has to be: a reboot clears the remaps behind the app's back, and the
    /// user may run `Scripts/remap.sh` while the app is running.
    func refreshRemapState() {
        let active = KeyRemap.active()
        guard active != activeRemaps else { return }
        activeRemaps = active
        // A fresh mapping supersedes whatever the keyboard was doing before it.
        if active.contains(.capsLock) { sawRawCapsLock = false }
    }

    func setRemap(_ feature: KeyRemap.Feature, enabled: Bool) {
        var wanted = activeRemaps
        if enabled { wanted.insert(feature) } else { wanted.remove(feature) }
        setRemaps(wanted)
    }

    private func setRemaps(_ wanted: Set<KeyRemap.Feature>) {
        do {
            try KeyRemap.apply(wanted)
            sawRawCapsLock = false
            remapError = nil
        } catch {
            remapError = error.localizedDescription
        }
        // Read back rather than assuming the write took: `hidutil` can accept
        // the call and still not cover a device.
        activeRemaps = KeyRemap.active()
        settings.remapsOnLaunch = activeRemaps
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
        guard !value else {
            // Clicking away and back is a manual retry, so a stuck engine does
            // not mean waiting out the backoff timer.
            audio.recoverIfNeeded()
            return
        }
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
            && pointerInPlayArea
        guard shouldHide != cursorHidden else { return }
        cursorHidden = shouldHide
        if shouldHide { NSCursor.hide() } else { NSCursor.unhide() }
    }

    /// The playable area is the content view, which excludes the title bar.
    /// Everything below rests on that split: a pointer over the title bar keeps
    /// its cursor and keeps its clicks, so the close and minimise buttons stay
    /// reachable while a thumb is on the pad.
    private var pointerInPlayArea: Bool {
        guard let surface = trackpad, let window = surface.window else { return false }
        return surface.frame.contains(window.convertPoint(fromScreen: NSEvent.mouseLocation))
    }

    /// A tap on the trackpad must not press whatever the cursor happens to be
    /// sitting on.
    ///
    /// Scoped to the instrument window's *content view*: events with another
    /// window — the menu bar above all — are left alone, or turning trackpad
    /// sustain on would make the menus unclickable, and events in the title bar
    /// are left alone, or the close and minimise buttons stop responding. The
    /// rollover overlay is exempt too, so its reset button keeps working.
    private func shouldSwallowPointer(_ event: NSEvent) -> Bool {
        // The pointer moved, so the cursor may have crossed into or out of the
        // playable area.
        updateCursorVisibility()
        guard instrumentFocused, settings.trackpadSustainEnabled, !showRollover else { return false }
        guard let surface = trackpad, let window = surface.window else { return false }
        guard event.window === window else { return false }
        return surface.frame.contains(event.locationInWindow)
    }

    // MARK: - Key handling

    private func keyDown(_ code: UInt16) {
        // F16 arriving used to be how the app inferred that right ⌘ was
        // remapped. `hidutil` is now read directly, which is authoritative and
        // works before any key is pressed — an inference could only ever flip
        // one way, and never back.
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
            // Right ⌘ is a modifier, so its latch is driven by the monitor's
            // tap detection. Remapped to F16 it is an ordinary key, and the
            // press itself is the tap.
            if code != KC.rightCommand { toggleLatch() }
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
        audio.load(timbre: index)
        soundSource = audio.statusLabel
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
        held.contains(code)
            || (code == KC.rightCommand && (sustainLatched || held.contains(KC.f16)))
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

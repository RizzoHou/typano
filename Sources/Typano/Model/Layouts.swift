import Foundation

/// The instrument mappings.
///
/// Two families, and which one is in force is a property of the keyboard
/// rather than a preference — see `KeyboardModel`.
///
/// **Chord grid** (built-in MacBook keyboard). Left of the Y/H/N column plays
/// melody, three rows of seven keys, one diatonic octave each. Right of it
/// plays chords, one key per chord, which sidesteps the built-in matrix's
/// limits on simultaneous right-hand keys.
///
/// **Diatonic** (external 98 / full-size keyboards, after FreePiano). Every row
/// of the main block is one continuous major scale, rows an octave apart and
/// column-aligned; the numeric keypad and editing cluster carry the right hand.
/// An external board is n-key rollover, so the chord grid has nothing left to
/// work around and the right hand plays real notes.
enum Layouts {

    // MARK: - Scale

    /// Scale steps of a major scale, in semitones from the tonic.
    private static let majorSteps = [0, 2, 4, 5, 7, 9, 11]

    /// Semitones above the tonic for the `degree`-th note of a major scale,
    /// counting on past the octave — the rows are longer than seven keys.
    private static func diatonic(_ degree: Int) -> Int {
        12 * (degree / 7) + majorSteps[degree % 7]
    }

    /// A row of keys walking the scale upwards from `base`, plus the leading
    /// tone a semitone below it on the wide key at the left edge.
    private struct Row {
        let lead: UInt16
        let keys: [UInt16]
        /// MIDI note of the first letter key.
        let base: Int

        func actions(_ hand: Hand) -> [UInt16: KeyAction] {
            var out: [UInt16: KeyAction] = [lead: .note(base - 1, hand)]
            for (degree, key) in keys.enumerated() {
                out[key] = .note(base + diatonic(degree), hand)
            }
            return out
        }
    }

    private static func merge(_ parts: [[UInt16: KeyAction]]) -> [UInt16: KeyAction] {
        parts.reduce(into: [:]) { $0.merge($1) { a, _ in a } }
    }

    // MARK: - Controls, shared by every layout

    private static var controlActions: [UInt16: KeyAction] {
        [
            KC.space:        .pedal,
            KC.rightCommand: .sustainLatch,
            // An external board may have no right ⌘ at all — a 98 usually ends
            // its bottom row Alt / Fn / Ctrl — so the latch needs a key that
            // exists on every keyboard. Esc is unbound either way, and it is
            // what FreePiano's own users bind sustain to.
            KC.escape:       .sustainLatch,
            // Same key after the right-⌘ remap, which strips it of its
            // modifier meaning at the HID level.
            KC.f16:          .sustainLatch,
            KC.up:           .accidental(1),
            KC.down:         .accidental(-1),
            KC.left:         .transpose(-1),
            KC.right:        .transpose(1),

            // FreePiano's function row, kept in its positions so its habits
            // transfer. F1/F2 are its keyboard-group switch, which we have no
            // use for — the layout follows the keyboard here, not a key.
            KC.f3:  .transpose(1),
            KC.f4:  .transpose(-1),
            KC.f5:  .octave(1, .left),
            KC.f6:  .octave(-1, .left),
            KC.f7:  .octave(1, .right),
            KC.f8:  .octave(-1, .right),
            KC.f9:  .velocity(1, .left),
            KC.f10: .velocity(-1, .left),
            KC.f11: .velocity(1, .right),
            KC.f12: .velocity(-1, .right),
        ]
    }

    // MARK: - Chord grid (built-in MacBook keyboard)

    /// `do` sits on the letter keys (Z/A/Q); the wide, awkward modifiers at the
    /// left edge carry the leading tone `si`. A = middle C.
    private static let macBookRows = [
        Row(lead: KC.shift, keys: [KC.z, KC.x, KC.c, KC.v, KC.b, KC.n], base: 48),
        Row(lead: KC.f13,   keys: [KC.a, KC.s, KC.d, KC.f, KC.g, KC.h], base: 60),
        Row(lead: KC.tab,   keys: [KC.q, KC.w, KC.e, KC.r, KC.t, KC.y], base: 72),
    ]

    private static var macBookMelody: [UInt16: KeyAction] {
        merge(macBookRows.map { $0.actions(.left) })
    }

    /// Physical columns of the right-hand block, top row first.
    private static let chordTopRow = [KC.u, KC.i, KC.o, KC.p, KC.leftBracket, KC.rightBracket, KC.backslash]
    private static let chordHomeRow = [KC.j, KC.k, KC.l, KC.semicolon, KC.quote, KC.ret]
    private static let chordBottomRow = [KC.m, KC.comma, KC.period, KC.slash, KC.rightShift]

    private static func grid(
        top: [ChordSpec], home: [ChordSpec], bottom: [ChordSpec]
    ) -> [UInt16: KeyAction] {
        var actions: [UInt16: KeyAction] = [:]
        for (key, spec) in zip(chordTopRow, top)       { actions[key] = .chord(spec) }
        for (key, spec) in zip(chordHomeRow, home)     { actions[key] = .chord(spec) }
        for (key, spec) in zip(chordBottomRow, bottom) { actions[key] = .chord(spec) }
        return actions
    }

    // Pitch classes for readability below.
    private static let C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11

    /// Melody is the loud hand here and chords are the quiet one, which is the
    /// opposite of the diatonic layout — hence a per-layout balance.
    private static let chordVelocity: [Hand: Int] = [.left: 100, .right: 70]

    /// Columns walk the circle of fifths (F C G D A E B); rows change quality.
    ///
    /// Three rules cover the whole grid:
    ///   右移一格 = 上五度 · 上排 = 加七 · 下排 = 大小调对调
    ///
    /// The three primary triads IV–I–V land on J/K/L, the best keys on the
    /// board, and the rarest chords fall on Return / backslash / right-Shift.
    static let fifths = Layout(
        name: "Circle of fifths",
        leftRule: "melody — one octave per row",
        rightRule: "→ up a fifth · top row +7th · bottom row major↔minor",
        actions: merge([
            macBookMelody,
            controlActions,
            grid(
                top: [
                    ChordSpec(root: F, quality: .major7,          degree: "IVmaj7"),
                    ChordSpec(root: C, quality: .major7,          degree: "Imaj7"),
                    ChordSpec(root: G, quality: .dominant7,       degree: "V7"),
                    ChordSpec(root: D, quality: .minor7,          degree: "ii7"),
                    ChordSpec(root: A, quality: .minor7,          degree: "vi7"),
                    ChordSpec(root: E, quality: .minor7,          degree: "iii7"),
                    ChordSpec(root: B, quality: .halfDiminished7, degree: "viiø7"),
                ],
                home: [
                    ChordSpec(root: F, quality: .major, degree: "IV"),
                    ChordSpec(root: C, quality: .major, degree: "I"),
                    ChordSpec(root: G, quality: .major, degree: "V"),
                    ChordSpec(root: D, quality: .minor, degree: "ii"),
                    ChordSpec(root: A, quality: .minor, degree: "vi"),
                    ChordSpec(root: E, quality: .minor, degree: "iii"),
                ],
                bottom: [
                    ChordSpec(root: F, quality: .minor, degree: "iv"),
                    ChordSpec(root: C, quality: .minor, degree: "i"),
                    ChordSpec(root: G, quality: .minor, degree: "v"),
                    ChordSpec(root: D, quality: .major, degree: "V/V"),
                    ChordSpec(root: A, quality: .major, degree: "V/ii"),
                ]
            ),
        ]),
        startVelocity: chordVelocity
    )

    /// A/B alternative: the home row is ordered by how often the chord is used,
    /// so I–V–vi–IV is a straight left-to-right run across J K L ;. Better
    /// under the fingers, but it is a list to memorise rather than a rule.
    static let popular = Layout(
        name: "Usage order",
        leftRule: "melody — one octave per row",
        rightRule: "home row I V vi IV ii iii · top row +7th · bottom row major↔minor",
        actions: merge([
            macBookMelody,
            controlActions,
            grid(
                top: [
                    ChordSpec(root: C, quality: .major7,          degree: "Imaj7"),
                    ChordSpec(root: G, quality: .dominant7,       degree: "V7"),
                    ChordSpec(root: A, quality: .minor7,          degree: "vi7"),
                    ChordSpec(root: F, quality: .major7,          degree: "IVmaj7"),
                    ChordSpec(root: D, quality: .minor7,          degree: "ii7"),
                    ChordSpec(root: E, quality: .minor7,          degree: "iii7"),
                    ChordSpec(root: B, quality: .halfDiminished7, degree: "viiø7"),
                ],
                home: [
                    ChordSpec(root: C, quality: .major, degree: "I"),
                    ChordSpec(root: G, quality: .major, degree: "V"),
                    ChordSpec(root: A, quality: .minor, degree: "vi"),
                    ChordSpec(root: F, quality: .major, degree: "IV"),
                    ChordSpec(root: D, quality: .minor, degree: "ii"),
                    ChordSpec(root: E, quality: .minor, degree: "iii"),
                ],
                bottom: [
                    ChordSpec(root: C, quality: .minor, degree: "i"),
                    ChordSpec(root: G, quality: .minor, degree: "v"),
                    ChordSpec(root: A, quality: .major, degree: "V/ii"),
                    ChordSpec(root: F, quality: .minor, degree: "iv"),
                    ChordSpec(root: D, quality: .major, degree: "V/V"),
                ]
            ),
        ]),
        startVelocity: chordVelocity
    )

    // MARK: - Diatonic (external keyboards)

    /// FreePiano's default map, key for key. Rows are an octave apart and share
    /// their columns, so changing register is a vertical hand shift with
    /// identical fingering; they run on well past the octave, so the same note
    /// is often reachable from two rows and the easier fingering wins.
    ///
    /// Q is middle C, matching FreePiano's own pitches so its sheet music and
    /// anyone's habits transfer unchanged.
    private static let diatonicRows = [
        Row(lead: KC.shift, keys: [KC.z, KC.x, KC.c, KC.v, KC.b, KC.n, KC.m,
                                   KC.comma, KC.period, KC.slash, KC.rightShift], base: 36),
        Row(lead: KC.f13,   keys: [KC.a, KC.s, KC.d, KC.f, KC.g, KC.h, KC.j, KC.k,
                                   KC.l, KC.semicolon, KC.quote, KC.ret], base: 48),
        Row(lead: KC.tab,   keys: [KC.q, KC.w, KC.e, KC.r, KC.t, KC.y, KC.u, KC.i,
                                   KC.o, KC.p, KC.leftBracket, KC.rightBracket,
                                   KC.backslash], base: 60),
        Row(lead: KC.grave, keys: [KC.one, KC.two, KC.three, KC.four, KC.five, KC.six,
                                   KC.seven, KC.eight, KC.nine, KC.zero, KC.minus,
                                   KC.equal, KC.delete], base: 72),
    ]

    /// The right hand, in ascending order: keypad first, then the editing
    /// cluster above it. Written as one run because the keypad's own geometry
    /// is a reading order, not a musical one — 1·2·3 left to right, bottom row
    /// up. A keyboard missing some of these simply never sends them; nothing
    /// here has to know which board is attached.
    private static let rightRun: [UInt16] = [
        KC.keypad0, KC.keypadDecimal, KC.keypadEnter,
        KC.keypad1, KC.keypad2, KC.keypad3, KC.keypad4, KC.keypad5,
        KC.keypad6, KC.keypad7, KC.keypad8, KC.keypad9,
        KC.keypadPlus, KC.keypadClear, KC.keypadDivide, KC.keypadMultiply, KC.keypadMinus,
        KC.forwardDelete, KC.end, KC.pageDown, KC.help, KC.home, KC.pageUp,
    ]

    /// `rightRun` starts on G3 — the fourth degree above C3 — so that keypad 1
    /// lands on middle C.
    private static let rightFirstDegree = 4
    private static let rightBase = 48

    private static var rightHand: [UInt16: KeyAction] {
        var out: [UInt16: KeyAction] = [:]
        for (index, key) in rightRun.enumerated() {
            out[key] = .note(rightBase + diatonic(rightFirstDegree + index), .right)
        }
        return out
    }

    static let diatonic = Layout(
        name: "Diatonic",
        leftRule: "left hand — one scale per row, rows an octave apart",
        rightRule: "right hand — keypad and editing cluster, ascending",
        // FreePiano's own balance: the accompaniment hand sits under the
        // melody hand, and here the melody hand is the right one.
        actions: merge([
            merge(diatonicRows.map { $0.actions(.left) }),
            rightHand,
            controlActions,
        ]),
        startVelocity: [.left: 80, .right: 100]
    )
}

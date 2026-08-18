import Foundation

/// The instrument mapping.
///
/// Left of the Y/H/N column plays melody: three rows of seven keys, one
/// diatonic octave each, columns aligned so changing octave is a vertical hand
/// shift with identical fingering. `do` sits on the letter keys (Z/A/Q); the
/// wide, awkward modifiers at the left edge carry the leading tone `si`.
///
/// Right of that column plays chords, one key per chord, which sidesteps the
/// keyboard matrix's limits on simultaneous right-hand keys.
enum Layouts {

    // MARK: - Melody (shared by every layout)

    /// Row leading tone, then the six letter keys of that octave.
    private static let melodyRows: [(lead: UInt16, leadNote: Int, keys: [UInt16], base: Int)] = [
        (KC.shift,    47, [KC.z, KC.x, KC.c, KC.v, KC.b, KC.n], 48),  // B2 | C3–A3
        (KC.f13,      59, [KC.a, KC.s, KC.d, KC.f, KC.g, KC.h], 60),  // B3 | C4–A4  (A = middle C)
        (KC.tab,      71, [KC.q, KC.w, KC.e, KC.r, KC.t, KC.y], 72),  // B4 | C5–A5
    ]

    /// Scale steps of a major scale, in semitones from the tonic.
    private static let majorSteps = [0, 2, 4, 5, 7, 9]

    private static var melodyActions: [UInt16: KeyAction] {
        var actions: [UInt16: KeyAction] = [:]
        for row in melodyRows {
            actions[row.lead] = .note(row.leadNote)
            for (index, key) in row.keys.enumerated() {
                actions[key] = .note(row.base + majorSteps[index])
            }
        }
        return actions
    }

    // MARK: - Controls

    private static var controlActions: [UInt16: KeyAction] {
        [
            KC.space:        .pedal,
            KC.rightCommand: .sustainLatch,
            KC.up:           .accidental(1),
            KC.down:         .accidental(-1),
            KC.left:         .transpose(-1),
            KC.right:        .transpose(1),
        ]
    }

    // MARK: - Chord grid

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

    /// Columns walk the circle of fifths (F C G D A E B); rows change quality.
    ///
    /// Three rules cover the whole grid:
    ///   右移一格 = 上五度 · 上排 = 加七 · 下排 = 大小调对调
    ///
    /// The three primary triads IV–I–V land on J/K/L, the best keys on the
    /// board, and the rarest chords fall on Return / backslash / right-Shift.
    static let fifths = Layout(
        name: "Circle of fifths",
        chordRule: "→ up a fifth · top row +7th · bottom row major↔minor",
        actions: melodyActions
            .merging(controlActions) { a, _ in a }
            .merging(grid(
                top: [
                    ChordSpec(root: F, quality: .major7,         degree: "IVmaj7"),
                    ChordSpec(root: C, quality: .major7,         degree: "Imaj7"),
                    ChordSpec(root: G, quality: .dominant7,      degree: "V7"),
                    ChordSpec(root: D, quality: .minor7,         degree: "ii7"),
                    ChordSpec(root: A, quality: .minor7,         degree: "vi7"),
                    ChordSpec(root: E, quality: .minor7,         degree: "iii7"),
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
            )) { a, _ in a }
    )

    /// A/B alternative: the home row is ordered by how often the chord is used,
    /// so I–V–vi–IV is a straight left-to-right run across J K L ;. Better
    /// under the fingers, but it is a list to memorise rather than a rule.
    static let popular = Layout(
        name: "Usage order",
        chordRule: "home row I V vi IV ii iii · top row +7th · bottom row major↔minor",
        actions: melodyActions
            .merging(controlActions) { a, _ in a }
            .merging(grid(
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
            )) { a, _ in a }
    )

    static let all = [fifths, popular]

    /// Used by the rollover tester, which reports the two sides separately —
    /// the left side is expected to hold many keys at once, the right side is
    /// the one the keyboard matrix is suspected of limiting.
    static let melodyKeys: Set<UInt16> = Set(melodyRows.flatMap { [$0.lead] + $0.keys })
    static let chordKeys: Set<UInt16> = Set(chordTopRow + chordHomeRow + chordBottomRow)
}

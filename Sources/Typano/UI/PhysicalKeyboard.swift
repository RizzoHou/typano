import Foundation

struct PhysicalKey {
    let code: UInt16?
    let legend: String
    /// Width in keycap units. Every row of a given model totals the same.
    let width: CGFloat
    /// A gap between clusters, drawn as empty space rather than as a key.
    let isGap: Bool

    init(code: UInt16?, legend: String, width: CGFloat = 1) {
        self.code = code
        self.legend = legend
        self.width = width
        self.isGap = false
    }

    private init(gap width: CGFloat) {
        self.code = nil
        self.legend = ""
        self.width = width
        self.isGap = true
    }

    static func gap(_ width: CGFloat) -> PhysicalKey { PhysicalKey(gap: width) }
}

/// Keycap geometry, drawn to real proportions so the on-screen map reads as the
/// keyboard the user is actually touching.
///
/// Geometry only — nothing here decides what a key *does*. Mappings are keyed by
/// virtual key code, so a board missing a key simply never sends it and a board
/// drawn slightly wrong still plays correctly.
enum PhysicalKeyboard {

    private static func k(_ code: UInt16?, _ legend: String, _ width: CGFloat = 1) -> PhysicalKey {
        PhysicalKey(code: code, legend: legend, width: width)
    }

    // MARK: - Shared blocks

    /// The ANSI main block, 15u wide, minus its function row.
    private static let numberRow: [PhysicalKey] = [
        k(KC.grave, "`"), k(KC.one, "1"), k(KC.two, "2"), k(KC.three, "3"), k(KC.four, "4"),
        k(KC.five, "5"), k(KC.six, "6"), k(KC.seven, "7"), k(KC.eight, "8"), k(KC.nine, "9"),
        k(KC.zero, "0"), k(KC.minus, "-"), k(KC.equal, "="), k(KC.delete, "backspace", 2),
    ]

    private static let topRow: [PhysicalKey] = [
        k(KC.tab, "tab", 1.5), k(KC.q, "Q"), k(KC.w, "W"), k(KC.e, "E"), k(KC.r, "R"),
        k(KC.t, "T"), k(KC.y, "Y"), k(KC.u, "U"), k(KC.i, "I"), k(KC.o, "O"), k(KC.p, "P"),
        k(KC.leftBracket, "["), k(KC.rightBracket, "]"), k(KC.backslash, "\\", 1.5),
    ]

    /// Caps Lock is bound as F13, which is what arrives once the remap has run.
    private static let homeRow: [PhysicalKey] = [
        k(KC.f13, "caps", 1.75), k(KC.a, "A"), k(KC.s, "S"), k(KC.d, "D"), k(KC.f, "F"),
        k(KC.g, "G"), k(KC.h, "H"), k(KC.j, "J"), k(KC.k, "K"), k(KC.l, "L"),
        k(KC.semicolon, ";"), k(KC.quote, "'"), k(KC.ret, "return", 2.25),
    ]

    private static let bottomLetters: [PhysicalKey] = [
        k(KC.z, "Z"), k(KC.x, "X"), k(KC.c, "C"), k(KC.v, "V"), k(KC.b, "B"),
        k(KC.n, "N"), k(KC.m, "M"), k(KC.comma, ","), k(KC.period, "."), k(KC.slash, "/"),
    ]

    // MARK: - Built-in MacBook

    /// 15u, no function row — the built-in row is media keys or a Touch Bar,
    /// and neither reaches a local key monitor without `fn`.
    static let macBook: [[PhysicalKey]] = [
        numberRow,
        topRow,
        homeRow,
        [k(KC.shift, "shift", 2.25)] + bottomLetters + [k(KC.rightShift, "shift", 2.75)],
        [
            k(KC.function, "fn"), k(KC.control, "control"),
            k(KC.option, "option"), k(KC.command, "command"),
            k(KC.space, "space", 5),
            k(KC.rightCommand, "command"), k(KC.rightOption, "option"),
            k(KC.left, "←"), k(KC.up, "↑"), k(KC.down, "↓"), k(KC.right, "→"),
        ],
    ]

    // MARK: - External

    private static let functionRow: [PhysicalKey] = [
        k(KC.escape, "esc"), k(KC.f1, "F1"), k(KC.f2, "F2"), k(KC.f3, "F3"), k(KC.f4, "F4"),
        k(KC.f5, "F5"), k(KC.f6, "F6"), k(KC.f7, "F7"), k(KC.f8, "F8"),
        k(KC.f9, "F9"), k(KC.f10, "F10"), k(KC.f11, "F11"), k(KC.f12, "F12"),
    ]

    /// 98 layout (the Cherry G80-1800 lineage): full keypad, the editing keys
    /// squeezed into a single column, and the arrows tucked under a shortened
    /// right Shift. Which editing keys land in that column is the one thing
    /// vendors do not agree on.
    ///
    /// 15u main + 0.25 + 1u editing column + 0.25 + 4u keypad = 20.5u.
    static let compact98: [[PhysicalKey]] = [
        functionRow + [.gap(2), .gap(0.25), k(KC.forwardDelete, "del"), .gap(0.25), .gap(4)],
        numberRow + [.gap(0.25), k(KC.pageUp, "pgup"), .gap(0.25),
                     k(KC.keypadClear, "num"), k(KC.keypadDivide, "/"),
                     k(KC.keypadMultiply, "*"), k(KC.keypadMinus, "-")],
        topRow + [.gap(0.25), k(KC.pageDown, "pgdn"), .gap(0.25),
                  k(KC.keypad7, "7"), k(KC.keypad8, "8"), k(KC.keypad9, "9"),
                  k(KC.keypadPlus, "+")],
        homeRow + [.gap(0.25), k(KC.home, "home"), .gap(0.25),
                   k(KC.keypad4, "4"), k(KC.keypad5, "5"), k(KC.keypad6, "6"), .gap(1)],
        [k(KC.shift, "shift", 2.25)] + bottomLetters
            + [k(KC.rightShift, "shift", 1.75), k(KC.up, "↑")]
            + [.gap(0.25), k(KC.end, "end"), .gap(0.25),
               k(KC.keypad1, "1"), k(KC.keypad2, "2"), k(KC.keypad3, "3"),
               k(KC.keypadEnter, "enter")],
        // No right ⌘ on this bottom row, which is why the sustain latch also
        // answers to Esc — a right Ctrl arrives as its own code, not as ⌘.
        [
            k(KC.control, "ctrl", 1.25), k(KC.command, "win", 1.25), k(KC.option, "alt", 1.25),
            k(KC.space, "space", 6.25),
            k(KC.rightOption, "alt"), k(nil, "fn"),
            k(KC.left, "←"), k(KC.down, "↓"), k(KC.right, "→"),
        ] + [.gap(0.25), .gap(1), .gap(0.25),
             k(KC.keypad0, "0", 2), k(KC.keypadDecimal, "."), .gap(1)],
    ]

    /// ANSI full size — the 104/108 boards sold everywhere in China, with a
    /// short left Shift and the backslash above Return. Its 105-key ISO cousin
    /// moves that key next to a tall Return and adds one beside left Shift;
    /// this build does not draw that variant.
    ///
    /// 15u main + 0.25 + 3u editing + 0.25 + 4u keypad = 22.5u.
    static let fullSize: [[PhysicalKey]] = [
        [k(KC.escape, "esc"), .gap(1)]
            + [k(KC.f1, "F1"), k(KC.f2, "F2"), k(KC.f3, "F3"), k(KC.f4, "F4"), .gap(0.5)]
            + [k(KC.f5, "F5"), k(KC.f6, "F6"), k(KC.f7, "F7"), k(KC.f8, "F8"), .gap(0.5)]
            + [k(KC.f9, "F9"), k(KC.f10, "F10"), k(KC.f11, "F11"), k(KC.f12, "F12")]
            + [.gap(0.25), k(nil, "prtsc"), k(nil, "scrlk"), k(nil, "pause"), .gap(0.25), .gap(4)],
        numberRow + [.gap(0.25), k(KC.help, "ins"), k(KC.home, "home"), k(KC.pageUp, "pgup"),
                     .gap(0.25),
                     k(KC.keypadClear, "num"), k(KC.keypadDivide, "/"),
                     k(KC.keypadMultiply, "*"), k(KC.keypadMinus, "-")],
        topRow + [.gap(0.25), k(KC.forwardDelete, "del"), k(KC.end, "end"),
                  k(KC.pageDown, "pgdn"), .gap(0.25),
                  k(KC.keypad7, "7"), k(KC.keypad8, "8"), k(KC.keypad9, "9"),
                  k(KC.keypadPlus, "+")],
        homeRow + [.gap(0.25), .gap(3), .gap(0.25),
                   k(KC.keypad4, "4"), k(KC.keypad5, "5"), k(KC.keypad6, "6"), .gap(1)],
        [k(KC.shift, "shift", 2.25)] + bottomLetters + [k(KC.rightShift, "shift", 2.75)]
            + [.gap(0.25), .gap(1), k(KC.up, "↑"), .gap(1), .gap(0.25),
               k(KC.keypad1, "1"), k(KC.keypad2, "2"), k(KC.keypad3, "3"),
               k(KC.keypadEnter, "enter")],
        [
            k(KC.control, "ctrl", 1.25), k(KC.command, "win", 1.25), k(KC.option, "alt", 1.25),
            k(KC.space, "space", 6.25),
            k(KC.rightOption, "alt", 1.25), k(KC.rightCommand, "win", 1.25),
            k(nil, "menu", 1.25), k(nil, "ctrl", 1.25),
        ] + [.gap(0.25), k(KC.left, "←"), k(KC.down, "↓"), k(KC.right, "→"), .gap(0.25),
             k(KC.keypad0, "0", 2), k(KC.keypadDecimal, "."), .gap(1)],
    ]
}

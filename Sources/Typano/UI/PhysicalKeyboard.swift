import Foundation

struct PhysicalKey: Identifiable {
    let id: String
    let code: UInt16?
    let legend: String
    /// Width in keycap units; every row totals 15.
    let width: CGFloat
}

/// The ANSI MacBook keyboard, drawn to its real proportions so the on-screen
/// map reads as the keyboard the user is actually touching.
enum PhysicalKeyboard {
    private static func k(_ code: UInt16?, _ legend: String, _ width: CGFloat = 1, id: String? = nil) -> PhysicalKey {
        PhysicalKey(id: id ?? legend, code: code, legend: legend, width: width)
    }

    static let rows: [[PhysicalKey]] = [
        [
            k(KC.grave, "`"), k(KC.one, "1"), k(KC.two, "2"), k(KC.three, "3"), k(KC.four, "4"),
            k(KC.five, "5"), k(KC.six, "6"), k(KC.seven, "7"), k(KC.eight, "8"), k(KC.nine, "9"),
            k(KC.zero, "0"), k(KC.minus, "-"), k(KC.equal, "="), k(KC.delete, "delete", 2),
        ],
        [
            k(KC.tab, "tab", 1.5), k(KC.q, "Q"), k(KC.w, "W"), k(KC.e, "E"), k(KC.r, "R"),
            k(KC.t, "T"), k(KC.y, "Y"), k(KC.u, "U"), k(KC.i, "I"), k(KC.o, "O"), k(KC.p, "P"),
            k(KC.leftBracket, "["), k(KC.rightBracket, "]"), k(KC.backslash, "\\", 1.5),
        ],
        [
            // Caps Lock is bound as F13, which is what arrives once
            // Scripts/capslock-remap.sh has run.
            k(KC.f13, "caps", 1.75), k(KC.a, "A"), k(KC.s, "S"), k(KC.d, "D"), k(KC.f, "F"),
            k(KC.g, "G"), k(KC.h, "H"), k(KC.j, "J"), k(KC.k, "K"), k(KC.l, "L"),
            k(KC.semicolon, ";"), k(KC.quote, "'"), k(KC.ret, "return", 2.25),
        ],
        [
            k(KC.shift, "shift", 2.25, id: "lshift"), k(KC.z, "Z"), k(KC.x, "X"), k(KC.c, "C"),
            k(KC.v, "V"), k(KC.b, "B"), k(KC.n, "N"), k(KC.m, "M"), k(KC.comma, ","),
            k(KC.period, "."), k(KC.slash, "/"), k(KC.rightShift, "shift", 2.75, id: "rshift"),
        ],
        [
            k(KC.function, "fn"), k(KC.control, "control"),
            k(KC.option, "option", 1, id: "lopt"), k(KC.command, "command", 1, id: "lcmd"),
            k(KC.space, "space", 5),
            k(KC.rightCommand, "command", 1, id: "rcmd"), k(KC.rightOption, "option", 1, id: "ropt"),
            k(KC.left, "←"), k(KC.up, "↑"), k(KC.down, "↓"), k(KC.right, "→"),
        ],
    ]

    static let unitsPerRow: CGFloat = 15
}

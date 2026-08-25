import Foundation

/// Which keyboard is being played, and therefore which mapping applies.
///
/// This is not a taste setting. The built-in MacBook keyboard cannot report
/// enough simultaneous right-hand keys to play chords as notes, which is the
/// whole reason the chord grid exists; an external board is n-key rollover, so
/// there is nothing left to work around and the right hand plays real notes.
/// Picking the keyboard picks the compromise.
enum KeyboardModel: String, CaseIterable, Identifiable {
    /// Built-in ANSI MacBook keyboard.
    case macBook
    /// External 98 — full keypad, sunken arrows, no editing cluster drawn.
    case compact98
    /// External ANSI full size, the 104/108 boards.
    case fullSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macBook:   return "MacBook"
        case .compact98: return "98-key"
        case .fullSize:  return "Full size"
        }
    }

    var detail: String {
        switch self {
        case .macBook:
            return "Built-in keyboard. Limited rollover, so the right hand plays one key per chord."
        case .compact98:
            return "External 98 in Mac mode — Alt sends ⌘, Win sends ⌥. Arrows and keypad carry the right hand."
        case .fullSize:
            return "External 104/108 (ANSI) in Mac mode — Alt sends ⌘, Win sends ⌥. Arrows and keypad carry the right hand."
        }
    }

    var rows: [[PhysicalKey]] {
        switch self {
        case .macBook:   return PhysicalKeyboard.macBook
        case .compact98: return PhysicalKeyboard.compact98
        case .fullSize:  return PhysicalKeyboard.fullSize
        }
    }

    /// Total keycap units across a row, read off the geometry so the two never
    /// drift apart.
    var unitsPerRow: CGFloat {
        rows.first?.reduce(0) { $0 + $1.width } ?? 15
    }

    /// Mappings available on this keyboard, in menu order. The first is the
    /// default.
    var layouts: [Layout] {
        switch self {
        case .macBook:              return [Layouts.fifths, Layouts.popular]
        case .compact98, .fullSize: return [Layouts.diatonic]
        }
    }

    /// Whether the function row reaches a local key monitor at all — on the
    /// built-in keyboard it is media keys unless the user has turned on
    /// standard function keys, and there is no F row drawn for it either.
    var hasFunctionRow: Bool { self != .macBook }
}

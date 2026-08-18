import Foundation

enum KeyAction {
    /// MIDI note at transpose 0 / octave shift 0.
    case note(Int)
    case chord(ChordSpec)
    /// Held: sustain while the key is down.
    case pedal
    /// Tapped: sustain until tapped again. Right ⌘ has to latch rather than
    /// hold, because a held ⌘ routes every following key to the menu.
    case sustainLatch
    /// Held modifier: +1 sharp, -1 flat.
    case accidental(Int)
    /// Latching, per press.
    case transpose(Int)
    case octave(Int)
}

enum KeyRole {
    case melody
    case chord
    case control
    case unassigned
}

extension KeyAction {
    var role: KeyRole {
        switch self {
        case .note:   return .melody
        case .chord:  return .chord
        default:      return .control
        }
    }
}

struct Layout {
    let name: String
    /// Short description of the chord-grid ordering, shown in the HUD.
    let chordRule: String
    let actions: [UInt16: KeyAction]
}

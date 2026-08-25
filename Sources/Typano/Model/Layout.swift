import Foundation

/// Which hand — and therefore which sampler, octave and velocity — a key
/// belongs to. The two audio channels used to be melody and chords; on an
/// external keyboard the right hand plays notes rather than chords, so the
/// axis is the hand, not the material.
enum Hand: String, CaseIterable {
    case left
    case right

    var title: String { self == .left ? "Left" : "Right" }
    var short: String { self == .left ? "L" : "R" }
}

enum KeyAction {
    /// MIDI note at transpose 0 / octave shift 0, played by one hand.
    case note(Int, Hand)
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
    case octave(Int, Hand)
    /// Per-hand MIDI velocity, in steps of `Instrument.velocityStep`.
    case velocity(Int, Hand)
}

enum KeyRole {
    case leftHand
    case rightHand
    case control
    case unassigned
}

extension KeyAction {
    var role: KeyRole {
        switch self {
        case .note(_, let hand): return hand == .left ? .leftHand : .rightHand
        case .chord:             return .rightHand
        default:                 return .control
        }
    }
}

struct Layout {
    let name: String
    /// One line each, shown in the footer legend.
    let leftRule: String
    let rightRule: String
    let actions: [UInt16: KeyAction]
    /// Starting velocity per hand, reset whenever this layout becomes active.
    /// The chord layouts want the melody hand louder; the FreePiano layout
    /// wants the melody hand — which is the right one there — louder instead,
    /// so the balance cannot be a single global constant.
    let startVelocity: [Hand: Int]

    /// Whether the right channel plays stacked chords, which sum roughly 12 dB
    /// louder than a single note and so need a lower baseline gain.
    let rightPlaysChords: Bool
    /// Keys owned by each hand, for the rollover tester — it reports the two
    /// sides separately, and which side the matrix limits is the question.
    let handKeys: [Hand: Set<UInt16>]

    init(name: String,
         leftRule: String,
         rightRule: String,
         actions: [UInt16: KeyAction],
         startVelocity: [Hand: Int]) {
        self.name = name
        self.leftRule = leftRule
        self.rightRule = rightRule
        self.actions = actions
        self.startVelocity = startVelocity

        var left: Set<UInt16> = []
        var right: Set<UInt16> = []
        var chords = false
        for (code, action) in actions {
            switch action.role {
            case .leftHand:  left.insert(code)
            case .rightHand: right.insert(code)
            default:         break
            }
            if case .chord = action { chords = true }
        }
        self.rightPlaysChords = chords
        self.handKeys = [.left: left, .right: right]
    }

    func defaultVelocity(_ hand: Hand) -> Int { startVelocity[hand] ?? 100 }
    func keys(_ hand: Hand) -> Set<UInt16> { handKeys[hand] ?? [] }
}

import Foundation

enum Pitch {
    /// Chord-symbol spellings; flats read better for chord roots than sharps.
    static let rootNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
    /// Melody note spellings.
    static let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    static func pitchClass(_ value: Int) -> Int { ((value % 12) + 12) % 12 }

    static func noteName(midi: Int) -> String {
        noteNames[pitchClass(midi)] + String(midi / 12 - 1)
    }

    static func rootName(pitchClass value: Int) -> String { rootNames[pitchClass(value)] }
}

enum ChordQuality {
    case major
    case minor
    case dominant7
    case major7
    case minor7
    case halfDiminished7

    /// Semitones above the root.
    var intervals: [Int] {
        switch self {
        case .major:           return [0, 4, 7]
        case .minor:           return [0, 3, 7]
        case .dominant7:       return [0, 4, 7, 10]
        case .major7:          return [0, 4, 7, 11]
        case .minor7:          return [0, 3, 7, 10]
        case .halfDiminished7: return [0, 3, 6, 10]
        }
    }

    var suffix: String {
        switch self {
        case .major:           return ""
        case .minor:           return "m"
        case .dominant7:       return "7"
        case .major7:          return "maj7"
        case .minor7:          return "m7"
        case .halfDiminished7: return "m7♭5"
        }
    }
}

struct ChordSpec {
    /// Pitch class at transpose 0, where 0 = C.
    let root: Int
    let quality: ChordQuality
    /// Roman numeral in the home key, shown as a secondary caption.
    let degree: String

    func symbol(transpose: Int) -> String {
        Pitch.rootName(pitchClass: root + transpose) + quality.suffix
    }

    func pitchClasses(transpose: Int) -> [Int] {
        quality.intervals.map { Pitch.pitchClass(root + transpose + $0) }
    }
}

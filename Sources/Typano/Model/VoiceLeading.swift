import Foundation

/// Picks chord voicings that move as little as possible from one chord to the
/// next. Always-root-position triads leap around the register and are the
/// single most obviously mechanical thing a chord instrument can do.
enum VoiceLeading {
    /// Voicings are kept inside this window so the harmony stays put while the
    /// melody moves above it.
    static let windowLow = 52   // E3
    static let windowHigh = 67  // G4

    /// The bass root lives an octave-and-a-bit below, like a pianist's left hand.
    static let bassLow = 36     // C2

    struct Voicing {
        let bass: Int
        /// Upper voices only. Feed these back as `previous` — including the
        /// bass would let every new note match against it and flatten the cost.
        let upper: [Int]
        var notes: [Int] { [bass] + upper }
    }

    static func voice(_ spec: ChordSpec, transpose: Int, previous: [Int]?) -> Voicing {
        let classes = spec.pitchClasses(transpose: transpose)

        // Candidate MIDI notes per pitch class inside the window. With a
        // 16-semitone window each class yields one or two options, so the
        // exhaustive product below stays at 16 combinations or fewer.
        let options: [[Int]] = classes.map { pc in
            stride(from: windowLow, through: windowHigh, by: 1).filter {
                Pitch.pitchClass($0) == pc
            }
        }

        var best: [Int] = []
        var bestScore = Double.greatestFiniteMagnitude

        func walk(_ index: Int, _ chosen: [Int]) {
            guard index < options.count else {
                let score = cost(chosen, previous: previous)
                if score < bestScore {
                    bestScore = score
                    best = chosen
                }
                return
            }
            for note in options[index] {
                walk(index + 1, chosen + [note])
            }
        }
        walk(0, [])

        let bass = bassLow + Pitch.pitchClass(spec.root + transpose)
        return Voicing(bass: bass, upper: best.sorted())
    }

    private static func cost(_ notes: [Int], previous: [Int]?) -> Double {
        guard let previous, !previous.isEmpty else {
            // No history: sit near the middle of the window.
            let center = Double(windowLow + windowHigh) / 2
            return notes.reduce(0) { $0 + abs(Double($1) - center) }
        }
        // Sum of each new note's distance to the nearest previous note, with a
        // mild penalty on total spread so voicings stay compact.
        let motion = notes.reduce(0.0) { total, note in
            total + Double(previous.map { abs($0 - note) }.min() ?? 0)
        }
        let spread = Double((notes.max() ?? 0) - (notes.min() ?? 0))
        return motion + spread * 0.15
    }
}

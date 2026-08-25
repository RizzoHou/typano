import AVFoundation

/// Turns key events into notes. Everything here runs on the main thread — the
/// sampler calls are cheap message sends, not DSP.
final class Performer {
    private let audio: AudioEngine

    private var soundingNotes: [UInt16: (note: Int, hand: Hand)] = [:]
    private var chordNotes: [Int] = []
    private var chordOwner: UInt16?
    private var previousVoicing: [Int]?
    /// Invalidates in-flight strum callbacks when the chord changes under them.
    private var chordGeneration = 0

    /// Velocity is also timbre: the Salamander bank has 16 velocity layers, so
    /// pushing a hand up two layers makes it brighter as well as louder — which
    /// is what "that side sounds small" actually means. Gain alone would make
    /// it loud and still dull.
    ///
    /// Set from the layout and moved live from the function row, so it is a
    /// performance parameter rather than a constant.
    var velocity: [Hand: Int] = [.left: 100, .right: 70]

    /// The bass note of a chord carries it, so it sits above the upper voices —
    /// the same offset the tuned constants used to encode.
    private static let bassBoost = 12

    init(audio: AudioEngine) { self.audio = audio }

    private func sampler(_ hand: Hand) -> AVAudioUnitSampler {
        hand == .left ? audio.left : audio.right
    }

    private func level(_ hand: Hand) -> Int { velocity[hand] ?? 100 }

    // MARK: - Notes

    func noteOn(key: UInt16, midi: Int, hand: Hand) {
        noteOff(key: key)   // defensive: a dropped key-up must not strand a note
        let note = UInt8(clamping: midi)
        sampler(hand).startNote(note, withVelocity: humanised(level(hand)), onChannel: 0)
        soundingNotes[key] = (Int(note), hand)
    }

    func noteOff(key: UInt16) {
        guard let sounding = soundingNotes.removeValue(forKey: key) else { return }
        sampler(sounding.hand).stopNote(UInt8(sounding.note), onChannel: 0)
    }

    // MARK: - Chords

    func playChord(_ spec: ChordSpec, key: UInt16, transpose: Int) {
        stopChordNotes()

        let voicing = VoiceLeading.voice(spec, transpose: transpose, previous: previousVoicing)
        previousVoicing = voicing.upper
        chordNotes = voicing.notes
        chordOwner = key
        chordGeneration += 1
        let generation = chordGeneration

        // Bass lands immediately so the chord feels instant; the upper voices
        // follow a few milliseconds apart. A perfectly simultaneous attack is
        // the clearest tell that no hand was involved.
        audio.right.startNote(UInt8(clamping: voicing.bass),
                              withVelocity: humanised(level(.right) + Self.bassBoost),
                              onChannel: 0)

        var delay = 0.0
        for note in voicing.upper {
            delay += Double.random(in: 0.006...0.012)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.chordGeneration == generation else { return }
                self.audio.right.startNote(UInt8(clamping: note),
                                           withVelocity: self.humanised(self.level(.right)),
                                           onChannel: 0)
            }
        }
    }

    /// Releasing the chord key damps it, exactly as on a piano — unless the
    /// sustain pedal is down, in which case the sampler holds it via CC64.
    func releaseChord(key: UInt16) {
        guard chordOwner == key else { return }
        stopChordNotes()
        chordOwner = nil
    }

    private func stopChordNotes() {
        for note in chordNotes {
            audio.right.stopNote(UInt8(clamping: note), onChannel: 0)
        }
        chordNotes = []
    }

    // MARK: - Pedal

    func setPedal(_ down: Bool) {
        let value: UInt8 = down ? 127 : 0
        audio.left.sendController(64, withValue: value, onChannel: 0)
        audio.right.sendController(64, withValue: value, onChannel: 0)
    }

    // MARK: - Panic

    func allNotesOff() {
        // Strums already in flight must not land after the panic. `chordNotes`
        // is cleared below and CC123 has already gone out by the time a late
        // callback fires, so its `startNote` would produce a note that nothing
        // is left holding a reference to — permanently stuck.
        chordGeneration += 1
        for key in Array(soundingNotes.keys) { noteOff(key: key) }
        stopChordNotes()
        chordOwner = nil
        previousVoicing = nil
        for sampler in [audio.left, audio.right] {
            sampler.sendController(64, withValue: 0, onChannel: 0)    // pedal up
            sampler.sendController(123, withValue: 0, onChannel: 0)   // all notes off
        }
    }

    /// There is no touch sensitivity to read, so a fixed velocity would make
    /// every note identical. A few units of jitter is enough to break that up.
    ///
    /// Clamped to MIDI's 1...127, not `UInt8`'s 0...255: above 127 the value
    /// wraps into nonsense, and velocity 0 is a note-off as far as the sampler
    /// is concerned.
    private func humanised(_ base: Int) -> UInt8 {
        UInt8(max(1, min(127, base + Int.random(in: -6...6))))
    }
}

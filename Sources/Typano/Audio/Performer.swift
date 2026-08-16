import AVFoundation

/// Turns key events into notes. Everything here runs on the main thread — the
/// sampler calls are cheap message sends, not DSP.
final class Performer {
    private let audio: AudioEngine

    private var soundingNotes: [UInt16: Int] = [:]
    private var chordNotes: [Int] = []
    private var chordOwner: UInt16?
    private var previousVoicing: [Int]?
    /// Invalidates in-flight strum callbacks when the chord changes under them.
    private var chordGeneration = 0

    private let melodyVelocity = 78
    private let chordVelocity = 66
    private let bassVelocity = 72

    init(audio: AudioEngine) { self.audio = audio }

    // MARK: - Melody

    func noteOn(key: UInt16, midi: Int) {
        noteOff(key: key)   // defensive: a dropped key-up must not strand a note
        let note = UInt8(clamping: midi)
        audio.melody.startNote(note, withVelocity: humanised(melodyVelocity), onChannel: 0)
        soundingNotes[key] = Int(note)
    }

    func noteOff(key: UInt16) {
        guard let midi = soundingNotes.removeValue(forKey: key) else { return }
        audio.melody.stopNote(UInt8(midi), onChannel: 0)
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
        audio.chords.startNote(UInt8(clamping: voicing.bass),
                               withVelocity: humanised(bassVelocity), onChannel: 0)

        var delay = 0.0
        for note in voicing.upper {
            delay += Double.random(in: 0.006...0.012)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.chordGeneration == generation else { return }
                self.audio.chords.startNote(UInt8(clamping: note),
                                            withVelocity: self.humanised(self.chordVelocity),
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
            audio.chords.stopNote(UInt8(clamping: note), onChannel: 0)
        }
        chordNotes = []
    }

    // MARK: - Pedal

    func setPedal(_ down: Bool) {
        let value: UInt8 = down ? 127 : 0
        audio.melody.sendController(64, withValue: value, onChannel: 0)
        audio.chords.sendController(64, withValue: value, onChannel: 0)
    }

    // MARK: - Panic

    func allNotesOff() {
        for key in Array(soundingNotes.keys) { noteOff(key: key) }
        stopChordNotes()
        chordOwner = nil
        previousVoicing = nil
        for sampler in [audio.melody, audio.chords] {
            sampler.sendController(64, withValue: 0, onChannel: 0)    // pedal up
            sampler.sendController(123, withValue: 0, onChannel: 0)   // all notes off
        }
    }

    /// There is no touch sensitivity to read, so a fixed velocity would make
    /// every note identical. A few units of jitter is enough to break that up.
    private func humanised(_ base: Int) -> UInt8 {
        UInt8(clamping: base + Int.random(in: -6...6))
    }
}

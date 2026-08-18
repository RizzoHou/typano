import AVFoundation

/// `Typano --check-sound` — reports which sound sources actually load on this
/// machine. Runs headless so the sample-library question can be answered from
/// a build shell instead of by ear.
enum SoundCheck {
    /// `Typano --try-instrument <path>` — attempt one arbitrary sampler
    /// instrument file and report the raw error. Used to probe whether a given
    /// sample library is reachable at all.
    static func tryInstrument(path: String) {
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        try? engine.start()

        do {
            try sampler.loadInstrument(at: URL(fileURLWithPath: path))
            print("OK    \(path)")
        } catch {
            print("FAIL  \(path)\n      \(error)")
        }
    }

    static func run() {
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        do {
            try engine.start()
            print("engine: started")
        } catch {
            print("engine: NOT started (\(error.localizedDescription)) — load results below may still be valid")
        }

        for (index, name) in SoundLibrary.timbreNames.enumerated() {
            for candidate in SoundLibrary.timbres[index] {
                do {
                    try candidate.apply(sampler)
                    print("  OK    [\(name)] \(candidate.label)")
                } catch {
                    print("  FAIL  [\(name)] \(candidate.label) — \(error.localizedDescription)")
                }
            }
        }

        graph()
    }

    /// The throwaway engine above wires one sampler straight to the main mixer,
    /// so it says nothing about the real graph. This starts the actual
    /// `AudioEngine` — the only headless way to find out whether the limiter
    /// instantiates and the chain connects on this machine.
    private static func graph() {
        let audio = AudioEngine()
        audio.start()
        print("graph:  \(audio.sourceLabel)")

        for level in [0.0, 0.25, 0.5, 0.75, 1.0] {
            audio.setMelodyLevel(level)
            audio.setChordLevel(level)
            print(String(format: "  level %.2f  melody %+.1f dB  chords %+.1f dB",
                         level, audio.melody.overallGain, audio.chords.overallGain))
        }
    }
}

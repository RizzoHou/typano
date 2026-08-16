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
    }
}

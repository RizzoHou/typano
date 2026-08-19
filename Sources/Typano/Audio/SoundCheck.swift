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
        print("graph:  \(audio.statusLabel)" + (audio.lastFailure.map { " — \($0)" } ?? ""))

        for level in [0.0, 0.25, 0.5, 0.75, 1.0] {
            audio.setMelodyLevel(level)
            audio.setChordLevel(level)
            print(String(format: "  level %.2f  melody %+.1f dB  chords %+.1f dB",
                         level, audio.melody.overallGain, audio.chords.overallGain))
        }
    }

    /// `Typano --check-restart` — exercises the route-change recovery path
    /// without a route change, which is the most that can be proved from a
    /// machine with no audio devices to switch between.
    ///
    /// Asserts the things that would otherwise only be observable by ear: that
    /// a burst of triggers collapses into a single rebuild, that the engine is
    /// running again afterwards, that the sound source and the tuned levels
    /// survived, and that the owner was told to clear its held notes.
    static func restart() -> Bool {
        let audio = AudioEngine()
        var routeChanges = 0
        audio.onRouteChange = { routeChanges += 1 }
        audio.start()

        // Deliberately not the defaults: a rebuild that quietly reset the
        // balance would still pass against 0.5.
        audio.setMelodyLevel(0.75)
        audio.setChordLevel(0.25)
        let source = audio.sourceLabel
        let melodyGain = audio.melody.overallGain
        let chordGain = audio.chords.overallGain

        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            print("  \(condition ? "OK   " : "FAIL ") \(message)")
            if !condition { failures.append(message) }
        }

        expect(audio.isRunning, "engine running after start")
        print("  ....  \(audio.deviceReport)")

        audio.simulateConfigurationChange()
        audio.simulateConfigurationChange()
        audio.simulateDefaultDeviceChange()
        // The debounce and the retry both live on the main queue, so the check
        // has to pump it.
        RunLoop.main.run(until: Date().addingTimeInterval(2))

        expect(audio.rebuildCount == 1,
               "three triggers -> one rebuild (got \(audio.rebuildCount))")
        expect(audio.isRunning, "engine running after rebuild")
        expect(audio.lastFailure == nil, "no failure recorded (\(audio.lastFailure ?? "—"))")
        expect(audio.sourceLabel == source, "sound source survived: \(audio.sourceLabel)")
        expect(audio.melody.overallGain == melodyGain,
               "melody gain survived (\(audio.melody.overallGain) dB)")
        expect(audio.chords.overallGain == chordGain,
               "chord gain survived (\(audio.chords.overallGain) dB)")
        expect(routeChanges == 2,
               "held notes cleared on the change and on recovery (got \(routeChanges))")
        print("  ....  \(audio.deviceReport)")

        print(failures.isEmpty ? "restart: PASS" : "restart: FAIL (\(failures.count))")
        return failures.isEmpty
    }
}

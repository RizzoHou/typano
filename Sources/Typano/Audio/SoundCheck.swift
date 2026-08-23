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

    /// `Typano --check-remap` — reports the live `hidutil` table.
    ///
    /// Worth having as a check rather than a print: the parse is the part that
    /// silently lies. `hidutil` emits an OpenStep plist, which has no number
    /// type, so reading the values as `NSNumber` yields nil and the app reports
    /// "nothing remapped" while both remaps are active.
    static func remap() -> Bool {
        let active = KeyRemap.active()
        let foreign = KeyRemap.foreignEntries()

        for feature in KeyRemap.Feature.allCases {
            let on = active.contains(feature)
            print(String(format: "  %@  %-16@  0x%llX -> 0x%llX",
                         on ? "ON " : "off",
                         feature.rawValue as NSString,
                         feature.source, feature.destination))
        }
        if !foreign.isEmpty {
            print("  \(foreign.count) entr\(foreign.count == 1 ? "y" : "ies") not owned by Typano — preserved on write")
        }
        print("remap: \(active.isEmpty ? "none active" : active.map(\.rawValue).sorted().joined(separator: " + "))")
        return true
    }

    /// `Typano --check-remap --write` — exercises the write path and restores
    /// the table to exactly what it found.
    ///
    /// Opt-in because it changes system-wide keyboard state for a moment. Worth
    /// having: `hidutil` replaces the whole table on every call, so the only
    /// thing standing between a user's unrelated remaps and oblivion is the
    /// foreign-entry preservation here — and that cannot be checked by reading
    /// the table, only by writing one and looking at what survived.
    static func remapWrite() -> Bool {
        let originalOurs = KeyRemap.active()
        let originalForeign = KeyRemap.foreignEntries()
        print("  before: ours=\(originalOurs.count) foreign=\(originalForeign.count)")

        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            print("  \(condition ? "OK   " : "FAIL ") \(message)")
            if !condition { failures += 1 }
        }

        defer {
            try? KeyRemap.apply(originalOurs)
            let restored = KeyRemap.active()
            print("  restored: \(restored.map(\.rawValue).sorted().joined(separator: " + "))"
                  + (restored.isEmpty ? "none" : ""))
        }

        do {
            try KeyRemap.apply([.capsLock])
            expect(KeyRemap.active() == [.capsLock], "applied capsLock only")

            try KeyRemap.apply([.capsLock, .rightCommand])
            expect(KeyRemap.active() == [.capsLock, .rightCommand], "applied both")

            expect(KeyRemap.foreignEntries().count == originalForeign.count,
                   "foreign entries preserved across writes (\(originalForeign.count))")

            try KeyRemap.apply([])
            expect(KeyRemap.active().isEmpty, "cleared ours")
            expect(KeyRemap.foreignEntries().count == originalForeign.count,
                   "foreign entries survive clearing ours — remap.sh off does not")

            // The quit path, played out against the real table: a remap set
            // from the shell before launch, the launch auto-apply on top of it,
            // then termination. Only the second one may come back off — undoing
            // by restoring a remembered table wholesale would delete the first.
            var session = KeyRemap.Session()
            try KeyRemap.apply([.capsLock])
            let atLaunch = KeyRemap.active()
            session.reconcile(with: atLaunch)

            try KeyRemap.apply(atLaunch.union([.rightCommand]))
            session.record(before: atLaunch, after: KeyRemap.active())
            expect(KeyRemap.active() == [.capsLock, .rightCommand],
                   "launch adds to what it found")

            try KeyRemap.apply(session.releasing(KeyRemap.active()))
            expect(KeyRemap.active() == [.capsLock],
                   "quit removes only what this run added")

            // Turned off by hand during the session, then quit: nothing left to
            // undo, and nothing resurrected.
            var toggled = KeyRemap.Session()
            let none = Set<KeyRemap.Feature>()
            try KeyRemap.apply([.rightCommand])
            toggled.record(before: none, after: KeyRemap.active())
            let onScreen = KeyRemap.active()
            try KeyRemap.apply([])
            toggled.record(before: onScreen, after: KeyRemap.active())
            try KeyRemap.apply(toggled.releasing(KeyRemap.active()))
            expect(KeyRemap.active().isEmpty, "quit does not re-add a remap turned off in-app")
        } catch {
            expect(false, "apply threw: \(error.localizedDescription)")
        }

        print(failures == 0 ? "remap write: PASS" : "remap write: FAIL (\(failures))")
        return failures == 0
    }

    /// `Typano --check-recording <path>` — proves the whole audio recording
    /// path without ears.
    ///
    /// Starts the real `AudioEngine`, installs the tap, plays an arpeggio so
    /// the file contains actual signal, stops, and reopens the result. A
    /// non-zero peak plus a successful readback covers format negotiation, the
    /// encoder, the write queue and finalisation — all from a Linux shell.
    static func recording(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let audio = AudioEngine()
        audio.start()

        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            print("  \(condition ? "OK   " : "FAIL ") \(message)")
            if !condition { failures += 1 }
        }

        expect(audio.isRunning, "engine running")
        print("  ....  tap format: \(audio.recordingFormat)")

        let container: AudioRecorder.Container =
            url.pathExtension.lowercased() == "wav" ? .wav : .aac
        let recorder = AudioRecorder(audio: audio)
        do {
            try recorder.start(url: url, container: container)
        } catch {
            print("  FAIL  start: \(error.localizedDescription)")
            return false
        }
        print("  ....  writing \(container.rawValue) -> \(path)")

        // A C major arpeggio, so the file has signal rather than silence.
        var peak: Float = 0
        for note in [60, 64, 67, 72] as [UInt8] {
            audio.melody.startNote(note, withVelocity: 100, onChannel: 0)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            peak = max(peak, recorder.peak)
            audio.melody.stopNote(note, onChannel: 0)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        peak = max(peak, recorder.peak)

        // The coupling between the route-change fix and this feature: a rebuild
        // tears the graph down, which drops installed taps. Without
        // restoreRecordingTap the recording would silently stop receiving audio
        // here and the rest of the take would be silence, with no error.
        let beforeRebuild = recorder.duration
        audio.simulateConfigurationChange()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        var peakAfter: Float = 0
        for note in [67, 72] as [UInt8] {
            audio.melody.startNote(note, withVelocity: 100, onChannel: 0)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            peakAfter = max(peakAfter, recorder.peak)
            audio.melody.stopNote(note, onChannel: 0)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        peakAfter = max(peakAfter, recorder.peak)

        expect(recorder.duration > beforeRebuild + 0.5,
               String(format: "tap survived a graph rebuild (%.2f s -> %.2f s)",
                      beforeRebuild, recorder.duration))
        expect(peakAfter > 0.001,
               String(format: "still capturing signal after the rebuild, peak %.4f", peakAfter))
        peak = max(peak, peakAfter)

        let framesSeen = recorder.duration
        var finished = false
        var result: Result<URL, Error>?
        recorder.stop { outcome in result = outcome; finished = true }
        let deadline = Date().addingTimeInterval(5)
        while !finished, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        expect(finished, "recorder finished")
        if case .failure(let error) = result {
            expect(false, "write failed: \(error.localizedDescription)")
        }
        expect(framesSeen > 2.5, String(format: "tap ran for %.2f s", framesSeen))
        // Silence would still produce a valid file, so this is the assertion
        // that separates "it wrote something" from "it recorded the instrument".
        expect(peak > 0.001, String(format: "captured signal, peak %.4f", peak))

        let size = (try? FileManager.default
            .attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        expect((size ?? 0) > 1024, "file is \(size ?? 0) bytes")

        if let readback = try? AVAudioFile(forReading: url) {
            let seconds = Double(readback.length) / readback.processingFormat.sampleRate
            expect(readback.length > 0,
                   String(format: "readback %d frames, %.2f s", readback.length, seconds))
        } else {
            expect(false, "could not reopen the file — container not finalised?")
        }

        print("  ....  screen recording permission: \(ScreenPermission.isGranted)")
        print(failures == 0 ? "recording: PASS" : "recording: FAIL (\(failures))")
        return failures == 0
    }
}

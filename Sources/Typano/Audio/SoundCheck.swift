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
            audio.setLevel(level, for: .left)
            audio.setLevel(level, for: .right)
            print(String(format: "  level %.2f  left %+.1f dB  right %+.1f dB",
                         level, audio.left.overallGain, audio.right.overallGain))
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
        audio.setLevel(0.75, for: .left)
        audio.setLevel(0.25, for: .right)
        let source = audio.sourceLabel
        let leftGain = audio.left.overallGain
        let rightGain = audio.right.overallGain

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
        expect(audio.left.overallGain == leftGain,
               "left gain survived (\(audio.left.overallGain) dB)")
        expect(audio.right.overallGain == rightGain,
               "right gain survived (\(audio.right.overallGain) dB)")
        expect(routeChanges == 2,
               "held notes cleared on the change and on recovery (got \(routeChanges))")
        print("  ....  \(audio.deviceReport)")

        print(failures.isEmpty ? "restart: PASS" : "restart: FAIL (\(failures.count))")
        return failures.isEmpty
    }

    /// `Typano --check-layout` — asserts the key maps rather than printing
    /// them, because a mapping typo is silent: a wrong note still sounds, and
    /// nothing on a Linux box can hear that it is the wrong one.
    static func layout() -> Bool {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            print("  \(condition ? "OK   " : "FAIL ") \(message)")
            if !condition { failures.append(message) }
        }

        func note(_ layout: Layout, _ code: UInt16) -> Int? {
            if case .note(let midi, _)? = layout.actions[code] { return midi }
            return nil
        }

        // MARK: geometry
        for model in KeyboardModel.allCases {
            let widths = model.rows.map { row in row.reduce(0) { $0 + $1.width } }
            let uniform = widths.allSatisfy { abs($0 - model.unitsPerRow) < 0.001 }
            expect(uniform,
                   "\(model.title): every row is \(model.unitsPerRow)u (got \(widths))")
            expect(!model.layouts.isEmpty, "\(model.title): has a layout")

            let drawn = Set(model.rows.flatMap { $0.compactMap(\.code) })
            for layout in model.layouts {
                let both = layout.keys(.left).intersection(layout.keys(.right))
                expect(both.isEmpty,
                       "\(model.title)/\(layout.name): hands do not overlap")

                // A key that is mapped but not on the board is a note the user
                // can never play — the failure the drawn keyboard exists to
                // make visible, and the one thing here Linux can still check.
                let missing = layout.keys(.left).union(layout.keys(.right)).subtracting(drawn)
                expect(missing.isEmpty,
                       "\(model.title)/\(layout.name): every mapped note key is on the board"
                       + " (missing \(missing.sorted().map(String.init).joined(separator: " ")))")
            }

            if model != .macBook {
                // Mac mode puts ⌘ on the Alt key right of the space bar, which
                // is where the sustain latch lives on all three keyboards.
                expect(drawn.contains(KC.rightCommand),
                       "\(model.title): draws a right ⌘ (the Alt key in Mac mode)")
            }
        }

        // MARK: diatonic anchors — FreePiano's own pitches, key for key
        let d = Layouts.diatonic
        let anchors: [(UInt16, Int, String)] = [
            (KC.shift, 35, "shift = B1"), (KC.z, 36, "Z = C2"),
            (KC.f13, 47, "caps = B2"), (KC.a, 48, "A = C3"),
            (KC.tab, 59, "tab = B3"), (KC.q, 60, "Q = C4 (middle C)"),
            (KC.grave, 71, "` = B4"), (KC.one, 72, "1 = C5"),
            (KC.rightShift, 53, "right shift = F3"),
            (KC.ret, 67, "return = G4"), (KC.backslash, 81, "\\ = A5"),
            (KC.delete, 93, "backspace = A6"),
            (KC.left, 48, "← = C3"), (KC.up, 53, "↑ = F3"),
            (KC.keypad0, 55, "keypad 0 = G3"), (KC.keypadEnter, 59, "keypad enter = B3"),
            (KC.keypad1, 60, "keypad 1 = C4"),
            (KC.keypad9, 74, "keypad 9 = D5"), (KC.keypadMinus, 83, "keypad − = B5"),
        ]
        for (code, midi, label) in anchors {
            expect(note(d, code) == midi,
                   "diatonic: \(label) (got \(note(d, code).map(String.init) ?? "nothing"))")
        }
        expect(d.keys(.left).count == 53, "diatonic: 53 left-hand keys (got \(d.keys(.left).count))")
        expect(d.keys(.right).count == 21, "diatonic: 21 right-hand keys (got \(d.keys(.right).count))")
        expect(!d.rightPlaysChords, "diatonic: right hand plays notes, not chords")

        // MARK: chord grid anchors — unchanged by the diatonic work
        let f = Layouts.fifths
        for (code, midi, label) in [(KC.shift, 47, "shift = B2"), (KC.z, 48, "Z = C3"),
                                    (KC.a, 60, "A = C4 (middle C)"), (KC.q, 72, "Q = C5")] {
            expect(note(f, code) == midi,
                   "fifths: \(label) (got \(note(f, code).map(String.init) ?? "nothing"))")
        }
        expect(f.keys(.right).count == 18, "fifths: 18 chord keys (got \(f.keys(.right).count))")
        expect(f.rightPlaysChords, "fifths: right hand plays chords")

        // MARK: controls survive the merge
        //
        // Note rows and control keys are merged into one table with the notes
        // winning, so a row extended one key too far would silently swallow a
        // control and the only symptom would be a control that stopped working.
        func isControl(_ layout: Layout, _ code: UInt16, _ label: String) {
            let ok: Bool
            switch layout.actions[code] {
            case .pedal, .sustainLatch, .accidental, .transpose, .octave, .velocity: ok = true
            default: ok = false
            }
            expect(ok, "\(layout.name): \(label) is still a control")
        }
        for layout in [d, f] {
            isControl(layout, KC.space, "space")
            isControl(layout, KC.rightCommand, "right ⌘")
            isControl(layout, KC.f16, "F16")
            for (code, label) in [(KC.f3, "F3"), (KC.f4, "F4"), (KC.f5, "F5"), (KC.f6, "F6"),
                                  (KC.f7, "F7"), (KC.f8, "F8"), (KC.f9, "F9"), (KC.f10, "F10"),
                                  (KC.f11, "F11"), (KC.f12, "F12")] {
                isControl(layout, code, label)
            }
        }

        // The arrows are the one place the two families genuinely disagree:
        // pitch controls where there is no reachable function row, notes where
        // there is. `refreshAccidental` reads the map rather than ↑/↓ for
        // exactly this reason, so assert both sides of it.
        for (code, label) in [(KC.up, "↑"), (KC.down, "↓"), (KC.left, "←"), (KC.right, "→")] {
            isControl(f, code, label)
            expect(note(d, code) != nil, "diatonic: \(label) is a note")
        }
        expect(d.accidentalKeys.isEmpty, "diatonic: nothing bends the pitch by hand")
        expect(f.accidentalKeys.count == 2, "fifths: ↑ and ↓ bend the pitch")
        expect(d.actions[KC.escape] == nil, "diatonic: esc is unbound")

        // MARK: the column invariant
        //
        // The rows are an octave apart *and share their columns*, which is what
        // makes changing register a vertical hand shift with the same
        // fingering. Nothing enforces it but the order of four key lists, so a
        // key inserted into one row would silently shear the whole grid.
        let columns: [(String, [UInt16])] = [
            ("do",  [KC.z, KC.a, KC.q, KC.one]),
            ("re",  [KC.x, KC.s, KC.w, KC.two]),
            ("mi",  [KC.c, KC.d, KC.e, KC.three]),
            ("fa",  [KC.v, KC.f, KC.r, KC.four]),
            ("sol", [KC.b, KC.g, KC.t, KC.five]),
            ("la",  [KC.n, KC.h, KC.y, KC.six]),
            ("si",  [KC.m, KC.j, KC.u, KC.seven]),
            ("lead", [KC.shift, KC.f13, KC.tab, KC.grave]),
        ]
        for (name, codes) in columns {
            let notes = codes.compactMap { note(d, $0) }
            let stacked = notes.count == 4
                && zip(notes, notes.dropFirst()).allSatisfy { $1 - $0 == 12 }
            expect(stacked, "diatonic: the \(name) column stacks in octaves (got \(notes))")
        }

        // The right hand is one unbroken run, so unlike the overlapping left
        // rows it must have no repeats at all.
        let rightNotes = d.keys(.right).compactMap { note(d, $0) }
        expect(Set(rightNotes).count == rightNotes.count,
               "diatonic: the right hand repeats no note")
        expect(rightNotes.min() == 48 && rightNotes.max() == 83,
               "diatonic: the right hand spans C3–B5 (got \(rightNotes.min() ?? -1)–\(rightNotes.max() ?? -1))")
        expect(rightNotes.count == 21, "diatonic: the right hand is three octaves, 21 keys")

        print(failures.isEmpty ? "layout: PASS" : "layout: FAIL (\(failures.count))")
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
            audio.left.startNote(note, withVelocity: 100, onChannel: 0)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            peak = max(peak, recorder.peak)
            audio.left.stopNote(note, onChannel: 0)
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
            audio.left.startNote(note, withVelocity: 100, onChannel: 0)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            peakAfter = max(peakAfter, recorder.peak)
            audio.left.stopNote(note, onChannel: 0)
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

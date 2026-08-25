import SwiftUI

/// Lives in its own window alongside the instrument, never modal. Balance is
/// something you find by ear while playing, so the sliders have to be reachable
/// without the sound stopping — every change applies immediately and there is
/// no apply button.
struct PreferencesView: View {
    @ObservedObject var instrument: Instrument
    @ObservedObject var settings: Settings

    /// Fixed width, intrinsic height: the window is sized from `content`'s
    /// fitting size, so it ends up exactly as tall as its contents instead of
    /// stretching them across an arbitrary rectangle — and no taller than the
    /// screen, which is what the scroll view is for.
    static let width: CGFloat = 420

    var body: some View {
        ScrollView(.vertical) {
            content
        }
        // Only scrolls when there is something to scroll to: on a display tall
        // enough for the whole panel this behaves exactly like the plain view
        // it replaced, with no rubber-banding on a window that already fits.
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.width)
        .background(Palette.background)
    }

    /// The settings themselves, unscrolled. Kept separate because this — not
    /// the scroll view, which has no intrinsic height of its own — is what the
    /// window measures itself against.
    var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Keyboard") {
                Picker("", selection: Binding(
                    get: { instrument.keyboardModel },
                    set: { instrument.selectKeyboard($0) }
                )) {
                    ForEach(KeyboardModel.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(instrument.keyboardModel.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)

                Text(keyboardNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Levels") {
                level("Left", value: $settings.leftLevel, tint: Palette.leftHand)
                level("Right", value: $settings.rightLevel, tint: Palette.rightHand)

                HStack {
                    Text("50% is the tuned baseline, not unity.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Button("Reset") { settings.resetLevels() }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }

            section("Velocity") {
                velocity("Left", hand: .left, tint: Palette.leftHand)
                velocity("Right", hand: .right, tint: Palette.rightHand)

                HStack {
                    Text("Velocity is timbre as well as loudness — the bank has 16 layers.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Reset") { instrument.resetVelocities() }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }

            section("Sustain") {
                toggle("Right ⌘ latch — tap on, tap off",
                       isOn: $settings.sustainLatchEnabled)
                toggle("Trackpad — rest a thumb on the sustain half",
                       isOn: $settings.trackpadSustainEnabled)
                toggle("Space — hold (conflicts with H / J on this matrix)",
                       isOn: $settings.sustainSpaceEnabled)

                Text(rightCommandNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Trackpad") {
                TrackpadMeterView(instrument: instrument, settings: settings)

                labelled("Divider", readout: String(format: "%.0f%%", settings.trackpadDivider * 100)) {
                    Slider(value: $settings.trackpadDivider, in: 0.2...0.8)
                        .tint(Palette.control)
                }
                toggle("Swap halves — sustain on the right",
                       isOn: $settings.trackpadSwapped)

                Text("The other half is unassigned: somewhere to rest the second thumb without sustaining. Trackpad zones are live only while the instrument window is in front — here, the trackpad is just a pointer.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Key remaps") {
                ForEach(KeyRemap.Feature.allCases) { feature in
                    remap(feature)
                }

                toggle("Re-apply at launch — the remaps are cleared by a reboot",
                       isOn: $settings.applyRemapsOnLaunch)
                toggle("Undo on quit — leave the keyboard as Typano found it",
                       isOn: $settings.restoreRemapsOnQuit)

                if let error = instrument.remapError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.rightHand)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(remapNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Recording") {
                Picker("", selection: $settings.recordingFormat) {
                    ForEach(AudioRecorder.Container.allCases, id: \.rawValue) { container in
                        Text(container.label).tag(container.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker("", selection: $settings.recordingVideoFPS) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                toggle("Include the pointer in video", isOn: $settings.recordingShowsCursor)
                toggle("Show the REC badge in video takes",
                       isOn: $settings.recordingBadgeInVideo)

                Text(recordingNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)

                if !ScreenPermission.isGranted {
                    Button("Open Screen Recording settings") { ScreenPermission.openSettings() }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }
        }
        .padding(22)
        .frame(width: Self.width, alignment: .leading)
    }

    /// Which of the two isolation mechanisms is actually in force. The in-app
    /// one covers menu shortcuts; only the HID remap reaches ⌘-Tab and ⌘-Space,
    /// which WindowServer handles before any app sees them.
    private var rightCommandNote: String {
        instrument.rightCommandRemapped
            ? "Right ⌘ is remapped to F16, so it carries no modifier meaning anywhere. Left ⌘ keeps every shortcut."
            : "Right ⌘ is held back from the menu while it is the only ⌘ down, so it no longer fires ⌘H or ⌘Q. ⌘-Tab and ⌘-Space are handled above the app — only the remap below reaches those."
    }

    /// Says which of the two states the machine is actually in, rather than
    /// which one the app last asked for.
    private var remapNote: String {
        if instrument.capsLockRemapStale {
            return "The mapping is set, but this keyboard is still sending raw Caps Lock — hidutil only covers devices attached when it ran. Toggle Caps Lock off and on to cover it."
        }
        return "Applied with hidutil: no password, no restart, and cleared by a reboot. The mapping is system-wide and outlives the app, so quitting undoes what this run switched on — a remap set from Scripts/remap.sh beforehand is left alone."
    }

    /// The keyboard is not a preference about appearance — it decides which
    /// compromise the mapping makes, so say which one and why.
    private var keyboardNote: String {
        instrument.keyboardModel == .macBook
            ? "The built-in matrix cannot report enough right-hand keys at once, so the right hand plays one key per chord. On an external board it plays notes instead."
            : "n-key rollover, so the chord grid is unnecessary: both hands play notes, after FreePiano's default map. F5–F12 move octave and velocity per hand — only when macOS is sending real function keys."
    }

    private var recordingNote: String {
        let base = "Audio records the instrument's own output, straight off the graph — no other app, no microphone, and unaffected by which output device is selected."
        return ScreenPermission.isGranted
            ? base + " Video captures this window."
            : base + " Video additionally needs Screen Recording permission."
    }

    /// Reads live from hidutil rather than from a stored preference, so a remap
    /// applied by the script — or cleared by a reboot — shows up here.
    private func remap(_ feature: KeyRemap.Feature) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(
                get: { instrument.activeRemaps.contains(feature) },
                set: { instrument.setRemap(feature, enabled: $0) }
            )) {
                Text(feature.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .toggleStyle(.switch)
            .tint(Palette.control)

            Text(feature.detail)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.30))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Pieces

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
            content()
        }
    }

    private func level(_ title: String, value: Binding<Double>, tint: Color) -> some View {
        labelled(title, readout: gainLabel(value.wrappedValue)) {
            Slider(value: value, in: 0...1).tint(tint)
        }
    }

    private func velocity(_ title: String, hand: Hand, tint: Color) -> some View {
        labelled(title, readout: "\(instrument.velocity(hand))") {
            Slider(value: Binding(
                get: { Double(instrument.velocity(hand)) },
                set: { instrument.setVelocity(Int($0.rounded()), for: hand) }
            ), in: 1...127, step: 1)
            .tint(tint)
        }
    }

    private func labelled<Content: View>(
        _ title: String, readout: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 58, alignment: .leading)
            content()
            Text(readout)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
        }
        .toggleStyle(.switch)
        .tint(Palette.control)
    }

    private func gainLabel(_ level: Double) -> String {
        let dB = AudioEngine.gainDelta(for: level)
        if dB <= -89 { return "muted" }
        return String(format: "%+.1f dB", dB)
    }
}

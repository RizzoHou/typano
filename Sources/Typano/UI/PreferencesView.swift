import SwiftUI

/// Lives in its own window alongside the instrument, never modal. Balance is
/// something you find by ear while playing, so the sliders have to be reachable
/// without the sound stopping — every change applies immediately and there is
/// no apply button.
struct PreferencesView: View {
    @ObservedObject var instrument: Instrument
    @ObservedObject var settings: Settings

    /// Fixed width, intrinsic height: the window is sized from this view's
    /// fitting size, so it ends up exactly as tall as its contents instead of
    /// stretching them across an arbitrary rectangle.
    static let width: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Levels") {
                level("Melody", value: $settings.melodyLevel, tint: Palette.melody)
                level("Chords", value: $settings.chordLevel, tint: Palette.chord)

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

                if let error = instrument.remapError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.chord)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(remapNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(width: Self.width, alignment: .leading)
        .background(Palette.background)
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
        return "Applied with hidutil: no password, no restart, and cleared by a reboot. Scripts/remap.sh does the same thing from a shell if the app will not start."
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

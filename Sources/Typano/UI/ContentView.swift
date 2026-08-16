import SwiftUI

struct ContentView: View {
    @ObservedObject var instrument: Instrument

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 16) {
                header
                if !instrument.capsLockRemapped { capsLockHint }
                keyboard
                footer
            }
            .padding(20)

            if instrument.showRollover {
                RolloverTesterView(instrument: instrument)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: instrument.showRollover)
        .animation(.easeOut(duration: 0.2), value: instrument.capsLockRemapped)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text("Typano")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            stat("KEY", instrument.keyName, Palette.melody)
            stat("TRANSPOSE", instrument.transposeLabel, Palette.control)
            stat("OCTAVE", instrument.octaveLabel, Palette.control)
            stat("SUSTAIN", instrument.pedalDown ? "down" : "up",
                 instrument.pedalDown ? Palette.chord : .white.opacity(0.45))

            Spacer(minLength: 8)

            stat("LAYOUT", instrument.layout.name, Palette.chord)
            stat("SOUND", instrument.soundSource, .white.opacity(0.8))
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    // MARK: - Keyboard

    private var keyboard: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 5
            let unit = (geometry.size.width + gap) / PhysicalKeyboard.unitsPerRow
            let height = min(unit * 0.95, (geometry.size.height - gap * 4) / 5)

            VStack(spacing: gap) {
                ForEach(Array(PhysicalKeyboard.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gap) {
                        ForEach(row) { key in
                            KeyCapView(key: key, instrument: instrument)
                                .frame(width: key.width * unit - gap, height: height)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 18) {
            legend(Palette.melody, "melody — one octave per row")
            legend(Palette.chord, instrument.layout.chordRule)
            Spacer(minLength: 8)
            Text("space sustain · ↑↓ hold ♯♭ · ←→ transpose · ⌘L layout · ⌘R rollover · ⌘1–4 timbre")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    private var capsLockHint: some View {
        HStack(spacing: 8) {
            Text("⚠")
            Text("Caps Lock is still a toggle, so B3 is unavailable. Run `Scripts/capslock-remap.sh on` to remap it to F13.")
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.chord)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.chord.opacity(0.10))
        )
    }
}

import SwiftUI

struct ContentView: View {
    @ObservedObject var instrument: Instrument
    /// Its own observed object rather than reached through `instrument`: a
    /// nested ObservableObject does not propagate its changes through an outer
    /// one, so the badge would never tick.
    @ObservedObject var recording: RecordingController

    @State private var pulse = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 16) {
                header
                if let error = recording.lastError { recordingError(error) }
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

            stat("KEY", instrument.keyName, Palette.leftHand)
            stat("TRANSPOSE", instrument.transposeLabel, Palette.control)
            stat("OCTAVE", instrument.octaveLabel, Palette.control)
            stat("VELOCITY", instrument.velocityLabel, Palette.control)
            stat("SUSTAIN", sustainLabel,
                 instrument.pedalDown ? Palette.rightHand : .white.opacity(0.45))

            Spacer(minLength: 8)

            stat("KEYBOARD", instrument.keyboardModel.title, Palette.rightHand)
            stat("LAYOUT", instrument.layout.name, Palette.rightHand)
            stat("SOUND", instrument.soundSource, .white.opacity(0.8))

            if showBadge { badge }
        }
    }

    /// Hidden during a video take unless asked for, because the badge is inside
    /// the captured window and would otherwise be burnt into every recording.
    private var showBadge: Bool {
        guard recording.mode.isRecording else { return false }
        return !recording.isRecordingVideo || instrument.settings.recordingBadgeInVideo
    }

    private var badge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
                .opacity(pulse ? 0.25 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                           value: pulse)
            stat(recording.isRecordingVideo ? "REC VIDEO" : "REC", recording.elapsedLabel, .red)
        }
        .onAppear { pulse = true }
        .onDisappear { pulse = false }
    }

    /// Three sources can hold the pedal, so "down" alone is ambiguous.
    private var sustainLabel: String {
        instrument.pedalDown ? "down · \(instrument.sustainSource)" : "up"
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
            let rows = instrument.keyboardModel.rows
            let gap: CGFloat = 5
            let unit = (geometry.size.width + gap) / instrument.keyboardModel.unitsPerRow
            let rowCount = CGFloat(rows.count)
            let height = min(unit * 0.95,
                             (geometry.size.height - gap * (rowCount - 1)) / rowCount)

            VStack(spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gap) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                            Group {
                                if key.isGap {
                                    Color.clear
                                } else {
                                    KeyCapView(key: key, instrument: instrument)
                                }
                            }
                            .frame(width: max(0, key.width * unit - gap), height: height)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: 16) {
            TrackpadMeterView(instrument: instrument, settings: instrument.settings, height: 42)
                .frame(width: 68)

            VStack(alignment: .leading, spacing: 5) {
                legend(Palette.leftHand, instrument.layout.leftRule)
                legend(Palette.rightHand, instrument.layout.rightRule)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("sustain: trackpad rest · right ⌘ or esc latch · space hold")
                    .foregroundStyle(.white.opacity(0.45))
                Text(functionRowLine)
                    .foregroundStyle(.white.opacity(0.45))
                Text("↑↓ hold ♯♭ · ←→ transpose · ⌘L layout · ⌘R rollover · ⌘1–4 timbre · ⌘E record · ⌥⌘E video · ⌘, preferences")
                    .foregroundStyle(.white.opacity(0.35))
            }
            .font(.system(size: 10, design: .monospaced))
        }
    }

    /// The function row only reaches a key monitor when macOS is sending real
    /// F-keys, so say what it does rather than let it look broken.
    private var functionRowLine: String {
        instrument.keyboardModel.hasFunctionRow
            ? "F3/F4 key · F5–F8 octave L/R · F9–F12 velocity L/R"
            : "no function row drawn — use ⌘0 to reset, or Preferences"
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

    private func recordingError(_ message: String) -> some View {
        HStack(spacing: 8) {
            Text("⚠")
            Text(message)
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.rightHand)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.rightHand.opacity(0.10))
        )
    }

    private var capsLockHint: some View {
        HStack(spacing: 8) {
            Text("⚠")
            Text("Caps Lock is still a toggle, so its leading tone is unavailable. Turn on the Caps Lock remap in Preferences (⌘,).")
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.rightHand)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.rightHand.opacity(0.10))
        )
    }
}

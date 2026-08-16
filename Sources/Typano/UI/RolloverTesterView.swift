import SwiftUI

/// Measures what the keyboard matrix actually delivers. The design assumes the
/// left hand can hold several keys at once while the right hand cannot — this
/// panel is how that assumption gets checked instead of trusted.
struct RolloverTesterView: View {
    @ObservedObject var instrument: Instrument

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rollover tester")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("Mash as many keys as you can on one side at a time. The counters record what the hardware actually reported.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 26) {
                counter("HELD NOW", instrument.stats.current, Palette.control)
                counter("MAX TOTAL", instrument.stats.maxOverall, .white)
                counter("MAX LEFT", instrument.stats.maxLeft, Palette.melody)
                counter("MAX RIGHT", instrument.stats.maxRight, Palette.chord)
            }

            Button("Reset counters") { instrument.resetStats() }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .padding(18)
        .frame(width: 460, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func counter(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.40))
            Text("\(value)")
                .font(.system(size: 26, weight: .light, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

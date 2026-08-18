import SwiftUI

/// Live view of the trackpad: the divider, every contact, and which half is
/// currently sustaining.
///
/// Not decoration. The trackpad is the one input path that cannot be checked
/// from the development machine, so when sustain drops mid-phrase this is what
/// says whether the contact vanished or the zone logic misfired.
struct TrackpadMeterView: View {
    @ObservedObject var instrument: Instrument
    @ObservedObject var settings: Settings

    var height: CGFloat = 58

    private var sustainOnLeft: Bool { !settings.trackpadSwapped }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let split = size.width * settings.trackpadDivider

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                // The sustaining half, lit only while it is actually holding.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Palette.control.opacity(instrument.pedalDown ? 0.28 : 0.09))
                    .frame(width: sustainOnLeft ? split : size.width - split)
                    .offset(x: sustainOnLeft ? 0 : split)

                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 1)
                    .offset(x: split)

                ForEach(Array(instrument.trackpadContacts.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Palette.melody)
                        .frame(width: 11, height: 11)
                        // normalizedPosition has its origin at the lower left.
                        .offset(x: point.x * size.width - 5.5,
                                y: (1 - point.y) * size.height - 5.5)
                }

                Text(sustainOnLeft ? "sustain" : "—")
                    .trackpadZoneLabel()
                    .frame(width: split, height: size.height)

                Text(sustainOnLeft ? "—" : "sustain")
                    .trackpadZoneLabel()
                    .frame(width: size.width - split, height: size.height)
                    .offset(x: split)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .frame(height: height)
    }
}

private extension View {
    func trackpadZoneLabel() -> some View {
        self.font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.30))
    }
}

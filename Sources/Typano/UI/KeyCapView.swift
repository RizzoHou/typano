import SwiftUI

enum Palette {
    static let background = Color(red: 0.043, green: 0.051, blue: 0.063)
    static let melody = Color(red: 0.33, green: 0.73, blue: 1.00)
    static let chord = Color(red: 1.00, green: 0.69, blue: 0.31)
    static let control = Color(red: 0.72, green: 0.56, blue: 1.00)
    static let idle = Color.white.opacity(0.10)

    static func tint(_ role: KeyRole) -> Color {
        switch role {
        case .melody:     return melody
        case .chord:      return chord
        case .control:    return control
        case .unassigned: return idle
        }
    }
}

struct KeyCapView: View {
    let key: PhysicalKey
    @ObservedObject var instrument: Instrument

    @State private var rippleScale: CGFloat = 1
    @State private var rippleOpacity: Double = 0

    private var role: KeyRole {
        guard let code = key.code, let action = instrument.action(for: code) else { return .unassigned }
        return action.role
    }

    private var isActive: Bool {
        guard let code = key.code else { return false }
        return instrument.isLit(code)
    }

    private var caption: Instrument.Caption? {
        key.code.flatMap { instrument.caption(for: $0) }
    }

    private var tint: Color { Palette.tint(role) }
    private var assigned: Bool { role != .unassigned }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        ZStack {
            shape
                .fill(isActive ? tint.opacity(0.85) : tint.opacity(assigned ? 0.13 : 0.04))
                .overlay(shape.strokeBorder(tint.opacity(assigned ? 0.45 : 0.18), lineWidth: 1))
                .shadow(color: isActive ? tint.opacity(0.75) : .clear, radius: isActive ? 13 : 0)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(key.legend)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(isActive ? 0.75 : 0.32))
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, 3)

            if let caption {
                VStack(spacing: 0) {
                    Text(caption.primary)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? Palette.background : .white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let secondary = caption.secondary {
                        Text(secondary)
                            .font(.system(size: 8, weight: .regular, design: .rounded))
                            .foregroundStyle(isActive ? Palette.background.opacity(0.7) : .white.opacity(0.38))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, 6)
            }

            shape
                .stroke(tint, lineWidth: 2)
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)
                .allowsHitTesting(false)
        }
        .scaleEffect(isActive ? 0.965 : 1)
        .animation(.easeOut(duration: 0.10), value: isActive)
        .onChange(of: isActive) { _, nowActive in
            guard nowActive, assigned else { return }
            rippleScale = 1
            rippleOpacity = 0.9
            withAnimation(.easeOut(duration: 0.45)) {
                rippleScale = 1.9
                rippleOpacity = 0
            }
        }
    }
}

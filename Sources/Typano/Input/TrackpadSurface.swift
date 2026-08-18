import AppKit

/// The trackpad as an instrument surface.
///
/// A vertical divider splits it in two: one half sustains while a finger rests
/// on it, the other is deliberately inert — somewhere to park the other thumb
/// without sustaining. Resting is the whole point. A key has to be held down;
/// the trackpad only has to be touched, and it sits exactly where the thumbs
/// already are.
///
/// `NSTouch` on an indirect device is the public, documented route and needs no
/// Accessibility permission, which is the same bargain the key monitor makes.
final class TrackpadSurface: NSView {

    /// One live contact. `position` is 0…1 across the trackpad, origin at the
    /// lower left.
    struct Contact: Equatable {
        let position: CGPoint
    }

    var onContactsChanged: (([Contact]) -> Void)?

    private var contacts: [TouchID: CGPoint] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowedTouchTypes = [.indirect]
        // Without this a motionless finger is filtered out as a resting touch,
        // which is precisely the gesture this surface is built around.
        wantsRestingTouches = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Touches

    override func touchesBegan(with event: NSEvent) { absorb(event) }
    override func touchesMoved(with event: NSEvent) { absorb(event) }
    override func touchesEnded(with event: NSEvent) { absorb(event) }

    /// A cancelled touch counts as a release. Failing towards "sustain drops"
    /// rather than "sustain sticks" is the only safe direction — a stuck pedal
    /// ruins everything that comes after it.
    override func touchesCancelled(with event: NSEvent) { absorb(event) }

    private func absorb(_ event: NSEvent) {
        var live: [TouchID: CGPoint] = [:]
        for touch in event.touches(matching: .touching, in: self) {
            live[TouchID(touch.identity)] = touch.normalizedPosition
        }
        guard live != contacts else { return }
        contacts = live
        onContactsChanged?(contacts.values.map(Contact.init(position:)))
    }

    /// Losing focus produces no touch-ended events, so the surface has to be
    /// cleared by hand or a resting finger stays down forever.
    func clearContacts() {
        guard !contacts.isEmpty else { return }
        contacts = [:]
        onContactsChanged?([])
    }

    /// `NSTouch.identity` is only documented as `isEqual`-comparable, not as a
    /// stable pointer, so it is compared the way the documentation says.
    private struct TouchID: Hashable {
        let raw: any NSObjectProtocol & NSCopying

        init(_ raw: any NSObjectProtocol & NSCopying) { self.raw = raw }

        static func == (lhs: TouchID, rhs: TouchID) -> Bool { lhs.raw.isEqual(rhs.raw) }
        func hash(into hasher: inout Hasher) { hasher.combine(raw.hash) }
    }
}

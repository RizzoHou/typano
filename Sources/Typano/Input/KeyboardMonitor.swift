import AppKit

/// In-app key capture.
///
/// A local monitor sees events before the responder chain and can swallow them
/// by returning nil, which keeps Tab from moving focus and stops the system
/// beep on unmapped keys. Being local rather than a CGEventTap also means the
/// app needs no Accessibility permission.
final class KeyboardMonitor {
    var onKeyDown: ((UInt16) -> Void)?
    var onKeyUp: ((UInt16) -> Void)?
    /// Fired when Caps Lock arrives unremapped, i.e. as a toggle we cannot use.
    var onRawCapsLock: (() -> Void)?
    /// Right ⌘ pressed and released on its own — the sustain latch toggle.
    var onSustainLatchToggle: (() -> Void)?

    /// Whether a pointer event should be dropped. A thumb resting on the
    /// trackpad drags the cursor around and can tap-to-click; when the
    /// instrument is the thing being played, none of that should reach the UI.
    var shouldSwallowPointer: (NSEvent) -> Bool = { _ in false }

    private var monitor: Any?

    /// Right ⌘ is a latch, so the toggle fires on release — and only if the key
    /// went down and came back up without anything else being pressed. That
    /// keeps right ⌘ usable as an ordinary menu modifier.
    private var rightCommandDown = false
    private var rightCommandClean = false

    private static let pointerTypes: Set<NSEvent.EventType> = [
        .mouseMoved,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        .scrollWheel,
    ]

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .keyDown, .keyUp, .flagsChanged,
                .mouseMoved,
                .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                .scrollWheel,
            ]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            // macOS auto-repeats held keys; without this a sustained note
            // machine-guns.
            if event.isARepeat { return nil }

            // Anything pressed while right ⌘ is down makes it a real
            // ⌘-combination rather than a latch tap.
            if rightCommandDown { rightCommandClean = false }

            // ⌘ combinations belong to the menu, never to the instrument.
            if event.modifierFlags.contains(.command) { return event }

            onKeyDown?(event.keyCode)
            return nil

        case .keyUp:
            // Reported even under ⌘. Bailing to the menu on key-up used to
            // strand the note and leave the key permanently dead, because
            // `held` never lost the code.
            onKeyUp?(event.keyCode)
            return event.modifierFlags.contains(.command) ? event : nil

        case .flagsChanged:
            return handleFlags(event)

        default:
            if Self.pointerTypes.contains(event.type), shouldSwallowPointer(event) { return nil }
            return event
        }
    }

    /// Every modifier is reported, not just the two that carry notes. The
    /// rollover tester is the only way to find out which keys the matrix
    /// actually blocks, and it can only measure what reaches `held`.
    private func handleFlags(_ event: NSEvent) -> NSEvent? {
        let code = event.keyCode

        if code == KC.capsLock {
            // Unremapped Caps Lock: a toggle with no key-up, so note duration
            // is undefined and it cannot serve as a note key.
            onRawCapsLock?()
            return nil
        }

        if code == KC.function {
            // fn carries no device-dependent bit; the cooked flag is all there
            // is, and on some machines the key never reaches us at all.
            if event.modifierFlags.contains(.function) { onKeyDown?(code) } else { onKeyUp?(code) }
            return event
        }

        // `.shift` and friends cannot tell left from right, so read the
        // device-dependent bits instead.
        guard let mask = KC.DeviceFlag.mask(for: code) else { return event }
        let down = event.modifierFlags.rawValue & mask != 0

        if code == KC.rightCommand { trackRightCommand(down: down) }

        if down { onKeyDown?(code) } else { onKeyUp?(code) }

        // Shift plays a note, so its event stops here. Everything else is
        // passed through — the system's own view of which modifiers are down
        // has to stay correct or ⌘ shortcuts break.
        return (code == KC.shift || code == KC.rightShift) ? nil : event
    }

    private func trackRightCommand(down: Bool) {
        if down {
            rightCommandDown = true
            rightCommandClean = true
            return
        }
        let wasTap = rightCommandDown && rightCommandClean
        rightCommandDown = false
        rightCommandClean = false
        if wasTap { onSustainLatchToggle?() }
    }

    /// Called when the app loses focus: a modifier released while we were not
    /// looking would otherwise leave the tap detector armed.
    func resetTransientState() {
        rightCommandDown = false
        rightCommandClean = false
    }
}

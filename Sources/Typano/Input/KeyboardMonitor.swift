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

    private var monitor: Any?

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // ⌘ combinations belong to the menu, never to the instrument.
        if event.modifierFlags.contains(.command) { return event }

        switch event.type {
        case .keyDown:
            // macOS auto-repeats held keys; without this a sustained note
            // machine-guns.
            if event.isARepeat { return nil }
            onKeyDown?(event.keyCode)
            return nil

        case .keyUp:
            onKeyUp?(event.keyCode)
            return nil

        case .flagsChanged:
            return handleFlags(event)

        default:
            return event
        }
    }

    private func handleFlags(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.rawValue

        switch event.keyCode {
        case KC.shift:
            // `.shift` alone cannot tell the two Shift keys apart, so read the
            // device-dependent bits instead.
            if flags & KC.DeviceFlag.leftShift != 0 { onKeyDown?(KC.shift) }
            else { onKeyUp?(KC.shift) }
            return nil

        case KC.rightShift:
            if flags & KC.DeviceFlag.rightShift != 0 { onKeyDown?(KC.rightShift) }
            else { onKeyUp?(KC.rightShift) }
            return nil

        case KC.capsLock:
            // Unremapped Caps Lock: a toggle with no key-up, so note duration
            // is undefined and it cannot serve as a note key.
            onRawCapsLock?()
            return nil

        default:
            return event
        }
    }
}

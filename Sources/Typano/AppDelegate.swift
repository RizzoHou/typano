import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let instrument = Instrument()
    private lazy var recording = RecordingController(instrument: instrument,
                                                     settings: instrument.settings)
    private var window: NSWindow!
    private var preferences: NSWindow?
    private var recordAudioItem: NSMenuItem!
    private var recordVideoItem: NSMenuItem!
    private var revealItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Typano"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Palette.background)
        window.contentView = instrumentSurface()
        // The cursor is hidden while a thumb is on the pad, so the monitor has
        // to keep seeing where the pointer goes in order to bring it back when
        // it reaches the title bar.
        window.acceptsMouseMovedEvents = true
        window.center()
        window.makeKeyAndOrderFront(nil)

        observeFocus()

        NSApp.activate()
        instrument.start()
        window.makeFirstResponder(window.contentView)
        instrument.setInstrumentFocused(window.isKeyWindow)
        recording.attach(window: window)
    }

    /// An unfinalised MPEG-4 has no `moov` atom and will not open at all, so a
    /// take in progress has to be closed before the process goes away.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recording.mode.isRecording else { return .terminateNow }
        recording.finishBeforeTermination {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Content

    /// The trackpad surface is the content view and the SwiftUI tree lives
    /// inside it, because indirect touches are delivered to the first
    /// responder — not to whatever sits under the pointer.
    private func instrumentSurface() -> NSView {
        let surface = TrackpadSurface(frame: .zero)
        let hosting = NSHostingView(
            rootView: ContentView(instrument: instrument, recording: recording))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: surface.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
        ])
        instrument.attach(trackpad: surface)
        return surface
    }

    // MARK: - Focus

    private func observeFocus() {
        let centre = NotificationCenter.default
        centre.addObserver(forName: NSApplication.didResignActiveNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.instrument.setAppActive(false)
        }
        centre.addObserver(forName: NSApplication.didBecomeActiveNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.instrument.setAppActive(true)
            // The remap table can change while the app is in the background —
            // a reboot clears it, and Scripts/remap.sh can set it.
            self?.instrument.refreshRemapState()
        }
        centre.addObserver(forName: NSWindow.didBecomeKeyNotification,
                           object: window, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.window.makeFirstResponder(self.window.contentView)
            self.instrument.setInstrumentFocused(true)
        }
        centre.addObserver(forName: NSWindow.didResignKeyNotification,
                           object: window, queue: .main) { [weak self] _ in
            self?.instrument.setInstrumentFocused(false)
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item("Preferences…", #selector(showPreferences), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Typano",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Typano",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let instrumentItem = NSMenuItem()
        let instrumentMenu = NSMenu(title: "Instrument")
        instrumentMenu.addItem(item("Switch Chord Layout", #selector(switchLayout), "l"))
        instrumentMenu.addItem(item("Rollover Tester", #selector(toggleRollover), "r"))
        instrumentMenu.addItem(.separator())
        for (index, name) in SoundLibrary.timbreNames.enumerated() {
            let entry = item(name, #selector(selectTimbre(_:)), "\(index + 1)")
            entry.tag = index
            instrumentMenu.addItem(entry)
        }
        instrumentMenu.addItem(.separator())
        instrumentMenu.addItem(item("Reset Transpose", #selector(resetTranspose), "0"))
        instrumentItem.submenu = instrumentMenu
        mainMenu.addItem(instrumentItem)

        // Shortcuts avoid ⇧ entirely: Shift is a melody key (B2), so ⇧⌘V would
        // sound a note at the moment recording starts. They also avoid ⌘A ⌘C
        // ⌘V ⌘X ⌘Z ⌘S, which the main menu would otherwise steal from the save
        // panel's own text field. ⌥ is in no layout, so it makes no sound.
        let recordItem = NSMenuItem()
        let recordMenu = NSMenu(title: "Record")
        recordAudioItem = item("Record Audio", #selector(toggleAudioRecording), "e")
        recordVideoItem = item("Record Video", #selector(toggleVideoRecording), "e")
        recordVideoItem.keyEquivalentModifierMask = [.command, .option]
        recordMenu.addItem(recordAudioItem)
        recordMenu.addItem(recordVideoItem)
        recordMenu.addItem(.separator())
        revealItem = item("Reveal Last Recording in Finder", #selector(revealRecording), "")
        recordMenu.addItem(revealItem)
        recordItem.submenu = recordMenu
        mainMenu.addItem(recordItem)

        NSApp.mainMenu = mainMenu
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    // MARK: - Actions

    @objc private func switchLayout() { instrument.switchLayout() }

    @objc private func toggleRollover() { instrument.toggleRollover() }

    @objc private func selectTimbre(_ sender: NSMenuItem) { instrument.selectTimbre(sender.tag) }

    @objc private func resetTranspose() { instrument.resetTranspose() }

    @objc private func toggleAudioRecording() { recording.toggleAudio() }

    @objc private func toggleVideoRecording() { recording.toggleVideo() }

    @objc private func revealRecording() { recording.revealLastRecording() }

    /// Called for key-equivalent dispatch as well as for display, so this is
    /// also what stops ⌘E re-entering while its own save panel is open.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem {
        case recordAudioItem:
            menuItem.title = isAudioRecording ? "Stop Recording Audio" : "Record Audio"
            return recording.mode != .choosingLocation && !recording.isRecordingVideo
        case recordVideoItem:
            menuItem.title = recording.isRecordingVideo ? "Stop Recording Video" : "Record Video"
            return recording.mode != .choosingLocation && !isAudioRecording
        case revealItem:
            return recording.lastRecording != nil
        default:
            return true
        }
    }

    private var isAudioRecording: Bool {
        if case .audio = recording.mode { return true }
        return false
    }

    /// Non-modal and never closes the instrument: the point is to hear a
    /// setting change while the note that revealed the problem is still
    /// ringing.
    @objc private func showPreferences() {
        if preferences == nil { preferences = makePreferencesWindow() }
        instrument.refreshRemapState()
        // Re-checked on every open, not just the first: the window is long-lived
        // and may come back on a shorter display, or under a Dock that has since
        // appeared.
        if let panel = preferences {
            fitToScreen(panel)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func makePreferencesWindow() -> NSWindow {
        let root = PreferencesView(instrument: instrument, settings: instrument.settings)

        // Measured against the *unscrolled* content: a scroll view is happy at
        // any height, so asking the real root view how tall it wants to be
        // answers "whatever you give me". A hard-coded 500 pt left the content
        // stranded in the top half; this opens exactly as tall as the settings
        // are, and `fitToScreen` takes it from there.
        let natural = NSHostingView(rootView: root.content).fittingSize

        let controller = NSHostingController(rootView: root)
        controller.view.frame.size = natural

        let panel = NSWindow(contentViewController: controller)
        panel.styleMask = [.titled, .closable, .resizable]
        panel.title = "Typano Preferences"
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor(Palette.background)
        panel.isReleasedWhenClosed = false
        panel.setContentSize(natural)
        // Width is fixed by the design; only the height gives, and only down to
        // where a section is still worth reading.
        panel.contentMinSize = NSSize(width: PreferencesView.width, height: 260)
        panel.contentMaxSize = NSSize(width: PreferencesView.width,
                                      height: .greatestFiniteMagnitude)
        // Resizable, so the green button exists; a settings panel has no
        // business going full screen, and this turns it back into plain zoom —
        // which here means "as tall as the screen allows".
        panel.collectionBehavior.insert(.fullScreenNone)
        panel.center()
        return panel
    }

    /// Keeps the window inside the screen it opens on. Without this a panel
    /// taller than the display hangs off the bottom, and the sections down there
    /// cannot be reached at all.
    private func fitToScreen(_ panel: NSWindow) {
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = panel.frame
        guard frame.height > visible.height else { return }
        frame.size.height = visible.height
        frame.origin.y = visible.minY
        frame.origin.x = min(max(frame.origin.x, visible.minX),
                             visible.maxX - frame.width)
        panel.setFrame(frame, display: true)
    }
}

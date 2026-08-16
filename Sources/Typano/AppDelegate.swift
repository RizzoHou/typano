import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let instrument = Instrument()
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 580),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Typano"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Palette.background)
        window.contentView = NSHostingView(rootView: ContentView(instrument: instrument))
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.activate()
        instrument.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
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

        NSApp.mainMenu = mainMenu
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    // MARK: - Actions

    @objc private func switchLayout() { instrument.switchLayout() }

    @objc private func toggleRollover() { instrument.showRollover.toggle() }

    @objc private func selectTimbre(_ sender: NSMenuItem) { instrument.selectTimbre(sender.tag) }

    @objc private func resetTranspose() { instrument.resetTranspose() }
}

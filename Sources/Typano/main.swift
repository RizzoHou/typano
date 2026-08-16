import AppKit

if CommandLine.arguments.contains("--check-sound") {
    SoundCheck.run()
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--try-instrument"),
   CommandLine.arguments.indices.contains(flag + 1) {
    SoundCheck.tryInstrument(path: CommandLine.arguments[flag + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

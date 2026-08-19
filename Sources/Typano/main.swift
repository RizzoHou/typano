import AppKit

if CommandLine.arguments.contains("--check-sound") {
    SoundCheck.run()
    exit(0)
}

if CommandLine.arguments.contains("--check-remap") {
    let ok = CommandLine.arguments.contains("--write")
        ? SoundCheck.remap() && SoundCheck.remapWrite()
        : SoundCheck.remap()
    exit(ok ? 0 : 1)
}

if CommandLine.arguments.contains("--check-restart") {
    exit(SoundCheck.restart() ? 0 : 1)
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

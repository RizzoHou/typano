import AVFoundation
import AudioToolbox

/// One loadable sampler instrument.
struct SoundSource {
    let label: String
    let apply: (AVAudioUnitSampler) throws -> Void
}

/// Where the sounds come from.
///
/// Logic Pro's sampled pianos are far better than the system General MIDI
/// bank, and they are already on this machine, so we reference them in place
/// when present. Nothing is copied or redistributed; if Logic is absent — or
/// if its consolidated sample files turn out not to resolve outside Logic —
/// the built-in DLS bank keeps the instrument playable.
enum SoundLibrary {

    static let dlsURL = URL(fileURLWithPath:
        "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")

    /// Where a downloaded sound bank might live. The app bundle sits at
    /// `<project>/.build/Typano.app`, so the project's own `Sounds/` is two
    /// levels up from the bundle.
    private static var soundBankDirectories: [URL] {
        var directories: [URL] = []
        if let override = ProcessInfo.processInfo.environment["TYPANO_SOUNDS"] {
            directories.append(URL(fileURLWithPath: override))
        }
        directories.append(
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sounds"))
        directories.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Typano/Sounds"))
        directories.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sounds"))
        return directories
    }

    /// First `.sf2` found in any of the search directories.
    static func locateSoundFont() -> URL? {
        let fileManager = FileManager.default
        for directory in soundBankDirectories {
            guard let walker = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in walker where url.pathExtension.lowercased() == "sf2" {
                return url
            }
        }
        return nil
    }

    /// The downloaded Salamander grand — a real sampled piano with velocity
    /// layers and release samples, which is what makes it read as a piano
    /// rather than as a synthesiser pretending to be one.
    static let soundFont = SoundSource(label: "Salamander Grand Piano") { sampler in
        guard let url = locateSoundFont() else { throw CocoaError(.fileNoSuchFile) }
        try sampler.loadSoundBankInstrument(
            at: url,
            program: 0,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )
    }

    static func dls(program: UInt8, label: String) -> SoundSource {
        SoundSource(label: label) { sampler in
            try sampler.loadSoundBankInstrument(
                at: dlsURL,
                program: program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
        }
    }

    /// Each timbre is a list of candidates, best first; the first that loads wins.
    static let timbres: [[SoundSource]] = [
        [
            soundFont,
            dls(program: 0,  label: "Apple DLS Grand Piano"),
        ],
        [dls(program: 4,  label: "Electric Piano")],
        [dls(program: 11, label: "Vibraphone")],
        [dls(program: 48, label: "String Ensemble")],
    ]

    static let timbreNames = ["Grand Piano", "Electric Piano", "Vibraphone", "Strings"]
}

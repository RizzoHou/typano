import AVFoundation
import CoreAudio

/// melody ─┐
///          ├─ submix ─ reverb ─ main out
/// chords ─┘
///
/// Two samplers rather than one so melody and chords can be placed and
/// balanced independently — the MacBook's stereo image is one of the few
/// genuine advantages this instrument has over a real piano.
final class AudioEngine {
    private let engine = AVAudioEngine()
    private let submix = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()

    let melody = AVAudioUnitSampler()
    let chords = AVAudioUnitSampler()

    /// Human-readable name of whichever candidate actually loaded.
    private(set) var sourceLabel = "—"

    func start() {
        requestSmallBuffer()

        for node in [melody, chords, submix, reverb] as [AVAudioNode] {
            engine.attach(node)
        }
        engine.connect(melody, to: submix, format: nil)
        engine.connect(chords, to: submix, format: nil)
        engine.connect(submix, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 18

        // A gentle spread: melody just left of centre, chords just right.
        melody.stereoPan = -15
        chords.stereoPan = 15
        chords.overallGain = -2

        load(timbre: 0)

        do {
            try engine.start()
        } catch {
            sourceLabel = "audio engine failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func load(timbre index: Int) -> String {
        let candidates = SoundLibrary.timbres[index]
        for candidate in candidates {
            do {
                try candidate.apply(melody)
                try candidate.apply(chords)
                sourceLabel = candidate.label
                return sourceLabel
            } catch {
                continue
            }
        }
        sourceLabel = "no sound source available"
        return sourceLabel
    }

    /// Ask CoreAudio for a small buffer. Best effort — the device may refuse,
    /// and a demo is still perfectly usable at the default size.
    private func requestSmallBuffer(frames: UInt32 = 128) {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress, 0, nil, &size, &device) == noErr else { return }

        var value = frames
        var bufferAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        AudioObjectSetPropertyData(
            device, &bufferAddress, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

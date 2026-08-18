import AVFoundation
import CoreAudio

/// melody ─┐
///          ├─ submix ─ reverb ─ limiter ─ main out
/// chords ─┘
///
/// Two samplers rather than one so melody and chords can be placed and
/// balanced independently — the MacBook's stereo image is one of the few
/// genuine advantages this instrument has over a real piano.
final class AudioEngine {
    private let engine = AVAudioEngine()
    private let submix = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()

    /// Catches the peaks that appear when a sustained melody stacks on a
    /// four-note chord. Insurance, not sound design: at the baseline levels it
    /// should never engage, and it only earns its keep when a level slider is
    /// pushed up.
    private let limiter = AVAudioUnitEffect(audioComponentDescription:
        AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0))

    let melody = AVAudioUnitSampler()
    let chords = AVAudioUnitSampler()

    /// Baseline gain per zone, in dB, at level 0.5.
    ///
    /// Melody sits above chords because a chord fires four notes at once and
    /// sums roughly 12 dB louder than a single note at the same velocity — the
    /// left zone reads as quiet even when it is nominally the same level.
    private static let melodyBaselineGain: Float = 3
    private static let chordBaselineGain: Float = -1

    private var melodyLevel = 0.5
    private var chordLevel = 0.5

    /// Human-readable name of whichever candidate actually loaded.
    private(set) var sourceLabel = "—"

    func start() {
        requestSmallBuffer()

        for node in [melody, chords, submix, reverb, limiter] as [AVAudioNode] {
            engine.attach(node)
        }
        engine.connect(melody, to: submix, format: nil)
        engine.connect(chords, to: submix, format: nil)
        engine.connect(submix, to: reverb, format: nil)
        engine.connect(reverb, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 18

        // A gentle spread: melody just left of centre, chords just right.
        melody.stereoPan = -15
        chords.stereoPan = 15

        load(timbre: 0)

        do {
            try engine.start()
        } catch {
            sourceLabel = "audio engine failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Levels

    /// Below this the zone is muted outright rather than merely quiet.
    static let muteThreshold = 0.02
    /// `overallGain` is documented as −90…+12 dB, so the floor is absolute
    /// rather than an offset from the baseline — otherwise the two zones mute
    /// at different, out-of-range values.
    private static let silence: Float = -90

    /// Level → gain offset in dB, asymmetric on purpose: the baseline already
    /// sits close to the headroom ceiling, so there is far more room to go down
    /// than up.
    ///
    ///   0.5 → 0 dB · 1.0 → +6 dB · 0.0 → −40 dB · below 0.02 → silence
    static func gainDelta(for level: Double) -> Float {
        if level < muteThreshold { return silence }
        return Float((level - 0.5) * (level >= 0.5 ? 12 : 80))
    }

    func setMelodyLevel(_ level: Double) {
        melodyLevel = level
        applyLevels()
    }

    func setChordLevel(_ level: Double) {
        chordLevel = level
        applyLevels()
    }

    /// Re-asserted after every bank load — `loadSoundBankInstrument` resets the
    /// sampler's gain, so a ⌘1–⌘4 timbre switch would otherwise silently drop
    /// the user's balance back to the default.
    private func applyLevels() {
        melody.overallGain = Self.gain(baseline: Self.melodyBaselineGain, level: melodyLevel)
        chords.overallGain = Self.gain(baseline: Self.chordBaselineGain, level: chordLevel)
    }

    private static func gain(baseline: Float, level: Double) -> Float {
        level < muteThreshold ? silence : baseline + gainDelta(for: level)
    }

    @discardableResult
    func load(timbre index: Int) -> String {
        let candidates = SoundLibrary.timbres[index]
        for candidate in candidates {
            do {
                try candidate.apply(melody)
                try candidate.apply(chords)
                sourceLabel = candidate.label
                applyLevels()
                return sourceLabel
            } catch {
                continue
            }
        }
        sourceLabel = "no sound source available"
        applyLevels()
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

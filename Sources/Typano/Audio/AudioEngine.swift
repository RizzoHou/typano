import AVFoundation
import CoreAudio
import os

/// left  ──┐
///          ├─ submix ─ reverb ─ limiter ─ main out
/// right ──┘
///
/// Two samplers rather than one so the two hands can be placed and
/// balanced independently — the MacBook's stereo image is one of the few
/// genuine advantages this instrument has over a real piano.
///
/// Main-thread only. The two route-change triggers arrive on arbitrary threads
/// and hop to main before touching anything here.
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

    let left = AVAudioUnitSampler()
    let right = AVAudioUnitSampler()

    /// Baseline gain per hand, in dB, at level 0.5.
    ///
    /// A chord fires four notes at once and sums roughly 12 dB louder than a
    /// single note at the same velocity, so a hand playing chords needs to sit
    /// lower to read as the same loudness. Which baseline the right hand takes
    /// therefore depends on the layout, not on the hand — on an external
    /// keyboard it plays single notes like the left one.
    private static let noteBaselineGain: Float = 3
    private static let chordBaselineGain: Float = -1

    private var leftLevel = 0.5
    private var rightLevel = 0.5
    private var rightBaselineGain = AudioEngine.chordBaselineGain

    /// Human-readable name of whichever candidate actually loaded.
    private(set) var sourceLabel = "—"
    /// Engine state, kept separate from `sourceLabel` so a failure does not
    /// erase which bank is loaded and recovery can restore the timbre name.
    private(set) var lastFailure: String?

    /// A route change strands every sounding note and re-initialises the
    /// samplers out from under a latched CC64. The owner has to clear its own
    /// idea of what is held — `Performer.allNotesOff()` cannot reach
    /// `Instrument.held`.
    var onRouteChange: (() -> Void)?
    /// Fired on main whenever the header's SOUND stat should change.
    var onStatusChange: ((String) -> Void)?

    /// Reloaded after a rate change, so a rebuild restores the timbre the user
    /// actually chose rather than snapping back to the grand piano.
    private var currentTimbre = 0
    /// Rate the chain is currently wired for. Assigned only on a successful
    /// bring-up, which is what makes a failed attempt reload the bank on the
    /// next try without needing a separate flag.
    private var connectedSampleRate: Double = 0

    private var configurationObserver: NSObjectProtocol?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var pendingRebuild: DispatchWorkItem?
    private var rebuildAttempt = 0
    /// False from the moment a route change is seen until the graph is back.
    private var routeSettled = true
    /// Counted so `--check-restart` can assert a burst collapses into one rebuild.
    private(set) var rebuildCount = 0

    private static let settleDelay: TimeInterval = 0.25
    private static let maxRetryDelay: TimeInterval = 5
    private static let log = Logger(subsystem: "com.rizzohou.typano", category: "audio")

    var isRunning: Bool { engine.isRunning }

    /// What the SOUND stat shows.
    var statusLabel: String { lastFailure == nil ? sourceLabel : "no audio output" }

    /// Whether the engine's output unit actually followed the system default
    /// device. `AVAudioEngine` is documented to follow it, but that is the one
    /// assumption this fix rests on that cannot be checked by reading code —
    /// so the diagnostic prints it rather than trusting it.
    var deviceReport: String {
        let wanted = Self.defaultOutputDevice() ?? 0
        let bound = engine.outputNode.auAudioUnit.deviceID
        let agree = wanted == bound ? "follows default" : "DIVERGED"
        return "default=\(wanted) bound=\(bound) (\(agree)) rate=\(connectedSampleRate)"
    }

    // MARK: - Lifecycle

    /// Only the device-independent setup lives here; everything that depends on
    /// *which* output device is playing is in `bringUp()`, which the route
    /// change re-runs verbatim.
    func start() {
        for node in [left, right, submix, reverb, limiter] as [AVAudioNode] {
            engine.attach(node)
        }

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 18

        // A gentle spread, following the hands: left of centre, right of it.
        left.stereoPan = -15
        right.stereoPan = 15

        observeRouteChanges()
        bringUp(reason: "launch")
    }

    /// Everything that is a property of *a particular output device*: buffer
    /// size, connection formats, and the engine start itself.
    ///
    /// Launch and route change run this identically, and that is the point —
    /// the path the user exercises by unplugging headphones is the path
    /// `--check-sound` exercises at launch, and only one of the two can be
    /// tested from Linux.
    @discardableResult
    private func bringUp(reason: String) -> Bool {
        // A no-op at launch, and usually a no-op on a route change too — the
        // engine stops and uninitialises itself before posting. Saying it
        // anyway is what keeps the two paths byte-identical.
        engine.stop()
        engine.reset()

        requestSmallBuffer()

        // Must come before any `connect`: an invalid format there raises an
        // Objective-C exception, which is a crash rather than something Swift
        // can catch.
        guard let format = processingFormat() else {
            fail("no output device", reason: reason)
            return false
        }

        // Rebuilt with an explicit format, never `nil`: `nil` means "keep the
        // source node's current output format", which is precisely the old
        // device's format we are trying to move off.
        engine.connect(left, to: submix, format: format)
        engine.connect(right, to: submix, format: format)
        engine.connect(submix, to: reverb, format: format)
        engine.connect(reverb, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)

        // The bank survives a plain stop/start — the launch path proves it, by
        // loading before the engine is ever initialised. What it may not
        // survive is the sampler being re-initialised at a *new* sample rate,
        // so that is the only case that pays for a reload; speakers and
        // headphones are usually both 48 kHz and skip it.
        if format.sampleRate != connectedSampleRate {
            load(timbre: currentTimbre)
        } else {
            applyLevels()
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            fail(error.localizedDescription, reason: reason)
            return false
        }

        connectedSampleRate = format.sampleRate
        lastFailure = nil
        onStatusChange?(statusLabel)
        Self.log.info("""
            up (\(reason, privacy: .public)) rate=\(format.sampleRate) \
            default=\(Self.defaultOutputDevice() ?? 0) \
            bound=\(self.engine.outputNode.auAudioUnit.deviceID)
            """)
        return true
    }

    /// The format to run the chain at: the new device's rate, always stereo.
    ///
    /// Stereo regardless of what the device offers, because the two zones are
    /// panned and `mainMixerNode` — whose output tracks the output node as long
    /// as we never set it ourselves — is what maps stereo onto a mono or
    /// multi-channel device.
    private func processingFormat() -> AVAudioFormat? {
        let hardware = engine.outputNode.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0 else { return nil }
        return AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: 2)
    }

    private func fail(_ message: String, reason: String) {
        lastFailure = message
        onStatusChange?(statusLabel)
        Self.log.error("down (\(reason, privacy: .public)): \(message, privacy: .public)")
    }

    // MARK: - Route changes

    /// Two triggers, because neither is sufficient alone.
    ///
    /// The engine's notification fires on a *format* change — a different
    /// sample rate or channel count, or a device disappearing — which is the
    /// only way to hear about the current device changing its own rate in Audio
    /// MIDI Setup. It is not dependable for a swap between two devices that
    /// happen to agree on format. The CoreAudio listener fires on every
    /// default-device change whatever the format, and knows nothing about rates.
    ///
    /// They are deduplicated by the debounce rather than by identity, because a
    /// single device change legitimately emits several of both while the HAL
    /// settles; pairing them up is not winnable.
    private func observeRouteChanges() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil                      // runs on AVFoundation's thread; we
        ) { [weak self] _ in                // hop ourselves and never block it
            self?.routeChanged("engine configuration")
        }

        var address = Self.defaultDeviceAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.routeChanged("default output device")
        }
        // Held in a property so the same block object can be handed to
        // `AudioObjectRemovePropertyListenerBlock`; removal matches on identity.
        deviceListener = listener
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
        if status != noErr {
            Self.log.error("device listener not installed: \(status)")
        }
    }

    /// Both triggers land here, from arbitrary threads.
    private func routeChanged(_ reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rebuildAttempt = 0
            if self.routeSettled {
                self.routeSettled = false
                // Those notes are already gone and CC64 went with them. Say so
                // now, even if the graph takes seconds to come back — a lit key
                // with no sound is the thing that reads as broken.
                self.onRouteChange?()
            }
            self.onStatusChange?("switching output…")
            self.schedule(after: Self.settleDelay, reason: reason)
        }
    }

    /// Trailing-edge debounce over a single slot: a burst of triggers, or a
    /// pending retry overtaken by a new change, collapses to one rebuild.
    private func schedule(after delay: TimeInterval, reason: String) {
        pendingRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuild(reason: reason) }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func rebuild(reason: String) {
        pendingRebuild = nil
        rebuildCount += 1

        if bringUp(reason: reason) {
            rebuildAttempt = 0
            routeSettled = true
            restoreRecordingTap()
            // Again, now that the samplers can actually hear CC64 = 0 and
            // CC123 — sent to a stopped engine they are simply dropped.
            onRouteChange?()
            return
        }

        // The new device may still be enumerating; a Bluetooth one certainly
        // is. Back off, but never stop: an instrument that is silent with no
        // way back is the bug this whole change exists to remove.
        rebuildAttempt += 1
        let delay = min(Self.maxRetryDelay,
                        Self.settleDelay * pow(2, Double(rebuildAttempt)))
        schedule(after: delay, reason: reason)
    }

    /// Manual retry: coming back to the app should not mean waiting out a timer.
    func recoverIfNeeded() {
        guard !engine.isRunning else { return }
        routeChanged("app activated")
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

    func setLevel(_ level: Double, for hand: Hand) {
        switch hand {
        case .left:  leftLevel = level
        case .right: rightLevel = level
        }
        applyLevels()
    }

    /// Follows the active layout: a right hand playing single notes wants the
    /// note baseline, one playing chords wants the lower chord baseline.
    func setRightPlaysChords(_ chords: Bool) {
        rightBaselineGain = chords ? Self.chordBaselineGain : Self.noteBaselineGain
        applyLevels()
    }

    /// Re-asserted after every bank load — `loadSoundBankInstrument` resets the
    /// sampler's gain, so a ⌘1–⌘4 timbre switch would otherwise silently drop
    /// the user's balance back to the default.
    private func applyLevels() {
        left.overallGain = Self.gain(baseline: Self.noteBaselineGain, level: leftLevel)
        right.overallGain = Self.gain(baseline: rightBaselineGain, level: rightLevel)
    }

    private static func gain(baseline: Float, level: Double) -> Float {
        level < muteThreshold ? silence : baseline + gainDelta(for: level)
    }

    @discardableResult
    func load(timbre index: Int) -> String {
        currentTimbre = index
        let candidates = SoundLibrary.timbres[index]
        for candidate in candidates {
            do {
                try candidate.apply(left)
                try candidate.apply(right)
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

    // MARK: - Recording tap

    /// The tap goes on the main mixer, not on the limiter's output. The limiter
    /// is the last *effect*, but the main mixer is the last node the app
    /// controls — a recording taken before it would not be what the user heard.
    private var recordingTap: (size: AVAudioFrameCount, block: AVAudioNodeTapBlock)?

    /// Buffers arrive in this format. It follows the output device, so it can
    /// change under the app's feet when the route changes.
    var recordingFormat: AVAudioFormat { engine.mainMixerNode.outputFormat(forBus: 0) }

    /// AVAudioEngine allows exactly one tap per bus, so this is exclusive by
    /// construction. The block is retained so the tap can be put back after a
    /// configuration change tears the graph down.
    func installRecordingTap(bufferSize: AVAudioFrameCount = 4096,
                             _ block: @escaping AVAudioNodeTapBlock) {
        removeRecordingTap()
        recordingTap = (bufferSize, block)
        // `format: nil` is deliberate — passing a format that differs from the
        // bus's own raises an ObjC exception, and after a route change the bus
        // format is exactly what we no longer know.
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil, block: block)
    }

    func removeRecordingTap() {
        guard recordingTap != nil else { return }
        recordingTap = nil
        engine.mainMixerNode.removeTap(onBus: 0)
    }

    /// Called after a rebuild: the graph teardown drops installed taps, so an
    /// in-progress recording would silently stop receiving audio. Idempotent,
    /// and a no-op when nothing is recording.
    private func restoreRecordingTap() {
        guard let tap = recordingTap else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: tap.size, format: nil, block: tap.block)
    }

    // MARK: - Device

    private static let defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultDeviceAddress
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &device) == noErr, device != 0 else { return nil }
        return device
    }

    /// Ask CoreAudio for a small buffer on whatever the default output device
    /// is *now* — re-read on every bring-up, because the device that mattered
    /// at launch is not the one playing after the user picks headphones.
    ///
    /// Best effort throughout. A Bluetooth device will refuse 128 frames or
    /// clamp it upward and that is fine: its own transport latency dwarfs
    /// anything a buffer size can buy. The request is clamped into the range
    /// the device advertises so we never write an illegal value, and skipped
    /// when it is already right — every hardware reconfiguration is a chance to
    /// provoke the very notification that brought us here.
    private func requestSmallBuffer(frames: UInt32 = 128) {
        guard let device = Self.defaultOutputDevice() else { return }

        var sizeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var rangeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var wanted = frames
        var range = AudioValueRange()
        var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
        if AudioObjectGetPropertyData(device, &rangeAddress, 0, nil, &rangeSize, &range) == noErr,
           range.mMinimum > 0, range.mMaximum >= range.mMinimum {
            wanted = UInt32(max(range.mMinimum, min(range.mMaximum, Double(frames))))
        }

        var current = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &sizeAddress, 0, nil, &size, &current) == noErr,
           current == wanted { return }

        var value = wanted
        AudioObjectSetPropertyData(device, &sizeAddress, 0, nil,
                                   UInt32(MemoryLayout<UInt32>.size), &value)
    }

    deinit {
        pendingRebuild?.cancel()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        if let deviceListener {
            var address = Self.defaultDeviceAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address,
                DispatchQueue.main, deviceListener)
        }
    }

    // MARK: - Test seams

    /// `--check-restart` only. Posts the notification the engine itself posts,
    /// rather than calling the handler: it is the *registration* — matching on
    /// name and on `object: engine` — that is easiest to get wrong and
    /// impossible to see by reading.
    func simulateConfigurationChange() {
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
    }

    /// `--check-restart` only. The HAL listener cannot be fired without actually
    /// changing the system's output device, so this enters at the handler and
    /// proves only the shared half of that path.
    func simulateDefaultDeviceChange() {
        routeChanged("simulated device change")
    }
}

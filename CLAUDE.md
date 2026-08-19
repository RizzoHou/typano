# CLAUDE.md

Typano is a **macOS** app. This repo lives on a Linux box, which cannot build, run, or hear it. See `README.md` for the instrument spec and `DEVCHANGELOG.md` for why past decisions were made.

## Dev loop

Edit locally, sync, build over ssh. Never edit files on the Mac — local is the source of truth.

```bash
bash Scripts/sync.sh                                    # rsync -> entry-mac:~/projects/typano
ssh entry-mac 'cd ~/projects/typano && bash Scripts/build.sh release'
ssh entry-mac 'cd ~/projects/typano && .build/arm64-apple-macosx/release/Typano --check-sound'
```

Sync before **every** remote command batch; the usual failure is debugging a stale remote tree.

`Scripts/install.sh` (build + bundle + install to `/Applications`) and `Scripts/run.sh` (build + bundle + launch in place) both have to be run **by the user, at the Mac** — `open` from an ssh session puts the window on a session nobody is looking at, and the whole point of launching is that a human plays it.

## What can and cannot be verified here

Compilation, and `Typano --check-sound` / `--try-instrument <path>` (headless, runnable over ssh). `--check-sound` starts the **real** `AudioEngine`, not just a throwaway sampler, so it does prove the effect chain instantiates and connects, and it prints the level→dB curve.

Three more headless checks, all starting the real engine and all asserting rather than printing:

- `--check-restart` — forces the output-device recovery path and asserts a burst of triggers collapses to one rebuild, the engine restarts, and the bank and both tuned gains survive.
- `--check-remap` — the live `hidutil` table. `--write` additionally round-trips a write and restores the table to what it found.
- `--check-recording <path>` — records a real arpeggio, asserts on a **non-zero peak** (silence would still produce a valid file), triggers a graph rebuild mid-take, and reopens the result.

**Not verifiable from Linux:** latency, timbre, loudness balance, key rollover, whether a resting thumb keeps being reported, light effects, anything about how it feels — and everything about video recording, since ScreenCaptureKit needs a GUI session and a TCC grant. The user is the only sensor for those — ask, don't assert.

## Rules

- **Build with SwiftPM, not `xcodebuild`.** There is deliberately no `.xcodeproj`. Scripts export `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; never run `sudo xcode-select` — the Mac's global state stays untouched.
- **`Sounds/` must stay in `.rsync-exclude`.** It holds a 1.2 GB sound bank that exists only on the Mac. `sync.sh` uses `--delete`; dropping the exclusion destroys it.
- **Key layouts are compiled-in Swift values** (`Model/Layouts.swift`), not resource files — SwiftPM resource bundles complicate the hand-rolled `.app`.
- **`notes.md`, `cof.md`, `cot.md` are user-edit-only.** Read them; never write them. They are gitignored.
- **Windows are sized from their content, not from a rect.** Preferences is an `NSHostingController` sized to `fittingSize`; a hard-coded `contentRect` strands SwiftUI content in the top half, because the view stretches and its children do not.
- **The app is installed by `Scripts/install.sh`, not run from `.build`.** An installed bundle cannot see the repo's `Sounds/`, because that search path is two levels up from the bundle; the installer links `~/Library/Application Support/Typano/Sounds` instead. Dropping the link makes the app fall back to the system GM bank *silently*.
- **`Resources/AppIcon.icns` is generated, not hand-edited.** `swift Scripts/make-icon.swift` renders it with CoreGraphics; `--sheet` also writes a 16→256 contact sheet, which is the only way to catch a design that dissolves below 64 px. The `.icns` is committed, so an ordinary build never runs the generator — but `sync.sh --delete` will remove a freshly generated one from the Mac unless it is pulled back and committed first.
- **Ad-hoc signing resets the Screen Recording grant on every rebuild**, because the designated requirement is the binary's cdhash. `bundle.sh` prefers a self-signed `Typano Dev` identity when the keychain has one. The symptom of getting this wrong is recording failing while System Settings still shows the toggle as on.
- **Settings persist in `UserDefaults` under `com.rizzohou.typano`** and survive rebuilds. Changing a default in `Settings.swift` does nothing on a machine that has already run the app — that is the "my change had no effect" trap. Clear with `ssh entry-mac 'defaults delete com.rizzohou.typano'`.

## Input gotchas

These are load-bearing and easy to regress:

- Filter `event.isARepeat` on keyDown, or held notes machine-gun via macOS key repeat.
- **Left `⌘` keyDown goes to the menu; right `⌘` does not** (`KeyboardMonitor.rightCommandIsolated`) — while right ⌘ is the only ⌘ down the keystroke stays with the instrument, so holding it plays notes instead of firing ⌘H / ⌘Q. Two consequences: **no shortcut answers to right ⌘** (⌘L, ⌘R, ⌘1–4 are left-⌘ only), and `leftCommandDown` must stay tracked from `flagsChanged` or the isolation starts swallowing real shortcuts.
- **`⌘` keyUp must still reach `onKeyUp`** whichever ⌘ it is, or the note is stranded and the key stays dead because `held` never loses the code.
- **Right ⌘ latches, it never holds** — the toggle fires on release and only if nothing else was pressed during the hold. Isolation makes a held right ⌘ survivable; latching is still what the design wants, because resting beats holding for a whole phrase.
- **A local monitor cannot reach ⌘-Tab / ⌘-Space** — WindowServer handles those before any app. Only the HID remap (right ⌘ → F16, from Preferences or `Scripts/remap.sh on rightcmd`) removes them. F16 is bound to the same `.sustainLatch`, and unlike right ⌘ it is an ordinary key, so `Instrument` toggles the latch on its keyDown rather than from the monitor's tap detection.
- `.shift` cannot distinguish left from right Shift; read the device-dependent bits (`KC.DeviceFlag`).
- **Modifier `flagsChanged` events are reported but not swallowed** — except Shift, which plays a note. The rollover tester can only measure what reaches `held`, and swallowing the rest desyncs the system's idea of which modifiers are down.
- Caps Lock is a toggle with no key-up. It is bound as **F13** and requires the remap, applied from Preferences (`Scripts/remap.sh on` still works if the app will not start).
- **`hidutil` replaces the whole `UserKeyMapping` table on every call**, so all remaps must be set in one command — that is why `Scripts/remap.sh` sets both and `capslock-remap.sh` is a shim. `KeyRemap.apply` also carries across entries Typano does not own; drop that and the app silently destroys any unrelated remap the user has set, which is what `remap.sh off` does.
- **`hidutil` output is an OpenStep plist, which has no number type.** `PropertyListSerialization` parses it, but every value arrives as `String` — so `HIDKeyboardModifierMappingSrc as? NSNumber` yields nil and the app reports "nothing remapped" while both remaps are active, with a correct-looking parse and the right entry count. Parse via `String` → `UInt64`. An empty table prints `(null)`, whose non-dictionary member fails a whole-array `[[String: Any]]` cast, so `compactMap` the members instead.
- **Remap state is read from `hidutil`, never remembered.** The table survives app restarts and is cleared by a reboot, so an inferred flag can only ever be wrong; it is re-read on app activation and when Preferences opens. `hidutil --set` covers only devices attached when it ran, so "the mapping is set" and "this keyboard obeys it" are different facts — `sawRawCapsLock` is what tells them apart.
- The local `NSEvent` monitor needs no Accessibility permission. Keep it that way — do not reach for `CGEventTap`.
- **Anything that silences the instrument must clear `Instrument.held` too.** `Performer.allNotesOff()` cannot reach it; that is what `Instrument.panic()` is for.
- **A panel that accepts typing must call `Instrument.setNoteInputSuspended(true)`.** The monitor swallows every non-⌘ keyDown and turns it into a note — Shift included, since it is B2 — so without this, typing a filename into a save panel plays a scale and the text field receives nothing. It is a depth counter, not a flag, and it deliberately keeps delivering key-*ups* so a key released behind the panel still ends its note.
- **No menu shortcut may use ⇧**, for the same reason: Shift sounds B2 as the shortcut fires. Avoid ⌘A/⌘C/⌘V/⌘X/⌘Z/⌘S too — the main menu outranks the save panel's field editor and would break editing inside a panel the app itself opened.

## Trackpad

- `TrackpadSurface` is the window's `contentView` with the SwiftUI tree as a subview, because indirect touches go to the **first responder**, not to whatever is under the pointer.
- **`wantsRestingTouches = true` is load-bearing.** Without it a motionless finger is filtered out as a resting touch — which is the entire gesture this surface exists for.
- Zones are live only while the **instrument window is key**. In the preferences window the trackpad is an ordinary pointer, which is what makes the sliders draggable while the instrument keeps sounding.
- Pointer-event swallowing is scoped to the instrument window's **content view**, not the window. Scoping it to the window kills the close and minimise buttons; widening it past the window kills the menu bar. Cursor hiding follows the same rect, so the pointer reappears the moment it reaches the title bar.
- `NSTouch` needs no Accessibility permission either — same bargain as the key monitor. Do not reach for private `MultitouchSupport`.

## Sound

Primary voice is the Salamander SF2 (`Scripts/fetch-sounds.sh`), falling back to the system GM bank. Logic Pro's sampled pianos are **not** usable — see `DEVCHANGELOG.md` 2026-08-16 before trying again.

- **`loadSoundBankInstrument` resets `overallGain`**, so `AudioEngine.load(timbre:)` re-applies the levels after every load. Reorder or drop that call and a ⌘1–⌘4 timbre switch silently throws away the user's balance.
- **`AVAudioEngine` stops and uninitialises itself when the output device changes, and never restarts itself.** `AudioEngine.bringUp()` is shared by launch and recovery on purpose — the path a user exercises by unplugging headphones is the path `--check-sound` exercises at launch, and only one of the two can be tested from Linux. Two triggers feed it (the engine notification misses same-format device swaps; the CoreAudio listener misses rate changes), deduplicated by debounce rather than by identity.
- **Reconnect before `prepare()`.** `prepare()` on a graph that is not connected raises an **Objective-C exception**, which Swift cannot catch — a crash, not a `throw`. Same for `engine.connect` with an invalid format, which is why `processingFormat()` returns nil and bails instead.
- **Rebuilding the graph drops installed taps.** `restoreRecordingTap()` puts a recording tap back; without it a take in progress silently becomes silence with no error. The recorder resamples through an `AVAudioConverter` because the new device may run at a different rate.
- **Level 0.5 is the tuned baseline, not unity.** Melody sits above chords by design: a chord fires four notes at once and sums roughly 12 dB louder than a single note at the same velocity.

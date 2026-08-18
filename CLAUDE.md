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

`Scripts/run.sh` (build + bundle + launch) has to be run **by the user, at the Mac** — `open` from an ssh session puts the window on a session nobody is looking at, and the whole point of launching is that a human plays it.

## What can and cannot be verified here

Compilation, and `Typano --check-sound` / `--try-instrument <path>` (headless, runnable over ssh). `--check-sound` starts the **real** `AudioEngine`, not just a throwaway sampler, so it does prove the effect chain instantiates and connects, and it prints the level→dB curve.

**Not verifiable from Linux:** latency, timbre, loudness balance, key rollover, whether a resting thumb keeps being reported, light effects, anything about how it feels. The user is the only sensor for those — ask, don't assert.

## Rules

- **Build with SwiftPM, not `xcodebuild`.** There is deliberately no `.xcodeproj`. Scripts export `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; never run `sudo xcode-select` — the Mac's global state stays untouched.
- **`Sounds/` must stay in `.rsync-exclude`.** It holds a 1.2 GB sound bank that exists only on the Mac. `sync.sh` uses `--delete`; dropping the exclusion destroys it.
- **Key layouts are compiled-in Swift values** (`Model/Layouts.swift`), not resource files — SwiftPM resource bundles complicate the hand-rolled `.app`.
- **`notes.md`, `cof.md`, `cot.md` are user-edit-only.** Read them; never write them. They are gitignored.
- **Windows are sized from their content, not from a rect.** Preferences is an `NSHostingController` sized to `fittingSize`; a hard-coded `contentRect` strands SwiftUI content in the top half, because the view stretches and its children do not.
- **Settings persist in `UserDefaults` under `com.rizzohou.typano`** and survive rebuilds. Changing a default in `Settings.swift` does nothing on a machine that has already run the app — that is the "my change had no effect" trap. Clear with `ssh entry-mac 'defaults delete com.rizzohou.typano'`.

## Input gotchas

These are load-bearing and easy to regress:

- Filter `event.isARepeat` on keyDown, or held notes machine-gun via macOS key repeat.
- **Left `⌘` keyDown goes to the menu; right `⌘` does not** (`KeyboardMonitor.rightCommandIsolated`) — while right ⌘ is the only ⌘ down the keystroke stays with the instrument, so holding it plays notes instead of firing ⌘H / ⌘Q. Two consequences: **no shortcut answers to right ⌘** (⌘L, ⌘R, ⌘1–4 are left-⌘ only), and `leftCommandDown` must stay tracked from `flagsChanged` or the isolation starts swallowing real shortcuts.
- **`⌘` keyUp must still reach `onKeyUp`** whichever ⌘ it is, or the note is stranded and the key stays dead because `held` never loses the code.
- **Right ⌘ latches, it never holds** — the toggle fires on release and only if nothing else was pressed during the hold. Isolation makes a held right ⌘ survivable; latching is still what the design wants, because resting beats holding for a whole phrase.
- **A local monitor cannot reach ⌘-Tab / ⌘-Space** — WindowServer handles those before any app. Only the HID remap (`Scripts/remap.sh on rightcmd`, right ⌘ → F16) removes them. F16 is bound to the same `.sustainLatch`, and unlike right ⌘ it is an ordinary key, so `Instrument` toggles the latch on its keyDown rather than from the monitor's tap detection.
- `.shift` cannot distinguish left from right Shift; read the device-dependent bits (`KC.DeviceFlag`).
- **Modifier `flagsChanged` events are reported but not swallowed** — except Shift, which plays a note. The rollover tester can only measure what reaches `held`, and swallowing the rest desyncs the system's idea of which modifiers are down.
- Caps Lock is a toggle with no key-up. It is bound as **F13** and requires `Scripts/remap.sh on`.
- **`hidutil` replaces the whole `UserKeyMapping` table on every call**, so all remaps must be set in one command — `Scripts/remap.sh` exists for that reason and `capslock-remap.sh` is now a shim forwarding to it.
- The local `NSEvent` monitor needs no Accessibility permission. Keep it that way — do not reach for `CGEventTap`.
- **Anything that silences the instrument must clear `Instrument.held` too.** `Performer.allNotesOff()` cannot reach it; that is what `Instrument.panic()` is for.

## Trackpad

- `TrackpadSurface` is the window's `contentView` with the SwiftUI tree as a subview, because indirect touches go to the **first responder**, not to whatever is under the pointer.
- **`wantsRestingTouches = true` is load-bearing.** Without it a motionless finger is filtered out as a resting touch — which is the entire gesture this surface exists for.
- Zones are live only while the **instrument window is key**. In the preferences window the trackpad is an ordinary pointer, which is what makes the sliders draggable while the instrument keeps sounding.
- Pointer-event swallowing is scoped to the instrument window's **content view**, not the window. Scoping it to the window kills the close and minimise buttons; widening it past the window kills the menu bar. Cursor hiding follows the same rect, so the pointer reappears the moment it reaches the title bar.
- `NSTouch` needs no Accessibility permission either — same bargain as the key monitor. Do not reach for private `MultitouchSupport`.

## Sound

Primary voice is the Salamander SF2 (`Scripts/fetch-sounds.sh`), falling back to the system GM bank. Logic Pro's sampled pianos are **not** usable — see `DEVCHANGELOG.md` 2026-08-16 before trying again.

- **`loadSoundBankInstrument` resets `overallGain`**, so `AudioEngine.load(timbre:)` re-applies the levels after every load. Reorder or drop that call and a ⌘1–⌘4 timbre switch silently throws away the user's balance.
- **Level 0.5 is the tuned baseline, not unity.** Melody sits above chords by design: a chord fires four notes at once and sums roughly 12 dB louder than a single note at the same velocity.

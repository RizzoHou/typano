# DEVCHANGELOG

The append-only development record for Typano: why things changed, what was tried, and what it cost. Newest entry first; entries are never edited or removed — a reversed decision gets a new entry naming what it supersedes. Standing rules and invariants live in `CLAUDE.md`, not here; user-facing release notes would live in `CHANGELOG.md`.

## 2026-08-25 — Mac mode, and the right hand FreePiano actually ships

- **What**: Two corrections to the same day's external-keyboard work, both from playing it. The 98/full-size bottom rows are now drawn as the board reports itself in **Mac mode** — Alt sends ⌘, Win sends ⌥, Ctrl stays ⌃ — so the sustain latch is right ⌘ on all three keyboards and the Esc latch is gone. The diatonic right hand is now the arrow cluster plus the keypad: 21 keys, C3–B5, exactly three octaves.

- **Why Esc was wrong**: it was invented to solve a problem that does not exist. The premise was "a 98 ends its bottom row Alt / Fn with no right ⌘", which is true of the *keycaps* and false of the *key codes* — every PC board sold here has a Mac mode, and in it the Alt right of the space bar is right ⌘. The drawing said `rightOption` for that key, which is what made the board look like it had no latch. Two keys that both latch is also worse than one: the habit built on the built-in keyboard is the thing worth preserving.

- **Why the arrows became notes**: F3/F4 already carry the key signature, which is FreePiano's own answer to accidentals, so the held-♯/♭ arrows were paying for a function the function row already provides. `Layout.accidentalKeys` is now derived from the map and `refreshAccidental` reads it — asking `held.contains(KC.up)` directly would have bent the whole keyboard a semitone for as long as ↑ rang as F3.

- **What FreePiano's map actually says**: fetched `data/freepiano.map` from a mirror of the SourceForge tree (`tiwb/freepiano` on GitHub is DMCA-blocked). Its right hand is 27 keys, not 21: `left down right up` = C3–F3, then the keypad to B5, then `Del End PgDn Ins Home PgUp` = C6–A6. The first 21 are shipped verbatim. The last six are deliberately dropped — a 98 arranges that cluster differently on every board and often omits it, and one mapping that plays identically on both external boards is worth more than six notes at the top of the register. Restoring them is one line in `rightRun`.

- **Why the 98's editing keys are no longer drawn at all**: the previous entry recorded them as an unverifiable guess; they were also wrong. Now that nothing is mapped there, drawing a guessed key is strictly worse than drawing none — it invites pressing something that does nothing.

- **Files**: `Sources/Typano/Model/{Layout,Layouts,KeyboardModel,Instrument}.swift`, `Sources/Typano/UI/{PhysicalKeyboard,ContentView,PreferencesView}.swift`, `Sources/Typano/Audio/SoundCheck.swift`, `Sources/Typano/Input/KeyCodes.swift`, `CLAUDE.md`

- **Verify**: `--check-layout` PASS, with two new assertions that would have caught the first bug from Linux — every mapped note key must appear in that model's drawn geometry, and both external models must draw a right ⌘. Also asserts the run is 21 keys spanning C3–B5, that the arrows are notes on the diatonic map and controls on the chord grid, and that Esc is unbound. `--check-sound`, `--check-restart`, `--check-recording` still pass; installed and smoke-tested on the 98 in the GUI.

- **Supersedes**: the "three deviations" and "not verified" bullets of *2026-08-25 — The mapping follows the keyboard, after FreePiano*.

## 2026-08-25 — The mapping follows the keyboard, after FreePiano

- **What**: One mapping became three keyboards. The built-in MacBook keeps the melody-plus-chord-grid layout; external 98 and full-size (ANSI 104/108) boards get FreePiano's default map key for key — four diatonic rows across the main block, the numeric keypad and editing cluster carrying the right hand. Picked from Instrument ▸ Keyboard or Preferences, persisted. New `--check-layout` asserts the maps.

- **Why the chord grid is not a preference**: it exists because the built-in matrix cannot report enough simultaneous right-hand keys to play a chord as notes — that is the sentence in `Layouts.swift` that justified it. An external board is n-key rollover, so on those keyboards the workaround has nothing left to work around and the right hand plays real notes. Tying it to the keyboard rather than to a menu keeps the reason and the setting in the same place; a user who picks "98" cannot accidentally keep a compromise they no longer need.

- **Why copy FreePiano's pitches exactly**: Z=C2, A=C3, Q=C4 (middle C), 1=C5, keypad 1=C4, PgUp=A6. Anchoring anywhere else would have been a strictly private dialect — FreePiano's sheet music and anyone's habits are worth more than an octave of convenience, and F5–F8 move the register anyway. It also costs the left hand an octave versus the old MacBook anchor, which is why the two families deliberately differ: the MacBook layout has three rows centred on middle C and no room for a fourth.

- **Why the audio channels changed axis**: they were melody and chords. On an external board the right hand plays melody, so the old names were actively wrong. They are now left and right hand, which makes FreePiano's per-channel octave and velocity implementable one-for-one — and made "velocity" a visible concept for the first time: it was three constants in `Performer`, and is now live state on `Instrument`, in the header, on F9–F12, and on a Preferences slider. The stored `UserDefaults` keys are still `melodyLevel` / `chordLevel`; renaming them would have silently reset a balance tuned by ear.

- **Why the baseline gain follows the layout, not the hand**: the −12 dB the right channel carried is compensation for four notes summing at once, not a property of being the right hand. A right hand playing single notes now takes the note baseline, so the diatonic layout does not arrive quiet.

- **Three deviations from FreePiano, all deliberate**: the arrows stay ♯/♭ and key ∓ rather than becoming C3–F3, which are duplicated on the left hand anyway and are the cheapest four notes in the map; the pedal keys stay (FreePiano has none — it pins the left channel's sustain on in the map header); F1/F2 keyboard groups are not implemented, because the layout follows the keyboard here rather than a key. Esc was added as a second sustain latch: a 98 usually ends its bottom row Alt / Fn, with no right ⌘ for the latch to live on.

- **Files**: `Sources/Typano/Model/{Layout,Layouts,KeyboardModel,Instrument,Settings}.swift`, `Sources/Typano/UI/{PhysicalKeyboard,ContentView,PreferencesView,KeyCapView}.swift`, `Sources/Typano/Audio/{AudioEngine,Performer,SoundCheck}.swift`, `Sources/Typano/Input/KeyCodes.swift`, `CLAUDE.md`

- **Verify**: `--check-layout` (new) asserts the anchors, that every row of every drawn keyboard sums to the same width, that the four rows stack in octaves column by column, that the right-hand run repeats no note, and that no control key was swallowed by a lengthened note row — it caught four wrong expectations and one useless assertion on its first run. `--check-sound`, `--check-restart`, `--check-remap`, `--check-recording` all still pass. **Not verified**: the drawn geometry. `screencapture` over ssh dies with "could not create image from display" for want of a TCC grant, so which editing keys sit in the 98's right-hand column is a guess — vendors disagree, and the mapping is by key code, so a wrong drawing still plays correctly.

## 2026-08-23 — The fix was right and the app was old: driving the GUI from ssh

- **What**: The undo shipped in the previous entry did not appear on the Mac, because `/Applications/Typano.app` was four days old — building over ssh writes `.build/`, and only `Scripts/install.sh` touches the bundle the Dock launches. Installing over ssh fixed it. `NSAppleScriptEnabled` added to the bundle so the red-button path can be exercised from a shell.

- **Why it looked like the fix failed**: `--check-remap --write` passed and the app still misbehaved, which reads as a bad fix but was two different binaries. The headless checks run `.build/...`; the user runs the Dock icon. Any change the user will judge by launching the app now has to be installed, not just built.

- **Also wrong in `CLAUDE.md`**: it claimed `install.sh` needed a human at the Mac. It does not — it never calls `open`. Only `run.sh` does.

- **Why enable AppleScript**: `osascript -e 'tell application "Typano" to close window 1'` is the red button, and Cocoa's Standard Suite provides it for one Info.plist key with no dictionary of our own. That turns "does `applicationWillTerminate` fire when the window closes" from a claim into a check — the class of question this project could previously only hand back to the user.

- **Verify**: end to end against the live table, three runs. Empty → launch → 2 entries → close window 1 → process gone, table empty. And the ownership case: Caps Lock set from the shell *before* launch → 2 entries while running → only Caps Lock left after the close, so the app took back exactly what it added.

## 2026-08-23 — Quitting takes the remaps back down

- **What**: The app now undoes the `hidutil` remaps it turned on when it quits — red button, ⌘Q or logout — instead of leaving Caps Lock and right ⌘ rewired system-wide until a reboot or a manual `Scripts/remap.sh off`. New Preferences toggle "Undo on quit", on by default, and `applicationWillTerminate` was simply absent before this.

- **Why the counterpart was missing**: "Re-apply at launch" reads as a session-scoped convenience, but `hidutil` writes a per-boot, system-wide property that outlives the process — so applying at launch without undoing at quit is a one-way change to every other app's keyboard. Nothing puts it back on its own, and the app had no termination hook at all.

- **Why session ownership rather than a remembered table**: restoring the table as it was found would delete a remap the user set from `Scripts/remap.sh` *before* launching, and re-add one they deliberately switched off in Preferences *during* the session. `KeyRemap.Session` tracks only what the app's own writes turned on, drops ownership of anything cleared behind its back, and quitting subtracts exactly that set. Launch also unions rather than assigns now, for the same reason — it was silently dropping a script-set remap that was not in `remapsOnLaunch`.

- **Why not route the undo through `setRemaps`**: that stores `remapsOnLaunch`, so undoing through it would erase the very set "Re-apply at launch" exists to re-apply — the app would restore correctly once and then come up unremapped forever.

- **Files**: `Sources/Typano/Input/KeyRemap.swift`, `Sources/Typano/Model/Instrument.swift`, `Sources/Typano/Model/Settings.swift`, `Sources/Typano/AppDelegate.swift`, `Sources/Typano/UI/PreferencesView.swift`, `Sources/Typano/Audio/SoundCheck.swift`, `CLAUDE.md`

- **Verify**: `--check-remap --write` now plays the whole lifecycle against the live table and asserts on it — a shell-set remap before launch, the launch auto-apply on top, then the quit undo — proving only what the run added comes off and that a remap toggled off in-app is not resurrected. What Linux cannot prove is that `applicationWillTerminate` fires from the red button; that needs the Mac.

## 2026-08-19 — A video take that will not stop, and a preferences window taller than the screen

- **What**: Two bugs found by playing the previous entry's build. Stopping a video take failed with `RPRecordingErrorDomain -5814`, and the preferences window ran off the bottom of the display with its last sections unreachable.

- **Why the stop failed**: `ScreenRecorder.stop()` did `removeRecordingOutput` **and then** `stopCapture`, which is one teardown too many. `removeRecordingOutput` is itself a stop — it ends the recording and starts finalising the file, asynchronously, over the connection the stream owns. Stopping the capture in the next breath pulls that connection out from under the finalisation, so the take dies with `-5814`, which the ReplayKit header spells `RPRecordingErrorFailedApplicationConnectionInvalid`: "failed during recording, application connection invalid". The footage was fine; the file never got its `moov` atom. Stopping the capture alone both ends the recording and finalises it, so that is now the only call. Audio-only recording never had this — it is a graph tap, not ScreenCaptureKit, and `--check-recording` covers it.

- **Why the error name was worth decoding**: `-5814` says nothing on its own and searching for it returns nothing useful. The enum lives in `ReplayKit.framework/Headers/RPError.h` inside the Mac's SDK, one `grep` away over ssh, and the comment on the case named the mechanism directly. Reading the header beat two web searches.

- **Also fixed in the same path**: three callbacks can report the same take — `didStopWithError`, `recordingOutputDidFinishRecording`, `recordingOutput(_:didFailWithError:)` — and the old code let a second one through to `onUnexpectedStop`, which surfaces an error *after* a successful stop. Delivery is now once per take, gated on `destination` being non-nil, and a stream reporting its own shutdown during a deliberate stop is ignored because it says nothing about the file. A watchdog finishes the take if no callback arrives at all, since nothing else did and the HUD would sit on "recording" forever.

- **Why the window overflowed**: sizing a window to its content's `fittingSize` is right up until the content is taller than the display, and then it is the same bug as the hard-coded rect it replaced — content that exists but cannot be reached. The settings now live in a `ScrollView`, and the window clamps to `visibleFrame` on **every** open rather than only at creation, because it is long-lived and can come back on a shorter screen.

- **Paid lesson — a scroll view has no height to measure**: moving the content into a `ScrollView` breaks the `fittingSize` measurement that sized the window, because a scroll view answers "whatever you give me" to any height question. The fix is to keep the unscrolled content reachable as its own property and measure *that* in a throwaway `NSHostingView`, then host the scrolling version. Measuring the real root view yields a window a few points tall.

- **Rejected**: shortening the panel by cutting the explanatory notes under each section. They are what make the remap and trackpad states legible, and the panel would grow past the screen again on the next feature. Also rejected: a tabbed preferences window — six short sections read better as one column, and scrolling costs nothing on a display that fits them.

- **Files**: `Sources/Typano/Recording/ScreenRecorder.swift`, `Sources/Typano/UI/PreferencesView.swift`, `Sources/Typano/AppDelegate.swift`, `CLAUDE.md`

- **Verify**: release build clean, and all four headless checks still pass (`--check-sound`, `--check-restart`, `--check-recording`, `--check-remap`). Neither fix can be verified from Linux: ScreenCaptureKit needs a GUI session and a TCC grant, and a window that fits the screen is a claim about a screen. The Mac has to settle both — start a video take, stop it with ⌘⌥E, and open the file.

## 2026-08-19 — Surviving a device change, becoming an app, owning the remaps, and recording

- **What**: Four things. (1) The engine now recovers from an output-device change. (2) `Scripts/install.sh` puts a real, icon-bearing `Typano.app` in `/Applications`. (3) The `hidutil` remaps moved into Preferences and read their live state. (4) Recording, audio-only and video-with-audio.

- **Why the audio died**: `AVAudioEngine` stops **and uninitialises itself** when its I/O unit sees the output hardware change, and Apple's contract is that it does not restart itself. Nothing observed that, so after the first speakers↔Bluetooth switch `engine.isRunning` was false forever and every `startNote` went to an AU that was never rendered. `requestSmallBuffer()` had the same shape of bug for a different reason: its body re-reads the default device correctly, it was simply only ever called once.

- **Why two triggers, not one**: `.AVAudioEngineConfigurationChange` fires on format changes and is the only way to hear about a device changing its own rate in Audio MIDI Setup, but it is not dependable for a swap between two devices that agree on format. A CoreAudio listener on `kAudioHardwarePropertyDefaultOutputDevice` fires on every swap regardless of format but knows nothing about rates. They are deduplicated by a 0.25 s trailing debounce rather than by identity, because one device change legitimately emits several of both while the HAL settles and pairing them up is not winnable.

- **Paid lesson — `prepare()` raises, it does not throw**: calling `engine.prepare()` on a graph whose nodes are not connected raises `required condition is false: inputNode != nullptr || outputNode != nullptr` as an **Objective-C exception**, which Swift cannot catch. So it is a crash, not an error path, and the rebuild's ordering — reconnect, *then* prepare — is load-bearing rather than stylistic. Same hazard for `engine.connect` with an invalid format, which is why `processingFormat()` returns nil and bails when there is no usable device. Found by a probe that called `prepare()` on a bare engine.

- **Paid lesson — OpenStep plists have no number type**: `hidutil property --get` emits an OpenStep property list, which `PropertyListSerialization` parses happily. But every scalar comes back as `String`, so reading `HIDKeyboardModifierMappingSrc as? NSNumber` yields nil and the app reports "nothing is remapped" while both remaps are active — silently, with a correct-looking parse and the right entry count. That is exactly the failure the feature exists to prevent, and only writing the parser against the live output caught it. An empty table also prints `(null)`, whose non-dictionary member fails a whole-array `[[String: Any]]` cast rather than yielding zero entries.

- **Why read the table instead of remembering**: the old flags could only ever flip one way. `capsLockRemapped` started true and went false on a raw Caps Lock; `rightCommandRemapped` started false and went true on an F16. Neither could return, and neither knew anything before the first keypress — so opening the app onto an already-remapped keyboard displayed the wrong state, which is the case that prompted this. `hidutil` also covers only devices attached when it ran, so "the mapping is set" and "this keyboard obeys it" are genuinely different facts and the UI now says which.

- **Why a tap rather than system audio**: recording the instrument off its own main mixer means the file cannot contain another app, a system alert, or the microphone — so the sound of the keys being struck is absent by construction rather than by filtering. It needs no permission at all, and taking the signal before the hardware means it is unaffected by which output device is selected, including the one the user just switched to. The cost is that it cannot capture a backing track playing elsewhere; that was the explicit choice.

- **Also fixed**: `Performer.allNotesOff()` never bumped `chordGeneration`, so a strum callback already in flight passed its guard and fired `startNote` *after* CC123, with `chordNotes` already cleared — a note nothing could ever stop. Latent before, because it needed a panic within ~40 ms of a chord; the route-change fix calls `panic()` on every device switch, which is exactly when a chord is mid-strum. And `refreshPedal()` only sends CC64 on a transition, so a route change with the pedal latched left it reading down and behaving up permanently.

- **Rejected**: bumping swift-tools-version to 6.0 to get `.macOS(.v15)` — it would also flip the target into Swift 6 language mode and strict concurrency checking, a far larger change than raising a deployment target. `.macOS("15.0")` does the same job under tools 5.9. Also rejected: recording video through in-process view snapshots to avoid the TCC prompt; it would miss the title bar and needs a hand-rolled frame loop, and `SCRecordingOutput` is twenty lines.

- **Tradeoff**: ad-hoc signing puts the binary's cdhash in the designated requirement, so **every rebuild invalidates the Screen Recording grant** while System Settings still shows the toggle as on — a silent denial, the worst failure mode. `bundle.sh` now prefers a self-signed `Typano Dev` identity if the keychain has one; creating it is a one-time GUI step, so it is offered rather than required. Audio recording is unaffected, which is why it ships independent of any of this.

- **Files**: `Sources/Typano/Audio/{AudioEngine,Performer,SoundCheck}.swift`, `Sources/Typano/Recording/{AudioRecorder,ScreenRecorder,RecordingController}.swift`, `Sources/Typano/Input/{KeyRemap,KeyboardMonitor}.swift`, `Sources/Typano/Model/{Instrument,Settings}.swift`, `Sources/Typano/UI/{ContentView,PreferencesView}.swift`, `Sources/Typano/{AppDelegate,main}.swift`, `Scripts/{install,bundle,make-icon}.*`, `Resources/AppIcon.icns`, `Package.swift`, `README.md`, `CLAUDE.md`

- **Verify**: four headless checks, all starting the real engine, all asserting rather than printing. `--check-restart`: three triggers collapse to one rebuild, engine runs again, bank and both tuned gains survive, `panic()` fires twice — and it prints default-vs-bound device IDs, which confirmed the engine re-binds to the new default rather than assuming it (`default=71 bound=71`). `--check-remap`: read an externally-set table correctly, and `--write` confirmed foreign entries survive both a write and a clear, restoring the table to as-found. `--check-recording`: AAC and WAV both encode, finalise and reopen, asserting on a non-zero peak because silence would still produce a valid file — and it triggers a graph rebuild mid-take, which proved a recording survives an output-device change (2.00 s → 3.90 s, still capturing). The icon was rendered, pulled back to Linux and looked at, at 16–256 px as well as 1024; the small sizes caught a motif too small to read below 64 px and a corner glow that turned to mud.
- **Still only the Mac can settle**: that the swap is audible mid-phrase; that the Dock launch finds the Salamander bank; that toggling the remaps changes real key behaviour; and whether the `.mov`'s audio track is scoped to Typano alone or picks up other apps — the API shape says scoped, but that is a claim, not a measurement.

## 2026-08-18 — Window chrome, a content-sized preferences window, and right ⌘ taken away from the menu

- **What**: Pointer swallowing is now scoped to the instrument window's **content view** rather than the window, so the close and minimise buttons work again and the cursor reappears over the title bar. The preferences window is built from an `NSHostingController` and sized to its fitting size. Right ⌘ is held back from the menu while it is the only ⌘ down, and `Scripts/remap.sh` can additionally remap it to F16 at the HID level.
- **Why**: All three came out of playing the previous entry's build. Swallowing every pointer event whose `event.window` was the instrument window also swallowed clicks on the traffic lights — a window with no keyboard shortcut for close (right ⌘ was eating ⌘W's neighbours) and no clickable chrome is a trap. A hard-coded 440×500 preferences rect left every control stranded in the top half. And right ⌘ was still a system modifier, so the rollover measurement this build exists to enable — hold right ⌘, mash `Y H N U J M` — hid the app on `H` instead of reporting anything.
- **Tradeoff**: isolating right ⌘ means **no shortcut answers to it any more** — ⌘L, ⌘R, ⌘1–4 are left-⌘ only. That is the point of the key becoming an instrument control, and left ⌘ is untouched, but it reverses this morning's "right ⌘ stays usable as a menu modifier".
- **Why two mechanisms**: a local `NSEvent` monitor runs before menu key-equivalent dispatch but not before WindowServer, so it cannot stop ⌘-Tab or ⌘-Space. Only the HID remap can, and it costs right ⌘ globally until `off` or a reboot — so it stays opt-in rather than becoming the only path. `hidutil` replaces the whole `UserKeyMapping` table per call, which is why both remaps had to merge into one script; `capslock-remap.sh` is now a shim.
- **Files**: `Sources/Typano/Input/{KeyboardMonitor,KeyCodes}.swift`, `Sources/Typano/Model/{Instrument,Layouts}.swift`, `Sources/Typano/UI/PreferencesView.swift`, `Sources/Typano/AppDelegate.swift`, `Scripts/{remap,capslock-remap}.sh`, `README.md`, `CLAUDE.md`
- **Verify**: release build and `--check-sound` clean on the Mac; `remap.sh` exercised against a stubbed `hidutil` for every argument form, and its payload matches the shape the working caps-lock script emitted. Whether the local monitor actually beats the menu to ⌘H is the one claim only the Mac can settle.
- **Supersedes**: the "right ⌘ stays usable as a menu modifier" clause of 2026-08-18 — Trackpad as the primary sustain pedal.

## 2026-08-18 — Trackpad as the primary sustain pedal; per-zone levels; modifiers made visible

- **What**: Sustain becomes an OR of three sources — a thumb resting on half the trackpad (`Input/TrackpadSurface.swift`, `NSTouch` on an indirect device), a right-⌘ latch, and the original space bar. Melody and chord zones get independent level sliders in a new non-modal preferences window, backed by `UserDefaults`. A peak limiter closes the chain. Every modifier key is now reported into `held`, so the rollover tester can measure them.
- **Why**: Playing revealed that `space` + `H` + `J` does not register — the space bar ghosts against the melody keys, so sustain and the left hand cannot be used together. That is the keyboard matrix and no software change fixes it; only a different key does. The trackpad is not a workaround but the better instrument: it is where the thumbs already rest, resting is cheaper than holding for a whole phrase, and it is the kind of control the brief means by "only a computer can do this". Right ⌘ has to **latch** rather than hold, because `KeyboardMonitor` routes anything carrying `.command` to the menu — a held ⌘ would silence the instrument and make `Q` quit it. Levels: chords fire four notes at once and sum roughly 12 dB above a single melody note, so the left zone read as quiet; melody velocity 78 also sat in a mezzo-piano layer of the 16-layer Salamander bank, which made it dull as well as quiet. Velocity and gain were both raised, because velocity is timbre on a sampled piano and gain alone would have made it loud and still dull.
- **Also fixed**: two latent bugs that broke sustain specifically. `KeyboardMonitor` returned any `.command`-carrying event unhandled, so a key-up under ⌘ never reached `onKeyUp` — the note rang forever and the key stayed dead because `held` never lost the code. And nothing observed focus loss, so ⌘-Tabbing away with the pedal down latched CC64 at 127 permanently.
- **Rejected**: right ⌥ as the pedal — it is bound to dictation on this machine and is an awkward reach for the thumb. Percussion on the trackpad's second half — deferred; for now that half is deliberately inert, which is what makes it a place to rest the other thumb.
- **Files**: `Sources/Typano/Input/{TrackpadSurface,KeyboardMonitor,KeyCodes}.swift`, `Sources/Typano/Model/{Settings,Instrument,Layout,Layouts}.swift`, `Sources/Typano/Audio/{AudioEngine,Performer,SoundCheck}.swift`, `Sources/Typano/UI/{PreferencesView,TrackpadMeterView,ContentView,KeyCapView}.swift`, `Sources/Typano/AppDelegate.swift`
- **Verify**: `--check-sound` now starts the real `AudioEngine` as well as the throwaway one, which is the only headless way to confirm the limiter instantiates and the graph connects; it reports `graph: Salamander Grand Piano` and the level→dB curve (`0.50 → melody +3.0 dB, chords −1.0 dB`). Everything else — whether a motionless thumb keeps being reported, whether right ⌘ ghosts, whether the balance is right — needs a human at the keyboard.

## 2026-08-16 — Salamander SF2 as the primary voice; Logic's pianos are unreachable

- **What**: Primary piano is the downloaded Salamander Grand Piano SF2, fetched by `Scripts/fetch-sounds.sh`, with the system GM bank as fallback.
- **Why**: Logic Pro is installed with `Concert Grand Piano.exs` and 3.2 GB of samples, and `AVAudioUnitSampler` does support EXS — an older GarageBand instrument loads fine. But Logic's Studio Piano instruments hard-code sample paths under `/Library/Application Support/com.apple.musicapps.content/`, which does not exist; the samples actually sit under `Logic/EXS Factory Samples/`. Co-locating samples beside the instrument still fails (`-43`); the Steinway fails as unsupported format (`-10868`). Making it work would need a write under `/Library`. Salamander is CC-BY, needs no `sudo`, and does not tie the app to Logic being installed.
- **Files**: `Sources/Typano/Audio/SoundSource.swift`, `Scripts/fetch-sounds.sh`, `.gitignore`, `.rsync-exclude`
- **Verify**: `Typano --check-sound` reports `OK [Grand Piano] Salamander Grand Piano`; bundled app sits at ~310 MB RSS (vs ~105 MB on the GM fallback), loads in <1 s.

## 2026-08-16 — Caps Lock remapped to F13 rather than read directly

- **What**: `Scripts/capslock-remap.sh` maps Caps Lock to F13 via `hidutil`; the layout binds the note to F13, and the app detects raw keycode 57 to show a hint when the remap is not active.
- **Why**: Caps Lock emits `flagsChanged` as a toggle with no key-up, so note duration is undefined, and it carries a hardware debounce. This also drove the decision to put the leading tone rather than the tonic on the left-edge modifier column — losing B3 to an unremapped Caps Lock costs far less than losing middle C.
- **Files**: `Scripts/capslock-remap.sh`, `Sources/Typano/Input/KeyboardMonitor.swift`, `Sources/Typano/Model/Layouts.swift`
- **Verify**: pending — needs a human at the keyboard.

## 2026-08-16 — Build with SwiftPM and a hand-rolled bundle, not xcodebuild

- **What**: `Package.swift` + `Scripts/bundle.sh` assembling `Typano.app` by hand; scripts export `DEVELOPER_DIR` per invocation.
- **Why**: Every edit reaches the Mac over `rsync` and the IDE is never opened, so a hand-maintained `.xcodeproj` would be a liability with no upside. `DEVELOPER_DIR` selects Xcode's toolchain without `sudo xcode-select`, leaving the Mac's global state untouched — Xcode was installed mid-session but `xcode-select` still points at CommandLineTools, and that is fine.
- **Files**: `Package.swift`, `Scripts/{build,bundle,run,sync}.sh`
- **Verify**: `swift build -c release` clean; `codesign -dv` reports an ad-hoc-signed arm64 app bundle that launches and survives.

## 2026-08-16 — Instrument layout: melody left, chord grid right

- **What**: Left of the Y/H/N column plays three aligned diatonic octaves; right of it is an 18-key chord grid with columns on the circle of fifths and rows changing quality.
- **Why**: The keyboard matrix limits simultaneous right-hand keys, so one-key-one-chord sidesteps the constraint instead of fighting it — which is also the brief's position that Typano is not a piano simulator. The grid is ordered by a rule (fifths × quality) rather than by usage frequency, because a rule can be derived from memory while a frequency ranking has to be memorised; the cost is vi landing on `'` rather than a home key. A usage-ordered alternative ships behind `⌘L` so the two can be compared by playing rather than argued about.
- **Files**: `Sources/Typano/Model/Layouts.swift`, `Sources/Typano/Model/VoiceLeading.swift`
- **Verify**: pending — the `⌘R` rollover tester exists specifically to measure the matrix assumption instead of trusting it.

# DEVCHANGELOG

The append-only development record for Typano: why things changed, what was tried, and what it cost. Newest entry first; entries are never edited or removed — a reversed decision gets a new entry naming what it supersedes. Standing rules and invariants live in `CLAUDE.md`, not here; user-facing release notes would live in `CHANGELOG.md`.

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

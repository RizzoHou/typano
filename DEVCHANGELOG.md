# DEVCHANGELOG

The append-only development record for Typano: why things changed, what was tried, and what it cost. Newest entry first; entries are never edited or removed — a reversed decision gets a new entry naming what it supersedes. Standing rules and invariants live in `CLAUDE.md`, not here; user-facing release notes would live in `CHANGELOG.md`.

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

# Typano

Type + Piano — a macOS app that turns the MacBook keyboard into a playable instrument.

Typano is not a piano simulator. It does not chase touch sensitivity or realism for its own sake; it leans on what only a computer can do — programmable mapping, stereo placement, screen light effects. See `docs/Typano_Creative_Brief_EN.md` for the full intent.

## The instrument

**Left of the Y/H/N column plays melody.** Three rows of seven keys, one diatonic octave each. Columns are aligned, so changing octave is a vertical hand shift with identical fingering — `Z`, `A` and `Q` are all `do`.

|  | leading tone | scale |
|---|---|---|
| top | `Tab` B4 | `Q W E R T Y` = C5 D5 E5 F5 G5 A5 |
| home | `caps` B3 | `A S D F G H` = C4 D4 E4 F4 G4 A4 |
| bottom | `⇧` B2 | `Z X C V B N` = C3 D3 E3 F3 G3 A3 |

`A` is middle C. The wide, awkward keys at the left edge carry the leading tone rather than the tonic, so the note you play most often always falls on a normal letter key.

**Right of that column plays chords**, one key per chord. This is deliberate: the keyboard matrix limits how many right-hand keys register at once, and a chord per key sidesteps that entirely.

Columns walk the circle of fifths; rows change quality.

| row | rule | keys |
|---|---|---|
| top | **+7th** | `U` Fmaj7 · `I` Cmaj7 · `O` G7 · `P` Dm7 · `[` Am7 · `]` Em7 · `\` Bm7♭5 |
| home | **diatonic triad** | `J` F(IV) · `K` C(I) · `L` G(V) · `;` Dm(ii) · `'` Am(vi) · `↩` Em(iii) |
| bottom | **major↔minor flip** | `M` Fm(iv) · `,` Cm(i) · `.` Gm · `/` D(V/V) · `⇧R` A(V/ii) |

Three rules cover the whole grid: **右移一格 = 上五度 · 上排 = 加七 · 下排 = 大小调对调**. The three primary triads IV–I–V land on `J K L`, and the rarest chords fall on the keys hardest to reach.

`⌘L` switches to an alternative grid ordered by how often each chord is used, where I–V–vi–IV is a straight left-to-right run across `J K L ;`. It is easier under the fingers but is a list to memorise rather than a rule — the two are there to be compared by playing them.

### Controls

| key | function |
|---|---|
| trackpad | sustain while a thumb rests on the sustain half |
| right `⌘` | sustain latch — tap on, tap off |
| `space` | sustain pedal (hold) |
| `↑` / `↓` | hold to raise / lower the next note or chord root a semitone |
| `←` / `→` | transpose the whole instrument down / up a semitone |
| `⌘L` | switch chord layout |
| `⌘R` | rollover tester |
| `⌘1`–`⌘4` | timbre |
| `⌘0` | reset transpose |
| `⌘E` | start / stop recording audio |
| `⌥⌘E` | start / stop recording video |
| `⌘,` | preferences |

### Sustain

Three sources, ORed together, each switchable off in preferences.

The space bar is the obvious pedal and the worst one: it ghosts against the melody keys, so `space` + `H` + `J` does not register and holding sustain while playing `G` and `H` together is impossible. That is the keyboard matrix, not software — the only fix is a different key.

**The trackpad is the primary pedal.** One vertical divider splits it in two; resting a thumb on the sustain half holds the pedal, lifting it releases. It sits where the thumbs already are, and resting is less tiring than holding a key down for a whole phrase. The other half is deliberately inert — somewhere to park the second thumb. The divider position and which side sustains are both adjustable. Trackpad zones are live only while the instrument window is in front; in the preferences window the trackpad is an ordinary pointer, which is what makes its sliders draggable while the instrument keeps sounding.

**Right `⌘` latches** rather than holds, and it has to: a held `⌘` routes every following keystroke to the menu bar instead of the instrument, so `Q` would quit the app mid-phrase. The toggle fires on release and only if nothing else was pressed in between.

To make holding it harmless anyway, the app keeps right `⌘` away from the menu while it is the only `⌘` down — right `⌘` + `H` plays a note instead of hiding the app. Left `⌘` is untouched, so every shortcut in the table still works; the cost is that shortcuts no longer answer to right `⌘`. `⌘`-Tab and `⌘`-Space are handled by WindowServer before any app sees them and survive this; `Scripts/remap.sh on` removes those too, by remapping right `⌘` to F16 at the HID level so it is not a modifier anywhere. The app binds F16 to the same latch, so the key behaves identically either way.

### Preferences (`⌘,`)

A second window that stays open beside the instrument, because balance is something you find by ear while playing. Everything applies immediately and persists.

- **Melody / chord levels.** Two sliders. 50% is the tuned baseline, not unity; the curve is asymmetric (+6 dB at the top, −40 dB and then silence at the bottom) because the baseline already sits near the headroom ceiling.
- **Sustain sources.** Turn any of the three off.
- **Trackpad.** Divider position, which half sustains, and a live view of every contact on the pad.
- **Key remaps.** Two switches that apply the `hidutil` remaps below, reading the live state rather than remembering what the app last asked for — so opening Typano onto an already-remapped keyboard shows the truth, and a reboot clearing the remaps shows up too.
- **Recording.** Audio format, video frame rate, whether the pointer and the REC badge appear in video.

### Recording (`⌘E` audio, `⌥⌘E` video)

Both ask where to save first, then stream straight into that file; `⌘E` / `⌥⌘E` again stops.

- **Audio** is a tap on the instrument's own audio graph, so the file contains Typano and nothing else — no other app, no system alert sounds, and no microphone, so the sound of the keys being struck is not in it. It needs no permission, and because the signal is taken before the hardware, it is unaffected by which output device is selected. AAC by default, 24-bit WAV optional.
- **Video** captures this window with ScreenCaptureKit, picture and sound together. It needs Screen Recording permission, which macOS only grants to an app that is then relaunched. The REC badge is hidden from video takes by default, since it sits inside the captured window.

Recording survives switching output device mid-take.

## Build and run

Requires Xcode's toolchain. The scripts select it per-invocation via `DEVELOPER_DIR`, so no `sudo xcode-select` and no change to system state.

```bash
Scripts/fetch-sounds.sh          # once — downloads the piano sound bank (~310 MB)
Scripts/install.sh               # build, bundle, install to /Applications
Scripts/run.sh                   # or: build, bundle, launch in place
```

`Scripts/install.sh` puts `Typano.app` in `/Applications` (falling back to `~/Applications`, never `sudo`) so it launches from the Dock, and links the sound bank into `~/Library/Application Support/Typano/Sounds` — an installed bundle cannot see the repo's `Sounds/` directory, and without the link it silently falls back to the system GM bank.

Key remaps are applied from Preferences now, not from a shell. `Scripts/remap.sh` still works and is the way out if the app will not start.

`Scripts/fetch-sounds.sh` honours `TYPANO_PROXY` / `https_proxy`, and falls back to a local proxy on port 7890 if one is listening.

Diagnostics:

```bash
Typano --check-sound                 # sound sources, and the real graph
Typano --check-restart               # the output-device recovery path
Typano --check-remap [--write]       # live hidutil state; --write round-trips and restores
Typano --check-recording <path>      # records an arpeggio and asserts on captured signal
Typano --try-instrument <path>       # probe one instrument file
```

All of these run headless over ssh, and all of them start the *real* engine rather than a stand-in. `--check-recording` asserts on a non-zero peak, not on the file existing, and deliberately triggers a graph rebuild mid-take to prove a recording survives an output-device change.

### Key remaps

Both remaps live in Preferences (`⌘,`) as switches. They are applied with `hidutil` — no `sudo`, reversible, and reset by a reboot. The app reads the live table rather than remembering what it last set, so the switches are correct even when the remaps were applied by something else, and it preserves any mapping it does not own — which `Scripts/remap.sh off` does not, since `hidutil` replaces the whole table on every call.

Re-applying at launch is opt-in and off by default: starting an app should not silently change system-wide keyboard behaviour.

`Scripts/remap.sh on` does the same thing from a shell, and remains the way out if the app will not start.

- **Caps Lock → F13.** Caps Lock cannot be a note key as shipped: it is a toggle that emits no key-up event, so note duration is undefined, and it has a hardware debounce. Until you remap it, B3 is simply unavailable and the app says so.
- **Right `⌘` → F16.** Optional. Strips right `⌘` of its modifier meaning everywhere so no shortcut at any level answers to it. Left `⌘` is untouched. The cost is that right `⌘` stops being `⌘` in every other app until you run `off` or reboot.

## Sound

The primary voice is the **Salamander Grand Piano** (Yamaha C5, 16 velocity layers, release samples) by Alexander Holm, CC-BY 3.0, distributed as SF2 by [FreePats](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html). It is downloaded, not committed; attribution is required if Typano is ever distributed with it. If it is missing, the app falls back to the system General MIDI bank and stays playable.

Chords fire four notes at once and sum roughly 12 dB above a single melody note at the same velocity, so the melody zone reads as quiet even when it is nominally the same level. The melody is compensated with both velocity and gain: velocity is also timbre on a 16-layer sampled piano, so gain alone would make the left hand loud and still dull. A peak limiter sits at the end of the chain as insurance against the levels the sliders allow.

Because the keyboard reports no velocity, fidelity comes from arrangement rather than sampling:

- **Sustain pedal** (CC64) — without it every note is clipped at key-up.
- **Velocity humanisation** — a few units of jitter, since a fixed velocity makes every note identical.
- **Voice leading** — chords pick the inversion that moves least from the previous chord, plus a bass root below. Always-root-position triads leap around the register and are the most obviously mechanical thing a chord instrument can do.
- **Micro-strum** — chord tones staggered 6–12 ms; a perfectly simultaneous attack is the clearest tell that no hand was involved.

### Logic Pro's sampled pianos do not work

Worth recording, because it looks like it should. Logic's `Concert Grand Piano.exs` and `Steinway Grand Piano 2.exs` are present on a machine with Logic installed, and `AVAudioUnitSampler` does support the EXS format — an older GarageBand instrument loads fine. But Logic's Studio Piano instruments reference their samples by an absolute path under `/Library/Application Support/com.apple.musicapps.content/`, which does not exist; the samples actually live under `Logic/EXS Factory Samples/`. Logic resolves this internally, AUSampler does not, and co-locating the samples beside the instrument does not help (`-43`, file not found). The Steinway fails differently (`-10868`, format not supported). Creating the referenced path would require writing under `/Library`.

## Layout

```
Sources/Typano/
  Input/    KeyCodes, KeyboardMonitor, TrackpadSurface   — local NSEvent monitor and
                                                          NSTouch, neither needing
                                                          Accessibility permission
  Model/    Layouts, Chord, VoiceLeading, Instrument, Settings
  Audio/    AudioEngine, SoundSource, Performer, SoundCheck
  UI/       ContentView, KeyCapView, PhysicalKeyboard, RolloverTesterView,
            TrackpadMeterView, PreferencesView
```

Development happens on a Linux box and syncs to a Mac with `Scripts/sync.sh`; the Mac is the only place the app can actually be built, heard, or played.

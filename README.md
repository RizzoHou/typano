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
| `⌘,` | preferences |

### Sustain

Three sources, ORed together, each switchable off in preferences.

The space bar is the obvious pedal and the worst one: it ghosts against the melody keys, so `space` + `H` + `J` does not register and holding sustain while playing `G` and `H` together is impossible. That is the keyboard matrix, not software — the only fix is a different key.

**The trackpad is the primary pedal.** One vertical divider splits it in two; resting a thumb on the sustain half holds the pedal, lifting it releases. It sits where the thumbs already are, and resting is less tiring than holding a key down for a whole phrase. The other half is deliberately inert — somewhere to park the second thumb. The divider position and which side sustains are both adjustable. Trackpad zones are live only while the instrument window is in front; in the preferences window the trackpad is an ordinary pointer, which is what makes its sliders draggable while the instrument keeps sounding.

**Right `⌘` latches** rather than holds, and it has to: a held `⌘` routes every following keystroke to the menu bar instead of the instrument, so `Q` would quit the app mid-phrase. The toggle fires on release and only if nothing else was pressed in between, so right `⌘` still works as a normal menu modifier.

### Preferences (`⌘,`)

A second window that stays open beside the instrument, because balance is something you find by ear while playing. Everything applies immediately and persists.

- **Melody / chord levels.** Two sliders. 50% is the tuned baseline, not unity; the curve is asymmetric (+6 dB at the top, −40 dB and then silence at the bottom) because the baseline already sits near the headroom ceiling.
- **Sustain sources.** Turn any of the three off.
- **Trackpad.** Divider position, which half sustains, and a live view of every contact on the pad.

## Build and run

Requires Xcode's toolchain. The scripts select it per-invocation via `DEVELOPER_DIR`, so no `sudo xcode-select` and no change to system state.

```bash
Scripts/fetch-sounds.sh          # once — downloads the piano sound bank (~310 MB)
Scripts/capslock-remap.sh on     # once per boot — see below
Scripts/run.sh                   # build, bundle, launch
```

`Scripts/fetch-sounds.sh` honours `TYPANO_PROXY` / `https_proxy`, and falls back to a local proxy on port 7890 if one is listening.

Diagnostics:

```bash
.build/arm64-apple-macosx/release/Typano --check-sound              # sound sources, and the real graph
.build/arm64-apple-macosx/release/Typano --try-instrument <path>    # probe one instrument file
```

### Caps Lock

Caps Lock cannot be a note key as shipped: it is a toggle that emits no key-up event, so note duration is undefined, and it has a hardware debounce. `Scripts/capslock-remap.sh on` remaps it to F13 via `hidutil` — no `sudo`, reversible with `off`, and reset by a reboot. Until you run it, B3 is simply unavailable and the app says so.

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

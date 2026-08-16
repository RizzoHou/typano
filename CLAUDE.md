# CLAUDE.md

Typano is a **macOS** app. This repo lives on a Linux box, which cannot build, run, or hear it. See `README.md` for the instrument spec and `DEVCHANGELOG.md` for why past decisions were made.

## Dev loop

Edit locally, sync, build over ssh. Never edit files on the Mac — local is the source of truth.

```bash
bash Scripts/sync.sh                                    # rsync -> entry-mac:~/projects/typano
ssh entry-mac 'cd ~/projects/typano && bash Scripts/build.sh release'
```

Sync before **every** remote command batch; the usual failure is debugging a stale remote tree.

## What can and cannot be verified here

Compilation, and `Typano --check-sound` / `--try-instrument <path>` (headless, runnable over ssh).

**Not verifiable from Linux:** latency, timbre, key rollover, light effects, anything about how it feels. The user is the only sensor for those — ask, don't assert.

## Rules

- **Build with SwiftPM, not `xcodebuild`.** There is deliberately no `.xcodeproj`. Scripts export `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; never run `sudo xcode-select` — the Mac's global state stays untouched.
- **`Sounds/` must stay in `.rsync-exclude`.** It holds a 1.2 GB sound bank that exists only on the Mac. `sync.sh` uses `--delete`; dropping the exclusion destroys it.
- **Key layouts are compiled-in Swift values** (`Model/Layouts.swift`), not resource files — SwiftPM resource bundles complicate the hand-rolled `.app`.
- **`notes.md`, `cof.md`, `cot.md` are user-edit-only.** Read them; never write them. They are gitignored.

## Input gotchas

These are load-bearing and easy to regress:

- Filter `event.isARepeat` on keyDown, or held notes machine-gun via macOS key repeat.
- `⌘` is never a playing modifier — the monitor passes ⌘ events through so menu shortcuts work.
- `.shift` cannot distinguish left from right Shift; read the device-dependent bits (`KC.DeviceFlag`).
- Caps Lock is a toggle with no key-up. It is bound as **F13** and requires `Scripts/capslock-remap.sh on`.
- The local `NSEvent` monitor needs no Accessibility permission. Keep it that way — do not reach for `CGEventTap`.

## Sound

Primary voice is the Salamander SF2 (`Scripts/fetch-sounds.sh`), falling back to the system GM bank. Logic Pro's sampled pianos are **not** usable — see `DEVCHANGELOG.md` 2026-08-16 before trying again.

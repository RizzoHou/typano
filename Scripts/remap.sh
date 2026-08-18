#!/usr/bin/env bash
# HID-level key remaps Typano wants. No sudo; per-boot and per-device, so
# re-run after a reboot. `hidutil` replaces the whole mapping table on every
# call, which is why both remaps live in one script — setting one from a
# separate script would silently drop the other.
#
#   caps      Caps Lock -> F13. Caps Lock is a toggle with no key-up, so it
#             cannot time a note; as F13 it is an ordinary key (B3).
#   rightcmd  Right ⌘ -> F16. Strips right ⌘ of its modifier meaning
#             everywhere, so holding it can no longer fire ⌘-Tab, ⌘-Space or
#             any menu shortcut. Left ⌘ is untouched, and the app binds F16 to
#             the same sustain latch, so the key works either way.
#
# The app isolates right ⌘ from its own menu on its own; this remap is only
# needed for the shortcuts WindowServer handles before any app sees them.
#
# Written for bash 3.2, which is what a stock macOS ships.
set -euo pipefail

CAPS=0x700000039
F13=0x700000068
RIGHT_CMD=0x7000000E7
F16=0x70000006B

usage() {
    echo "usage: $(basename "$0") on [caps|rightcmd ...] | off | status" >&2
    echo "       on with no feature named enables both" >&2
    exit 1
}

case "${1:-}" in
    on)
        shift
        features="$*"
        if [ -z "$features" ]; then features="caps rightcmd"; fi

        entries=""
        report=""
        for feature in $features; do
            case "$feature" in
                caps)
                    src=$CAPS; dst=$F13
                    line="Caps Lock -> F13 (Typano note key B3)"
                    ;;
                rightcmd)
                    src=$RIGHT_CMD; dst=$F16
                    line="Right command -> F16 (Typano sustain latch; no longer a modifier)"
                    ;;
                *)
                    echo "unknown feature: $feature (want caps or rightcmd)" >&2
                    exit 1
                    ;;
            esac
            if [ -n "$entries" ]; then entries="$entries,"; fi
            entries="$entries{\"HIDKeyboardModifierMappingSrc\":$src,\"HIDKeyboardModifierMappingDst\":$dst}"
            report="$report$line
"
        done

        hidutil property --set "{\"UserKeyMapping\":[$entries]}" >/dev/null
        printf '%s' "$report"
        ;;
    off)
        hidutil property --set '{"UserKeyMapping":[]}' >/dev/null
        echo "All Typano remaps cleared"
        ;;
    status)
        hidutil property --get UserKeyMapping
        ;;
    *)
        usage
        ;;
esac

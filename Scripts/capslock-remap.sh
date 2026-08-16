#!/usr/bin/env bash
# Caps Lock is a toggle with no key-up event, so it cannot act as a note key.
# Remap it to F13, which behaves like a normal key. No sudo required.
# The mapping is per-boot and per-device; re-run after a reboot.
set -euo pipefail

CAPS=0x700000039
F13=0x700000068

case "${1:-}" in
    on)
        hidutil property --set "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":$CAPS,\"HIDKeyboardModifierMappingDst\":$F13}]}" >/dev/null
        echo "Caps Lock -> F13 (Typano note key B3)"
        ;;
    off)
        hidutil property --set '{"UserKeyMapping":[]}' >/dev/null
        echo "Caps Lock restored"
        ;;
    status)
        hidutil property --get UserKeyMapping
        ;;
    *)
        echo "usage: $(basename "$0") on|off|status" >&2
        exit 1
        ;;
esac

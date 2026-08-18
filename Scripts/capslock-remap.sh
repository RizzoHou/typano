#!/usr/bin/env bash
# Kept for muscle memory; the remaps live in Scripts/remap.sh now, because
# hidutil replaces the whole mapping table and two scripts would fight over it.
set -euo pipefail
case "${1:-}" in
    on) exec "$(dirname "$0")/remap.sh" on caps ;;
    *)  exec "$(dirname "$0")/remap.sh" "$@" ;;
esac

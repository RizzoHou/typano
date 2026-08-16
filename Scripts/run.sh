#!/usr/bin/env bash
# Run on the Mac: build, bundle, launch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"

"$ROOT/Scripts/build.sh"  "$CONFIG"
"$ROOT/Scripts/bundle.sh" "$CONFIG"

pkill -x Typano 2>/dev/null || true
open "$ROOT/.build/Typano.app"

#!/usr/bin/env bash
# Run on the Mac. Uses Xcode's toolchain without touching the global xcode-select.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
swift build -c "$CONFIG"
echo "built: $(swift build -c "$CONFIG" --show-bin-path)/Typano"

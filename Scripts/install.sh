#!/usr/bin/env bash
# Run on the Mac, by a human. Builds, bundles, and installs Typano where the
# Dock and Launchpad can find it.
#
# No sudo anywhere: /Applications is writable by an admin user, and if it is
# not we fall back to ~/Applications rather than escalating.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"

bash "$ROOT/Scripts/build.sh"  "$CONFIG"
bash "$ROOT/Scripts/bundle.sh" "$CONFIG"

DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    echo "note: /Applications not writable, installing to $DEST"
fi

# -x matches the process name only, so this cannot match the shell running it
# the way -f would.
pkill -u "$(id -u)" -x Typano 2>/dev/null || true

rm -rf "$DEST/Typano.app"
cp -R "$ROOT/.build/Typano.app" "$DEST/Typano.app"

# The 1.2 GB sound bank stays in the repo and is reached through the
# Application Support path SoundSource.swift already searches. The bundle's
# other search path is two levels up from itself, which resolves to /Sounds
# once installed and does not exist — so without this link an installed Typano
# silently falls back to the system GM bank.
SUPPORT="$HOME/Library/Application Support/Typano"
mkdir -p "$SUPPORT"
if [ -L "$SUPPORT/Sounds" ] || [ ! -e "$SUPPORT/Sounds" ]; then
    ln -sfn "$ROOT/Sounds" "$SUPPORT/Sounds"
    echo "linked: $SUPPORT/Sounds -> $ROOT/Sounds"
else
    echo "note: $SUPPORT/Sounds is a real directory — left alone"
fi

# Make Launch Services notice the bundle now rather than whenever it next scans.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$DEST/Typano.app" || true

echo "installed: $DEST/Typano.app"
echo "Drag it to the Dock once; later installs replace it in place."

#!/usr/bin/env bash
# Run on the Mac. Downloads the sampled piano used as Typano's primary voice.
#
# Salamander Grand Piano — Yamaha C5, 16 velocity layers, release samples.
# Alexander Holm, CC-BY 3.0, redistributed by FreePats. Attribution is required
# if Typano is ever distributed with it; see Sounds/README-license.txt.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Sounds"
URL="https://freepats.zenvoid.org/Piano/SalamanderGrandPiano/SalamanderGrandPiano-SF2-V3+20200602.tar.xz"
ARCHIVE="$DEST/salamander.tar.xz"

mkdir -p "$DEST"

# FreePats is slow to reach directly from here. Use an explicit proxy if one is
# configured, otherwise fall back to a local one on the conventional port.
PROXY="${TYPANO_PROXY:-${https_proxy:-}}"
if [ -z "$PROXY" ] && nc -z 127.0.0.1 7890 2>/dev/null; then
    PROXY="http://127.0.0.1:7890"
fi
PROXY_ARGS=()
if [ -n "$PROXY" ]; then
    PROXY_ARGS=(--proxy "$PROXY")
    echo "using proxy $PROXY"
fi

if find "$DEST" -name "*.sf2" -print -quit | grep -q .; then
    echo "sound bank already present:"
    find "$DEST" -name "*.sf2"
    exit 0
fi

echo "downloading Salamander Grand Piano (~310 MB)…"
curl -L --fail --retry 3 --continue-at - "${PROXY_ARGS[@]}" -o "$ARCHIVE" "$URL"
tar -xf "$ARCHIVE" -C "$DEST"
rm -f "$ARCHIVE"

cat > "$DEST/README-license.txt" <<'EOF'
Salamander Grand Piano V3
Recorded by Alexander Holm, licensed CC-BY 3.0.
SF2 conversion distributed by FreePats: https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html

Attribution is required if this sound bank is redistributed with Typano.
EOF

echo "installed:"
find "$DEST" -name "*.sf2"

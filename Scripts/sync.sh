#!/usr/bin/env bash
# Run on the Linux dev box: push the working tree to entry-mac.
set -euo pipefail

REMOTE="${TYPANO_REMOTE:-entry-mac}"
REMOTE_PATH="${TYPANO_REMOTE_PATH:-projects/typano}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rsync -az --delete -e ssh \
    --exclude-from="$ROOT/.rsync-exclude" \
    "$ROOT/" "$REMOTE:$REMOTE_PATH/"

echo "synced -> $REMOTE:$REMOTE_PATH/"

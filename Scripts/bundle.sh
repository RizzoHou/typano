#!/usr/bin/env bash
# Run on the Mac. Assembles Typano.app around the SwiftPM binary.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/.build/Typano.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Typano" "$APP/Contents/MacOS/Typano"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: Resources/AppIcon.icns missing — run 'swift Scripts/make-icon.swift'" >&2
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Typano</string>
    <key>CFBundleDisplayName</key>       <string>Typano</string>
    <key>CFBundleIdentifier</key>        <string>com.rizzohou.typano</string>
    <key>CFBundleExecutable</key>        <string>Typano</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key>           <string>2</string>
    <key>LSMinimumSystemVersion</key>    <string>15.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.music</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <!-- Lets a headless ssh session drive the window: `osascript -e 'tell
         application "Typano" to close window 1'` is the red button, which is
         otherwise unverifiable from Linux. Cocoa supplies the Standard Suite;
         there is no scripting dictionary of our own. -->
    <key>NSAppleScriptEnabled</key>     <true/>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Screen Recording permission is granted against the signature's designated
# requirement. Ad-hoc signing puts the binary's cdhash in that requirement, and
# the cdhash changes on every build — so the grant is silently invalidated each
# rebuild, which shows up as recording failing while System Settings still
# displays the toggle as on. A self-signed code-signing certificate in the login
# keychain pins the requirement to the certificate instead, so the grant is
# given once. Create one in Keychain Access > Certificate Assistant, named to
# match, then it is picked up automatically here.
IDENTITY="${TYPANO_SIGN_IDENTITY:-Typano Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" --identifier com.rizzohou.typano "$APP"
    echo "signed: $IDENTITY (Screen Recording permission survives rebuilds)"
else
    codesign --force --sign - "$APP" 2>/dev/null
    echo "signed: ad-hoc — Screen Recording permission resets on every rebuild."
    echo "        See the comment in Scripts/bundle.sh to make it stick."
fi

echo "bundled: $APP"

#!/usr/bin/env bash
# Packages dist/HubOS.app into a polished, compressed .dmg with a drag-to-
# Applications layout. Uses only stock macOS tooling (hdiutil + Finder/osascript).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Prism"
VOL_NAME="Prism"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"
STAGING="$DIST/.dmg_staging"
TMP_DMG="$DIST/.hubos_tmp.dmg"
BG="$ROOT/Resources/dmg_background.png"

[ -d "$APP" ] || { echo "✗ $APP not found — run build_app.sh first"; exit 1; }

# Detach any stale HubOS volume left from an interrupted run. Otherwise the new
# image mounts as "HubOS 1", so the layout AppleScript targets the wrong disk and
# the source image stays attached — which makes the final `convert` fail with
# "Resource temporarily unavailable".
cleanup_mounts() {
    local devs
    devs="$(hdiutil info 2>/dev/null | grep -F "/Volumes/$VOL_NAME" | grep -Eo '^/dev/disk[0-9]+' || true)"
    for d in $devs; do hdiutil detach "$d" -force >/dev/null 2>&1 || true; done
    for v in "/Volumes/$VOL_NAME"*; do
        [ -e "$v" ] && hdiutil detach "$v" -force >/dev/null 2>&1 || true
    done
}
cleanup_mounts

echo "▸ Rendering DMG background…"
swift "$ROOT/Scripts/dmg_bg_render.swift" "$BG" >/dev/null

echo "▸ Preparing staging folder…"
rm -rf "$STAGING" "$DMG" "$TMP_DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
if [ -f "$BG" ]; then
    mkdir -p "$STAGING/.background"
    cp "$BG" "$STAGING/.background/background.png"
fi

echo "▸ Creating writable DMG…"
hdiutil create -srcfolder "$STAGING" -volname "$VOL_NAME" -fs HFS+ \
    -format UDRW -ov "$TMP_DMG" >/dev/null

echo "▸ Mounting to arrange layout…"
ATTACH_OUT="$(hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen)"
DEV="$(printf '%s\n' "$ATTACH_OUT" | grep -Eo '^/dev/disk[0-9]+' | head -1)"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUT" | sed -n 's#.*\(/Volumes/.*\)$#\1#p' | tail -1)"
: "${MOUNT_DIR:=/Volumes/$VOL_NAME}"
VOL_ACTUAL="$(basename "$MOUNT_DIR")"
sleep 1

if [ -f "$BG" ]; then
osascript <<EOF || true
tell application "Finder"
    tell disk "$VOL_ACTUAL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {180, 120, 780, 520}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 120
        set text size of theViewOptions to 12
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {150, 185}
        set position of item "Applications" of container window to {450, 185}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
fi

sync
# Detach by device node, with retries — Finder/Spotlight can briefly hold the
# freshly written volume, which is what leaves the image attached.
detached=0
for i in 1 2 3 4 5; do
    if hdiutil detach "$DEV" >/dev/null 2>&1; then detached=1; break; fi
    sleep 1
done
[ "$detached" = 1 ] || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true

echo "▸ Compressing final DMG…"
converted=0
for i in 1 2 3; do
    if hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null 2>&1; then
        converted=1; break
    fi
    echo "  convert busy, retry $i…"; sleep 2
    cleanup_mounts
done
if [ "$converted" != 1 ]; then echo "✗ convert failed"; exit 1; fi

rm -f "$TMP_DMG"
rm -rf "$STAGING"

echo "✓ DMG ready: $DMG"

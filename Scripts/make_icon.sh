#!/usr/bin/env bash
# Generates Resources/AppIcon.icns from the Core Graphics icon renderer.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES="$ROOT/Resources"
BUILD="$ROOT/.build"
ICONSET="$BUILD/AppIcon.iconset"
PNG1024="$BUILD/icon_1024.png"

# Skip regeneration when the icon is already up to date.
if [ -f "$RES/AppIcon.icns" ] && [ "$RES/AppIcon.icns" -nt "$ROOT/Scripts/icon_render.swift" ]; then
    echo "✓ Icon up to date"
    exit 0
fi

mkdir -p "$BUILD"
echo "▸ Rendering base icon…"
swift "$ROOT/Scripts/icon_render.swift" "$PNG1024"

echo "▸ Building iconset…"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
gen() { sips -z "$1" "$1" "$PNG1024" --out "$2" >/dev/null; }
gen 16   "$ICONSET/icon_16x16.png"
gen 32   "$ICONSET/icon_16x16@2x.png"
gen 32   "$ICONSET/icon_32x32.png"
gen 64   "$ICONSET/icon_32x32@2x.png"
gen 128  "$ICONSET/icon_128x128.png"
gen 256  "$ICONSET/icon_128x128@2x.png"
gen 256  "$ICONSET/icon_256x256.png"
gen 512  "$ICONSET/icon_256x256@2x.png"
gen 512  "$ICONSET/icon_512x512.png"
gen 1024 "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
echo "✓ Icon: $RES/AppIcon.icns"

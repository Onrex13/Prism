#!/usr/bin/env bash
# Builds a release binary and assembles a distributable .app bundle. Signs with a
# STABLE self-signed identity when present (see make_cert.sh) so granted TCC
# permissions survive updates; falls back to ad-hoc otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="HubOS"          # SwiftPM product (internal binary name)
APP_NAME="Prism"        # user-facing app name
CERT_NAME="Prism Self-Signed"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "▸ Compiling release binary (arm64)…"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/$TARGET"

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "  (no AppIcon.icns yet — using system default)"
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "▸ Signing with stable identity “$CERT_NAME” (permissions persist across updates)…"
    codesign --force --deep --sign "$CERT_NAME" "$APP"
else
    echo "▸ Ad-hoc code signing (run Scripts/make_cert.sh for update-safe permissions)…"
    codesign --force --deep --sign - "$APP"
fi

echo "✓ Built: $APP"

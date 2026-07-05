#!/usr/bin/env bash
# Builds the release artifacts for a GitHub release: Prism.dmg (for humans) and
# Prism.zip (for the in-app auto-updater). The zip is made with `ditto` so the
# code signature + extended attributes survive — the updater unzips the same way,
# keeping permissions intact.
#
# Usage: Scripts/make_release.sh 0.2.0
#   1. bump CFBundleShortVersionString in Resources/Info.plist to match
#   2. run this, then create a GitHub release tagged v0.2.0 and attach BOTH files
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Prism.app"
ZIP="$DIST/Prism.zip"

VERSION="${1:-}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
if [ -n "$VERSION" ] && [ "$VERSION" != "$PLIST_VERSION" ]; then
    echo "⚠ Version mismatch: arg=$VERSION but Info.plist=$PLIST_VERSION."
    echo "  Update Resources/Info.plist first so the updater compares correctly."
    exit 1
fi

echo "▸ Building signed app + dmg…"
make -C "$ROOT" dmg

echo "▸ Zipping the app (signature-preserving)…"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo ""
echo "✓ Release artifacts ready (v$PLIST_VERSION):"
echo "    $DIST/Prism.dmg   → drag-install for new users"
echo "    $ZIP   → attach so the in-app updater can auto-install"
echo ""
echo "  Next: create a GitHub release tagged v$PLIST_VERSION and upload BOTH."

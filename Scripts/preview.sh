#!/usr/bin/env bash
# Renders a HubOS view into an isolated window and screenshots just that window.
# Usage: preview.sh [output.png] [target]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/hubos_preview.png}"
TARGET="${2:-hub}"

swift build >/dev/null 2>&1
BIN="$(swift build --show-bin-path)/HubOS"

rm -f "$OUT"
HUBOS_PREVIEW_OUT="$OUT" HUBOS_PREVIEW_TARGET="$TARGET" "$BIN" --preview >/dev/null 2>&1 &
PID=$!

for _ in $(seq 1 40); do
    [ -f "$OUT" ] && break
    sleep 0.2
done
sleep 0.3
kill "$PID" >/dev/null 2>&1 || true
wait "$PID" 2>/dev/null || true

if [ -f "$OUT" ]; then
    echo "✓ $OUT"
else
    echo "✗ no output produced"
    exit 1
fi

#!/bin/bash
# Stages and builds the drag-to-install disk image: the app, a symbolic link to
# /Applications, and a short read-me with the right-click Open step. The dmg
# carries the app and its bundled resources only; model weights are never inside.
#
# Usage: build_dmg.sh [--stage-only] [app-path] [staging-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE_ONLY=0
if [ "${1:-}" = "--stage-only" ]; then
  STAGE_ONLY=1
  shift
fi
APP_PATH="${1:-$ROOT/dist/WordFlow.app}"
STAGING="${2:-$ROOT/dist/dmg-staging}"
DMG="$ROOT/dist/WordFlow.dmg"

if [ ! -d "$APP_PATH" ]; then
  echo "error: no app bundle at $APP_PATH (run make app-bundle first)" >&2
  exit 1
fi

echo "==> staging $STAGING"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/WordFlow.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read me first.txt" <<'EOF'
Installing WordFlow

1. Drag WordFlow.app onto the Applications folder alongside it.
2. The first time only: right-click (or Control-click) the app in Applications
   and choose Open, then Open again in the dialogue. This is needed because the
   app is signed locally rather than notarised.
3. WordFlow lives in the menu bar (there is no Dock icon). On first launch it
   asks for Microphone and Accessibility access, fetches its backend, and
   downloads the speech models. It needs the network for that first run only.
4. Hold the § key and speak. Release, and your words appear at the cursor. On a
   keyboard without a § key, hold Right Command instead. Double-tap to lock
   hands-free; press Esc to cancel.
EOF

if [ "$STAGE_ONLY" = "1" ]; then
  echo "==> staged only (no dmg)"
  exit 0
fi

echo "==> building $DMG"
rm -f "$DMG"
hdiutil create -volname "WordFlow" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
echo "==> built $DMG"

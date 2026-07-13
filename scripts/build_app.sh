#!/bin/bash
# Builds dist/WordFlow.app from the SwiftPM package and signs it with the local
# self-signed certificate (see scripts/make_signing_cert.sh). The bundle carries
# everything provisioning needs on a new Mac: the backend source, a uv binary,
# and the bundled language resources. Model weights are never bundled.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/WordFlow.app"
IDENTITY="${SIGNING_IDENTITY:-WordFlow Local Signing}"

echo "==> building the Swift app (release)"
cd "$ROOT/app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "==> assembling ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN/WordFlowApp" "$APP_DIR/Contents/MacOS/WordFlowApp"
cp "$ROOT/app/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$ROOT/app/Support/AppIcon.icns" ]; then
  cp "$ROOT/app/Support/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
else
  echo "warning: no AppIcon.icns yet (branding pending); building without an icon" >&2
fi

echo "==> bundling language resources"
RES="$APP_DIR/Contents/Resources"
mkdir -p "$RES/language"
cp "$ROOT/backend/wordflow/resources/american_to_british.json" "$RES/language/"
cp "$ROOT/backend/wordflow/resources/NOTICE-VarCon.txt" "$RES/language/"
cp "$ROOT/backend/wordflow/resources/technical_allowlist.txt" "$RES/language/"
cp "$ROOT/backend/wordflow/resources/fillers.txt" "$RES/language/"
cp -R "$ROOT/backend/wordflow/resources/dict" "$RES/language/dict"

echo "==> bundling the backend for first-run provisioning"
mkdir -p "$RES/backend"
rsync -a --delete \
  --exclude '.venv' --exclude '__pycache__' --exclude '.pytest_cache' --exclude 'tests' \
  "$ROOT/backend/pyproject.toml" "$ROOT/backend/wordflow" "$RES/backend/"
if command -v uv >/dev/null 2>&1; then
  cp "$(command -v uv)" "$RES/uv"
else
  echo "warning: uv not found on the build machine; first-run provisioning needs it" >&2
fi

if [ "${SKIP_SIGNING:-0}" = "1" ]; then
  echo "==> SKIP_SIGNING=1, leaving the bundle unsigned"
  exit 0
fi

# A stable signing identity keeps macOS permissions (Accessibility, Microphone)
# across rebuilds; ad-hoc signatures change every build and lose the grant.
# Prefer the configured identity, then any local self-signed "*Local Signing"
# identity on the machine, then ad-hoc as a last resort.
SIGN="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  SIGN="$IDENTITY"
else
  ALT="$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '"[^"]*Local Signing"' | head -1 | tr -d '"')"
  [ -n "$ALT" ] && SIGN="$ALT"
fi
if [ "$SIGN" = "-" ]; then
  echo "==> no local signing identity; signing ad-hoc (permissions will not persist across rebuilds)"
  echo "    create one once with scripts/make_signing_cert.sh for stable permissions"
else
  echo "==> signing with the stable local identity '$SIGN'"
fi

# Sign every embedded Mach-O first, then the bundle with the entitlements.
find "$APP_DIR/Contents/Resources" -type f \( -name 'uv' -o -name '*.dylib' -o -name '*.so' \) -print0 |
  while IFS= read -r -d '' binary; do
    codesign --force --sign "$SIGN" "$binary" 2>/dev/null || true
  done
codesign --force --sign "$SIGN" \
  --entitlements "$ROOT/app/Support/WordFlow.entitlements" \
  "$APP_DIR"
codesign --verify --strict "$APP_DIR" && echo "==> built and signed $APP_DIR"

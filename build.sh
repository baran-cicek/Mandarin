#!/bin/bash
# Builds dist/<Name>.app from the Swift package. Runs the self-tests first.
#   ./build.sh            build + ad-hoc/dev-cert sign
#   SKIP_TESTS=1 ./build.sh   skip the self-test run (used by install.sh, which tests separately)
#   ADHOC=1 ./build.sh        always sign ad-hoc, even if a developer certificate exists (for distributable builds)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST="$ROOT/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"
EXECUTABLE_PRODUCT="MandarinApp"
BUILD_DIR="$ROOT/.build/release"
DIST_DIR="$ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

cd "$ROOT"

if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "==> Running self-tests"
  swift run MandarinSelfTests
fi

echo "==> Building $APP_NAME (release)"
swift build -c release

echo "==> Generating app icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC="$ROOT/Resources/mandarin-icon.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
ICNS="$(mktemp -d)/AppIcon.icns"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "==> Assembling app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$EXECUTABLE_PRODUCT" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PLIST" "$APP_BUNDLE/Contents/Info.plist"
cp "$ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> Code signing"
if [ "${ADHOC:-0}" = "1" ]; then
  IDENTITY=""
else
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
fi
if [ -z "$IDENTITY" ]; then
  echo "    Signing ad-hoc (no developer certificate used)."
  codesign --force --deep --sign - "$APP_BUNDLE"
else
  echo "    Signing with: $IDENTITY"
  codesign --force --deep --options runtime --sign "$IDENTITY" "$APP_BUNDLE"
fi

codesign --verify --verbose "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE"

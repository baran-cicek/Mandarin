#!/bin/bash
# Signed + notarized release build. NOT run by anyone automatically and not
# needed for normal use (install.sh builds an ad-hoc-signed app locally).
#
# Needs an Apple Developer account. Fill in the placeholders, or export them:
#   DEVELOPER_ID="Developer ID Application: YOUR NAME (TEAMID)"
#   NOTARY_PROFILE="your-notarytool-keychain-profile"
# Create the profile once with:
#   xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id YOU@EXAMPLE.COM --team-id TEAMID
set -euo pipefail

DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: YOUR NAME (TEAMID)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-YOUR-NOTARY-PROFILE}"

case "$DEVELOPER_ID$NOTARY_PROFILE" in
  *"YOUR NAME"*|*"YOUR-NOTARY"*) echo "Fill in DEVELOPER_ID and NOTARY_PROFILE first (see the top of this file)." >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$ROOT/Resources/Info.plist")"
APP="$ROOT/dist/$APP_NAME.app"
ZIP="$ROOT/dist/$APP_NAME.zip"

"$ROOT/build.sh"

echo "==> Signing with Developer ID (hardened runtime)"
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Notarizing (uploads the app to Apple; this is the only network step)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"
echo "==> Done: $ZIP"

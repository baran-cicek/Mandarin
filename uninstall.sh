#!/bin/bash
# Removes the installed app and (optionally) its preferences.
#   ./uninstall.sh                 remove from /Applications
#   ./uninstall.sh --prefix DIR    remove from DIR (matches install.sh --prefix)
#   ./uninstall.sh --purge         also delete saved settings
# Homebrew tools are left alone; remove them with `brew uninstall` if wanted.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST="$ROOT/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
TARGET="/Applications"
PURGE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) TARGET="${2:?--prefix needs a directory}"; shift 2 ;;
    --purge) PURGE=1; shift ;;
    -h|--help) sed -n 2,6p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

DEST="$TARGET/$APP_NAME.app"
echo "==> Removing $DEST"
if [ -d "$DEST" ]; then
  [ "$TARGET" = "/Applications" ] && osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  rm -rf "$DEST"
  echo "    Removed."
else
  echo "    Not installed there; nothing to do."
fi

if [ "$PURGE" = "1" ] && [ "$TARGET" = "/Applications" ]; then
  echo "==> Deleting saved settings ($BUNDLE_ID)"
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || echo "    No saved settings found."
fi

echo "==> Done. You can also remove $APP_NAME from the Accessibility and Input Monitoring lists in System Settings."

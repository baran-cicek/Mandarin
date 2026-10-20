#!/bin/bash
# Installs the app: checks the system, installs missing Homebrew tools,
# builds the app, copies it to the target folder.
#
#   ./install.sh                       install to /Applications
#   ./install.sh --prefix DIR          install into DIR instead (dry runs)
#   ./install.sh --skip-deps           don't touch Homebrew
#   ./install.sh --yes                 don't ask before installing packages
#
# Safe to run repeatedly. Never calls sudo; if the target folder isn't
# writable, it tells you instead of escalating.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST="$ROOT/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"
TARGET="/Applications"
SKIP_DEPS=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) TARGET="${2:?--prefix needs a directory}"; shift 2 ;;
    --skip-deps) SKIP_DEPS=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) sed -n 2,11p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$1"; }
fail() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }

step "Checking your Mac"
[ "$(uname -s)" = "Darwin" ] || fail "$APP_NAME only runs on macOS."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 13 ] || fail "macOS 13 (Ventura) or later is required; this Mac has $(sw_vers -productVersion)."
[ "$(uname -m)" = "arm64" ] || fail "An Apple Silicon Mac is required; this one reports $(uname -m)."
echo "    macOS $(sw_vers -productVersion), Apple Silicon: ok"

step "Checking Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  fail "The Xcode Command Line Tools are missing. Run: xcode-select --install   (then re-run this script)"
fi
echo "    $(xcode-select -p): ok"

if [ "$SKIP_DEPS" = "1" ]; then
  step "Skipping Homebrew tools (--skip-deps)"
else
  step "Checking Homebrew tools"
  if ! command -v brew >/dev/null 2>&1; then
    fail "Homebrew is not installed. Get it from https://brew.sh, or re-run with --skip-deps and install the tools in the Brewfile yourself."
  fi
  MISSING_FORMULAE=()
  for tool in ffmpeg pandoc unar webp; do
    if brew list --formula "$tool" >/dev/null 2>&1; then echo "    $tool: already installed"; else MISSING_FORMULAE+=("$tool"); fi
  done
  MISSING_CASKS=()
  if brew list --cask libreoffice >/dev/null 2>&1 || [ -d "/Applications/LibreOffice.app" ]; then
    echo "    libreoffice: already installed"
  else
    MISSING_CASKS+=("libreoffice")
  fi

  if [ ${#MISSING_FORMULAE[@]} -gt 0 ] || [ ${#MISSING_CASKS[@]} -gt 0 ]; then
    echo "    Missing: ${MISSING_FORMULAE[*]:-} ${MISSING_CASKS[*]:-}"
    if [ "$ASSUME_YES" != "1" ]; then
      if [ -t 0 ]; then
        read -r -p "    Install them with Homebrew now? [y/N] " answer
        case "$answer" in y|Y|yes) ;; *) fail "Cancelled. Install them yourself (brew bundle) or re-run with --skip-deps." ;; esac
      else
        fail "Tools are missing and there is no terminal to ask. Re-run with --yes or --skip-deps."
      fi
    fi
    for tool in ${MISSING_FORMULAE[@]+"${MISSING_FORMULAE[@]}"}; do
      step "Installing $tool (brew install $tool)"
      brew install "$tool"
    done
    for tool in ${MISSING_CASKS[@]+"${MISSING_CASKS[@]}"}; do
      step "Installing $tool (brew install --cask $tool; this one is large)"
      brew install --cask "$tool"
    done
  fi
fi

step "Building $APP_NAME (runs the self-tests first)"
"$ROOT/build.sh"

step "Copying to $TARGET"
mkdir -p "$TARGET" 2>/dev/null || true
[ -w "$TARGET" ] || fail "$TARGET isn't writable by your user. Choose another folder with --prefix, or copy dist/$APP_NAME.app there yourself."
DEST="$TARGET/$APP_NAME.app"
if pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$TARGET" = "/Applications" ]; then
  echo "    $APP_NAME is running; quitting it so the new version can replace it."
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  sleep 1
fi
rm -rf "$DEST"
cp -R "$ROOT/dist/$APP_NAME.app" "$DEST"
echo "    Installed: $DEST"

cat <<MSG

==> Done. Before first use, grant these in System Settings -> Privacy & Security:

    Accessibility      so $APP_NAME can notice that you're dragging a file and
                       show the wheel next to the cursor.
    Input Monitoring   so $APP_NAME can see Shift/Command/Control/Option taps
                       while a drag is in progress (they pick the wheel).
    Automation         asked by macOS the first time you select a file in Finder
                       and press Return: lets $APP_NAME ask Finder what is
                       selected. Allow "Finder".

    Open the app:   open "$DEST"
    After you rebuild or reinstall, macOS may treat the app as new: remove and
    re-add it in the two lists above if the wheel stops appearing.
MSG

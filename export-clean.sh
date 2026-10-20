#!/bin/bash
# Creates a publishable copy of the tracked files with ONE new commit and a
# neutral author. The original history is not touched.
#   ./export-clean.sh [DEST]       default DEST: ../<repo-folder>-clean-export
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$ROOT/../$(basename "$ROOT")-clean-export}"

[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ] || { echo "Commit your changes first." >&2; exit 1; }
[ ! -e "$DEST" ] || { echo "$DEST already exists; remove it or pass another path." >&2; exit 1; }

mkdir -p "$DEST"
git -C "$ROOT" archive HEAD | tar -x -C "$DEST"

# Safety net: refuse to export if personal data or a session export slipped in.
PATTERN="Bar""ans-Air|/Users/""[a-z]+|gmail""\.com|bar""an|cic""ek|fritz""\.box"
if grep -rIlE "$PATTERN" "$DEST" >/dev/null 2>&1 || find "$DEST" -name '*local-command-caveat*' | grep -q .; then
  grep -rIlE "$PATTERN" "$DEST" >&2 || true
  rm -rf "$DEST"
  echo "Personal data or a session export found; export aborted." >&2
  exit 1
fi

cd "$DEST"
git init -q -b main
git add -A
GIT_AUTHOR_NAME="Mandarin Contributors" GIT_AUTHOR_EMAIL="noreply@example.invalid" \
GIT_COMMITTER_NAME="Mandarin Contributors" GIT_COMMITTER_EMAIL="noreply@example.invalid" \
  git commit -q -m "Initial public release"
echo "Clean export: $DEST"
git log --format='%h %an <%ae> %s'

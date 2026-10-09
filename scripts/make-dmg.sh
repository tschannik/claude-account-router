#!/bin/bash
# Builds the installer .dmg: custom background, app + Applications shortcut, app icon as volume icon.
#   scripts/make-dmg.sh "build/Claude Accounts.app" build/Claude-Accounts-1.0.0.dmg
# Uses dmgbuild (pure Python, writes the Finder layout directly, so it works headless on CI).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"; OUT="$2"
WORK=build/dmg

rm -rf "$WORK"; mkdir -p "$WORK"
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install -q dmgbuild

"$APP/Contents/MacOS/ClaudeAccounts" --render-dmg-background "$WORK"
tiffutil -cat "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff"

rm -f "$OUT"
"$WORK/venv/bin/dmgbuild" -s scripts/dmg-settings.py \
  -D app="$APP" -D volicon="$APP/Contents/Resources/AppIcon.icns" -D background="$WORK/background.tiff" \
  "Claude Accounts" "$OUT"
echo "dmg: $OUT"

#!/bin/bash
# Builds "Claude Accounts.app" into ./build. Universal binary, signed with $SIGN_IDENTITY
# (default: ad hoc, fine for local use; releases pass the Developer ID).
#   VERSION=1.2.3 SIGN_IDENTITY="Developer ID Application: ..." scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.0.0-dev}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Claude Accounts.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ClaudeAccounts"

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeAccounts"
"$APP/Contents/MacOS/ClaudeAccounts" --render-app-icon "$APP/Contents/Resources/AppIcon.icns"

cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.yannik.claude-accounts</string>
  <key>CFBundleName</key><string>Claude Accounts</string>
  <key>CFBundleDisplayName</key><string>Claude Accounts</string>
  <key>CFBundleExecutable</key><string>ClaudeAccounts</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array>
    <dict><key>CFBundleURLName</key><string>Claude link</string>
          <key>CFBundleURLSchemes</key><array><string>claude</string></array></dict>
    <dict><key>CFBundleURLName</key><string>Claude Accounts launcher</string>
          <key>CFBundleURLSchemes</key><array><string>claudeaccounts</string></array></dict>
  </array>
</dict></plist>
PLIST

if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP" && echo "built: $APP ($VERSION)"

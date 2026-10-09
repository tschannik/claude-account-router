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

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/ClaudeAccounts"
SPARKLE_FW="$(find .build/artifacts -path '*macos-arm64_x86_64/Sparkle.framework' -maxdepth 6 | head -1)"
[ -d "$SPARKLE_FW" ] || { echo "Sparkle.framework not found (run swift build first)"; exit 1; }
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
# The app is not sandboxed, so Sparkle's XPC helper services are not needed.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
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
  <key>NSHumanReadableCopyright</key><string>© 2026 Yannik Zimmermann. MIT License.</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>SUFeedURL</key><string>https://github.com/tschannik/claude-account-router/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>7CIGgvQcCsp/x/wvEw8RZGABc3b+306wjjHYMx0szMo=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>CFBundleURLTypes</key><array>
    <dict><key>CFBundleURLName</key><string>Claude link</string>
          <key>CFBundleURLSchemes</key><array><string>claude</string></array></dict>
    <dict><key>CFBundleURLName</key><string>Claude Accounts launcher</string>
          <key>CFBundleURLSchemes</key><array><string>claudeaccounts</string></array></dict>
  </array>
</dict></plist>
PLIST

# Sign inside-out: Sparkle's helpers, then the framework, then the app (hardened runtime for releases).
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [ "$IDENTITY" = "-" ]; then SIGN=(codesign --force --sign -); else SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY"); fi
"${SIGN[@]}" "$FW/Autoupdate"
"${SIGN[@]}" "$FW/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP" && echo "built: $APP ($VERSION)"

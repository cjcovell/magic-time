#!/bin/zsh
# Builds Magic Time.app and installs it to /Applications.
# Requires Xcode (actool compiles the Icon Composer icon).
# Usage: ./build.sh            test, build, install
#        ./build.sh --no-install
set -euo pipefail

ROOT=${0:A:h}
BUILD="$ROOT/build"
APP="$BUILD/Magic Time.app"
DEST="/Applications/Magic Time.app"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "→ Parser checks"
swiftc -O -o "$BUILD/check" "$ROOT/Sources/TimeParser.swift" "$ROOT/Tests/main.swift"
"$BUILD/check"

echo "→ Compiling app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 \
  -o "$APP/Contents/MacOS/MagicTime" \
  "$ROOT"/Sources/*.swift

echo "→ Icon"
# Icon Composer document → Assets.car (macOS 26+ Liquid Glass) + AppIcon.icns (older macOS).
xcrun actool "$ROOT/Icon/AppIcon.icon" --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$BUILD/icon-partial.plist" >/dev/null

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Magic Time</string>
  <key>CFBundleDisplayName</key><string>Magic Time</string>
  <key>CFBundleIdentifier</key><string>cc.covell.magictime</string>
  <key>CFBundleExecutable</key><string>MagicTime</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

if [[ "${1:-}" != "--no-install" ]]; then
  echo "→ Installing to $DEST"
  was_running=false
  pgrep -qx MagicTime && was_running=true
  pkill -x MagicTime 2>/dev/null || true
  for _ in {1..50}; do pgrep -qx MagicTime || break; sleep 0.1; done
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  mdimport "$DEST" 2>/dev/null || true
  # Bring back a copy that was running, quietly, so ⌃⌥⌘T keeps working.
  if $was_running; then
    open -g "$DEST" --args --background
  fi
fi
echo "✓ Done"

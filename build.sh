#!/bin/zsh
# Builds Discord Time.app and installs it to ~/Applications (Spotlight indexes it there).
# Usage: ./build.sh            test, build, install
#        ./build.sh --no-install
set -euo pipefail

ROOT=${0:A:h}
BUILD="$ROOT/build"
APP="$BUILD/Discord Time.app"
DEST="$HOME/Applications/Discord Time.app"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "→ Parser checks"
swiftc -O -o "$BUILD/check" "$ROOT/Sources/TimeParser.swift" "$ROOT/Tests/main.swift"
"$BUILD/check"

echo "→ Compiling app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 \
  -o "$APP/Contents/MacOS/DiscordTime" \
  "$ROOT/Sources/TimeParser.swift" "$ROOT/Sources/App.swift"

echo "→ Icon"
swift "$ROOT/Tools/make_icon.swift" "$BUILD/AppIcon.iconset"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$BUILD/AppIcon.iconset"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Discord Time</string>
  <key>CFBundleDisplayName</key><string>Discord Time</string>
  <key>CFBundleIdentifier</key><string>cc.covell.discordtime</string>
  <key>CFBundleExecutable</key><string>DiscordTime</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

if [[ "${1:-}" != "--no-install" ]]; then
  echo "→ Installing to $DEST"
  pkill -x DiscordTime 2>/dev/null || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  mdimport "$DEST" 2>/dev/null || true
fi
echo "✓ Done"

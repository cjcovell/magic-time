#!/bin/zsh
# Takes every App Store screenshot, the same way every time: five phrases on four simulators
# (iPhone 6.9" and 6.3", iPad 13" and 11"), a 6.5" iPhone set scaled from the 6.9" one, and the
# Mac panel on a 2880 × 1800 backdrop.
# Usage: scripts/screenshots.sh [output folder]     (default: ../magic-time-store-assets/screenshots)
# Needs Xcode, the simulators named below, and Python with Pillow (for the Mac backdrop).
set -euo pipefail

ROOT=${0:A:h:h}
OUT=${1:-$ROOT/../magic-time-store-assets/screenshots}
WORK=$(mktemp -d)
PYTHON=$(command -v python3)                          # before the PATH change: this one has Pillow
"$PYTHON" -c "import PIL" 2>/dev/null || { echo "Python needs Pillow: $PYTHON -m pip install Pillow"; exit 1; }
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"    # Homebrew rsync breaks Xcode packaging

# What each screenshot shows. Change these here and every device follows.
# The last one shows the Apple Intelligence suggestion, so the Mac running this needs Apple
# Intelligence turned on; without it that screenshot shows only “No date or time found”.
PHRASES=("fri 8pm PT" "christmas eve 8pm" "tomorrow london noon" "eid 7pm" "3rd friday in may at 6pm"
         "the 15th at eight thirty at night")
NAMES=(1-fri-8pm-pt 2-christmas-eve 3-tomorrow-london-noon 4-wont-guess-eid 5-third-friday-in-may
       6-suggests-a-phrase)
# Folder name = simulator name.
typeset -A DEVICES=(
  "iPhone 6.9in" "iPhone 18 Pro Max"
  "iPhone 6.3in" "iPhone 18 Pro"
  "iPad 13in"    "iPad Pro 13-inch (M5)"
  "iPad 11in"    "iPad Pro 11-inch (M5)"
)

echo "→ Building the iPhone and iPad app (Debug, for -MTPrefill)"
xcodebuild -project "$ROOT/MagicTime.xcodeproj" -scheme MagicTime-iOS -configuration Debug -sdk iphonesimulator \
  -derivedDataPath "$WORK/sim" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD FAILED" && exit 1
APP="$WORK/sim/Build/Products/Debug-iphonesimulator/Magic Time.app"

rm -rf "$OUT"; mkdir -p "$OUT"
for folder in ${(k)DEVICES}; do
  name=$DEVICES[$folder]
  udid=$(xcrun simctl list devices available | grep -F "$name (" | head -1 | grep -oE "[0-9A-F-]{36}")
  [[ -n "$udid" ]] || { echo "No simulator named “$name”. Add it in Xcode > Settings > Components."; exit 1; }
  echo "→ $folder ($name)"
  mkdir -p "$OUT/$folder"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl install "$udid" "$APP"
  xcrun simctl spawn "$udid" defaults delete cc.covell.magictime zone 2>/dev/null || true   # start on Local
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState discharging --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3 --operatorName ""
  for n in {1..$#PHRASES}; do
    xcrun simctl terminate "$udid" cc.covell.magictime 2>/dev/null || true
    sleep 1
    xcrun simctl launch "$udid" cc.covell.magictime -MTPrefill "$PHRASES[$n]" >/dev/null
    sleep 6                                             # long enough for a suggestion to arrive
    xcrun simctl io "$udid" screenshot "$OUT/$folder/$NAMES[$n].png" >/dev/null 2>&1
  done
  xcrun simctl status_bar "$udid" clear
done

echo "→ iPhone 6.5in (scaled from 6.9in)"
mkdir -p "$OUT/iPhone 6.5in"
for n in $NAMES; do
  sips --resampleWidth 1284 "$OUT/iPhone 6.9in/$n.png" --out "$WORK/scaled.png" >/dev/null
  sips --cropToHeightWidth 2778 1284 "$WORK/scaled.png" --out "$OUT/iPhone 6.5in/$n.png" >/dev/null
done

echo "→ Building the Mac app (Debug)"
xcodebuild -project "$ROOT/MagicTime.xcodeproj" -scheme MagicTime-macOS -configuration Debug \
  -derivedDataPath "$WORK/mac" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build 2>&1 \
  | grep -E "error:|BUILD FAILED" && exit 1
MACAPP="$WORK/mac/Build/Products/Debug/Magic Time.app"

echo "→ Mac 2880x1800 (the panel opens on screen briefly; don’t type while it does)"
was_running=false; pgrep -qx MagicTime && was_running=true
restore() { $was_running && open -g "/Applications/Magic Time.app" --args --background 2>/dev/null || true }
trap restore EXIT                                     # even if a capture fails
pkill -x MagicTime 2>/dev/null || true
sleep 1
panel_window() {
  swift -e 'import CoreGraphics
let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in all where (w["kCGWindowOwnerName"] as? String) == "Magic Time" && (w["kCGWindowLayer"] as? Int) == 3 { print(w["kCGWindowNumber"]!); break }' 2>/dev/null
}
mkdir -p "$WORK/panels"
for n in {1..$#PHRASES}; do
  open -n "$MACAPP" --args -MTPrefill "$PHRASES[$n]" -style F -zone local -NSRequiresAquaSystemAppearance YES
  window=""
  for wait in {1..20}; do                             # a freshly built app can take a while to open
    window=$(panel_window)
    [[ -n "$window" ]] && break
    sleep 1
  done
  [[ -n "$window" ]] || { echo "The Mac panel didn’t open."; exit 1; }
  sleep 5                                             # long enough for a suggestion to arrive
  captured=false
  for try in {1..5}; do                               # a window that just opened can refuse once
    screencapture -x -l "$window" "$WORK/panels/$NAMES[$n].png" 2>/dev/null && { captured=true; break }
    sleep 1
  done
  $captured || { echo "Couldn’t capture the Mac panel for “$PHRASES[$n]”."; exit 1; }
  pkill -f "Debug/Magic Time.app/Contents/MacOS/Magic Time" || true
  sleep 1
done

mkdir -p "$OUT/Mac 2880x1800"
"$PYTHON" - "$WORK/panels" "$OUT/Mac 2880x1800" <<'PY'
import os, sys
from PIL import Image, ImageDraw
src, out = sys.argv[1], sys.argv[2]
W, H = 2880, 1800
top, bottom = (232, 234, 252), (205, 210, 250)      # pale periwinkle to lavender
bg = Image.new("RGB", (W, H))
draw = ImageDraw.Draw(bg)
for y in range(H):
    t = y / (H - 1)
    draw.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
for name in sorted(os.listdir(src)):
    panel = Image.open(os.path.join(src, name)).convert("RGBA")
    panel = panel.resize((int(panel.width * 1.3), int(panel.height * 1.3)), Image.LANCZOS)
    canvas = bg.copy().convert("RGBA")
    canvas.alpha_composite(panel, ((W - panel.width) // 2, (H - panel.height) // 2))
    canvas.convert("RGB").save(os.path.join(out, name))
PY

rm -rf "$WORK"
echo "✓ Screenshots in $OUT"
for folder in "$OUT"/*(/); do
  first=("$folder"/*.png(N[1]))
  echo "  ${folder:t}: $(ls "$folder" | wc -l | tr -d ' ') files, $(sips -g pixelWidth -g pixelHeight "$first" | awk '/pixel/{printf $2" "}')"
done

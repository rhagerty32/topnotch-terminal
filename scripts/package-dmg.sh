#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="${MARKETING_VERSION:-0.1.0}"
app_name="TopNotch Terminal"
volume_name="TopNotch Terminal"
app="build/Build/Products/Release/${app_name}.app"
background="Resources/dmg/background.png"
stage="dist/dmg-stage"
rw="dist/rw.dmg"
dmg="dist/TopNotchTerminal-${version}.dmg"
mount="/Volumes/${volume_name}"

# Finder icon-view points; must match scripts/render-dmg-background.swift
window_w=720
window_h=468
content_h=440
apps_x=360
apps_y=68
app_x=360
app_y=292

if [[ "${SKIP_BUILD:-}" != "1" ]]; then
  xcodegen generate
  export DEVELOPER_DIR="$(bash "$root/scripts/metal-developer-dir.sh")"
  xcodebuild \
    -scheme TopNotchTerminal \
    -configuration Release \
    -derivedDataPath build \
    -destination 'platform=macOS' \
    build
fi

swift "$root/scripts/render-dmg-background.swift" "$background"

if [[ -d "$mount" ]]; then
  hdiutil detach "$mount" -force >/dev/null || true
fi

rm -rf "$stage" "$rw" "$dmg"
mkdir -p "$stage/.background"
ditto "$app" "$stage/${app_name}.app"
ln -s /Applications "$stage/Applications"
cp "$background" "$stage/.background/background.png"
chflags hidden "$stage/.background"

hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$stage" \
  -ov \
  -format UDRW \
  "$rw" >/dev/null

hdiutil attach -readwrite -noverify -noautoopen "$rw" >/dev/null

for _ in {1..30}; do
  [[ -d "$mount" ]] && break
  sleep 0.1
done

bless --folder "$mount" --openfolder "$mount" >/dev/null 2>&1 || true

osascript <<EOF
tell application "Finder"
  tell disk "$volume_name"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    try
      set pathbar visible of container window to false
    end try
    set sidebar width of container window to 0
    set the bounds of container window to {280, 120, $((280 + window_w)), $((120 + window_h))}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 80
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:background.png"
    set extension hidden of item "${app_name}.app" to true
    set position of item "${app_name}.app" to {$app_x, $app_y}
    set position of item "Applications" to {$apps_x, $apps_y}
    set position of item ".background" to {8000, 8000}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
tell application "System Events"
  tell process "Finder"
    set frontmost to true
    try
      click menu item "Hide Path Bar" of menu "View" of menu bar 1
    end try
    try
      click menu item "Hide Tab Bar" of menu "View" of menu bar 1
    end try
  end tell
end tell
delay 0.4
EOF

sync
hdiutil detach "$mount" >/dev/null
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg" >/dev/null
rm -f "$rw"

echo "DMG ready: $dmg"
echo "Open it and drag TopNotch Terminal up into the notch."

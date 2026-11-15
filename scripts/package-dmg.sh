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

if [[ "${SKIP_BUILD:-}" != "1" ]]; then
  xcodegen generate
  export DEVELOPER_DIR="$(bash "$root/scripts/metal-developer-dir.sh")"
  xcodebuild \
    -scheme TopNotchTerminal \
    -configuration Release \
    -derivedDataPath build \
    -destination 'platform=macOS' \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$version" \
    build
fi

if [[ ! -f "$background" ]]; then
  swift "$root/scripts/render-dmg-background.swift" "$background"
fi
if [[ ! -d "$app" ]]; then
  echo "Release app not found at $app" >&2
  exit 1
fi

if [[ -d "$mount" ]]; then
  hdiutil detach "$mount" -force >/dev/null || true
fi

venv="$root/dist/.packaging-venv"
if [[ ! -x "$venv/bin/python" ]]; then
  python3 -m venv "$venv"
  "$venv/bin/pip" install --disable-pip-version-check -r "$root/scripts/packaging-requirements.txt"
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

attach_plist="$(mktemp)"
hdiutil attach -readwrite -noverify -noautoopen -nobrowse -plist "$rw" >"$attach_plist"
device="$(python3 - "$attach_plist" <<'PY'
import plistlib, sys
plist = plistlib.load(open(sys.argv[1], "rb"))
for entity in plist["system-entities"]:
    if entity.get("mount-point"):
        print(entity["dev-entry"])
        break
PY
)"
rm -f "$attach_plist"
if [[ -z "$device" ]]; then
  echo "Disk image attached without a device node" >&2
  exit 1
fi

cleanup() {
  if [[ -n "${device:-}" ]]; then
    hdiutil detach "$device" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

for _ in {1..30}; do
  [[ -d "$mount" ]] && break
  sleep 0.1
done
if [[ ! -d "$mount" ]]; then
  echo "Disk image did not mount at $mount" >&2
  exit 1
fi

chflags hidden "$mount/.background"
"$venv/bin/python" "$root/scripts/write_dmg_layout.py" "$mount"
bless --folder "$mount" --openfolder "$mount" >/dev/null 2>&1 || true
sync
hdiutil detach "$device" >/dev/null
device=""
trap - EXIT

hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg" >/dev/null
rm -f "$rw"

echo "DMG ready: $dmg"
echo "Open it and drag TopNotch Terminal up into the notch."

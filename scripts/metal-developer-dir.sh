#!/bin/bash
# Xcode 27 ships a metal stub that only works after the separate Metal
# toolchain is mounted. Print a DEVELOPER_DIR whose metal is the real compiler.
set -euo pipefail

XCODE_APP="/Applications/Xcode.app"
XCODE_DEV="$XCODE_APP/Contents/Developer"
STUB="$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/metal"

if "$STUB" --version >/dev/null 2>&1; then
    printf '%s\n' "$XCODE_DEV"
    exit 0
fi

SEARCH=$(xcodebuild -showComponent MetalToolchain 2>/dev/null | awk -F': ' '/Toolchain Search Path:/ { print $2; exit }')
REAL_BIN="$SEARCH/Metal.xctoolchain/usr/metal/current/bin/metal"
if [[ ! -x "$REAL_BIN" ]]; then
    echo "Metal toolchain is missing. Run: xcodebuild -downloadComponent MetalToolchain" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/metal-developer/Xcode.app"
DEV="$APP/Contents/Developer"
TC="$DEV/Toolchains/XcodeDefault.xctoolchain"
SRC_TC="$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain"

mkdir -p "$APP/Contents" "$TC/usr/bin"
for item in "$XCODE_APP/Contents"/*; do
    name="$(basename "$item")"
    [[ "$name" == "Developer" ]] && continue
    ln -sfn "$item" "$APP/Contents/$name"
done
for item in "$XCODE_DEV"/*; do
    name="$(basename "$item")"
    [[ "$name" == "Toolchains" ]] && continue
    ln -sfn "$item" "$DEV/$name"
done
for item in "$SRC_TC"/*; do
    name="$(basename "$item")"
    [[ "$name" == "usr" ]] && continue
    ln -sfn "$item" "$TC/$name"
done
for item in "$SRC_TC/usr"/*; do
    name="$(basename "$item")"
    [[ "$name" == "bin" ]] && continue
    ln -sfn "$item" "$TC/usr/$name"
done
for tool in "$SRC_TC/usr/bin"/*; do
    name="$(basename "$tool")"
    [[ "$name" == "metal" ]] && continue
    ln -sfn "$tool" "$TC/usr/bin/$name"
done
REAL_DIR="$(dirname "$REAL_BIN")"
for tool in "$REAL_DIR"/metal*; do
    ln -sfn "$tool" "$TC/usr/bin/$(basename "$tool")"
done

printf '%s\n' "$DEV"

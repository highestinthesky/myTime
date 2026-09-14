#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="release"; [[ "${1:-}" == "--dev" ]] && MODE="dev"
FLAGS=(-c release --arch arm64)
[[ "$MODE" == "dev" ]] && FLAGS+=(-Xswiftc -DDEV_TIMESCALE)

swift build "${FLAGS[@]}"
BIN_DIR="$(swift build "${FLAGS[@]}" --show-bin-path)"

APP="build/myTime.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/myTime" "$APP/Contents/MacOS/myTime"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

launchctl bootout "gui/$(id -u)/local.mytime.agent" 2>/dev/null || true
rm -rf "$HOME/Applications/myTime.app"   # older builds installed here
rm -rf "/Applications/myTime.app"
cp -R "$APP" "/Applications/myTime.app"
"/Applications/myTime.app/Contents/MacOS/myTime"
echo "myTime installed ($MODE)."

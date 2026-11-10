#!/bin/sh
# Builds build/FanCtl.app (menu-bar app with fanctld helper bundled in Resources).
set -eu
cd "$(dirname "$0")"

swift build -c release
BIN=$(swift build -c release --show-bin-path)

APP=build/FanCtl.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp "$BIN/FanCtl" "$APP/Contents/MacOS/"
cp "$BIN/fanctld" scripts/install-helper.sh scripts/uninstall-helper.sh "$APP/Contents/Resources/"

codesign --force -s - "$APP/Contents/Resources/fanctld"
codesign --force -s - "$APP"
echo "Built $APP"

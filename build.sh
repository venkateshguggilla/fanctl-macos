#!/bin/sh
# Builds build/FanCtl.app (universal: Apple Silicon + Intel) with the fanctld helper in Resources.
# Signs with the first "Developer ID Application" identity in the keychain (override with
# SIGN_IDENTITY), falling back to ad-hoc signing when there is none.
set -eu
cd "$(dirname "$0")"

ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN=$(swift build -c release $ARCHS --show-bin-path)

APP=build/FanCtl.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp "$BIN/FanCtl" "$APP/Contents/MacOS/"
cp "$BIN/fanctld" scripts/install-helper.sh scripts/uninstall-helper.sh "$APP/Contents/Resources/"

IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')}
sign() {
    if [ -n "$IDENTITY" ]; then
        codesign --force --options runtime --timestamp -s "$IDENTITY" "$@"
    else
        codesign --force -s - "$@"
    fi
}
sign --identifier local.fanctl.daemon "$APP/Contents/Resources/fanctld"
sign "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"

#!/bin/sh
# Builds build/FanCtl-<version>.pkg, which installs FanCtl.app into /Applications and starts
# the fanctld helper. Signs with the first "Developer ID Installer" identity (override with
# INSTALLER_IDENTITY). Set NOTARY_PROFILE to a `notarytool store-credentials` profile name to
# notarize and staple the package.
set -eu
cd "$(dirname "$0")"

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
WORK=build/pkg
OUT=build/FanCtl-$VERSION.pkg
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/root/Applications" "$WORK/scripts"
ditto build/FanCtl.app "$WORK/root/Applications/FanCtl.app"
install -m 755 installer/postinstall "$WORK/scripts/postinstall"

# Always install to /Applications, even if another copy of the app exists elsewhere.
pkgbuild --analyze --root "$WORK/root" "$WORK/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/components.plist"

pkgbuild --root "$WORK/root" --component-plist "$WORK/components.plist" \
    --scripts "$WORK/scripts" --identifier local.fanctl.pkg --version "$VERSION" \
    --install-location / "$WORK/FanCtl.pkg"

# Runs natively on both architectures (no Rosetta prompt on Apple Silicon).
cat > "$WORK/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>FanCtl $VERSION</title>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <volume-check><allowed-os-versions><os-version min="13.0"/></allowed-os-versions></volume-check>
    <choices-outline><line choice="default"><line choice="local.fanctl.pkg"/></line></choices-outline>
    <choice id="default"/>
    <choice id="local.fanctl.pkg" visible="false"><pkg-ref id="local.fanctl.pkg"/></choice>
    <pkg-ref id="local.fanctl.pkg" version="$VERSION" onConclusion="none">FanCtl.pkg</pkg-ref>
</installer-gui-script>
EOF

IDENTITY=${INSTALLER_IDENTITY:-$(security find-identity -v | awk -F'"' '/Developer ID Installer/ { print $2; exit }')}
if [ -n "$IDENTITY" ]; then
    productbuild --distribution "$WORK/distribution.xml" --package-path "$WORK" --sign "$IDENTITY" --timestamp "$OUT"
else
    productbuild --distribution "$WORK/distribution.xml" --package-path "$WORK" "$OUT"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUT"
fi
echo "Built $OUT (installer signed: ${IDENTITY:-no})"

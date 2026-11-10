#!/bin/sh
# Installs fanctld as a root LaunchDaemon. Run as root:
#   install-helper.sh <dir containing fanctld> <uid allowed to use the socket>
set -eu

SRC="$1"
OWNER_UID="$2"
LABEL=local.fanctl.daemon
DEST=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist

launchctl bootout system/$LABEL 2>/dev/null || true

mkdir -p /Library/PrivilegedHelperTools
install -m 755 -o root -g wheel "$SRC/fanctld" "$DEST"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DEST</string>
        <string>--owner-uid</string>
        <string>$OWNER_UID</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/fanctld.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/fanctld.log</string>
</dict>
</plist>
EOF
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl bootstrap system "$PLIST"
echo "fanctld installed"

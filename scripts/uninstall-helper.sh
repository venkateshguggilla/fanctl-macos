#!/bin/sh
# Stops fanctld (which returns all fans to Auto on SIGTERM) and removes it. Run as root.
set -u

LABEL=local.fanctl.daemon
launchctl bootout system/$LABEL 2>/dev/null || true
rm -f /Library/LaunchDaemons/$LABEL.plist /Library/PrivilegedHelperTools/$LABEL /var/run/fanctld.sock
echo "fanctld removed"

#!/bin/bash
# Installs the Simmer privileged helper (LaunchDaemon) and simmerctl from an app bundle.
# Usage (as root): install-helper.sh /path/to/Simmer.app
# Idempotent: safe to run again to upgrade or repair an install.
set -euo pipefail

LABEL="com.umarwaseem.simmer.helper"
HELPER_DST="/Library/PrivilegedHelperTools/$LABEL"
PLIST_DST="/Library/LaunchDaemons/$LABEL.plist"
CTL_DST="/usr/local/bin/simmerctl"

if [[ $# -lt 1 ]]; then
    echo "usage: $0 /path/to/Simmer.app" >&2
    exit 64
fi
if [[ "$(id -u)" -ne 0 ]]; then
    echo "error: $0 must run as root" >&2
    exit 1
fi

APP="${1%/}"
RES="$APP/Contents/Resources"
HELPER_SRC="$RES/simmerd"
PLIST_SRC="$RES/$LABEL.plist"
CTL_SRC="$RES/simmerctl"

for f in "$HELPER_SRC" "$PLIST_SRC" "$CTL_SRC"; do
    [[ -f "$f" ]] || { echo "error: missing $f" >&2; exit 1; }
done

# Simmer never touches other apps' helpers. After install, `simmerctl conflicts` lists any other
# charge limiter that would fight over the same SMC keys, and `simmerctl fix-conflict <id>` removes it.

# Stop a previous Simmer helper, then wait until launchd has removed the job.
launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
for _ in $(seq 1 50); do
    launchctl print "system/$LABEL" >/dev/null 2>&1 || break
    sleep 0.1
done

mkdir -p /Library/PrivilegedHelperTools
install -o root -g wheel -m 0755 "$HELPER_SRC" "$HELPER_DST"
install -o root -g wheel -m 0644 "$PLIST_SRC" "$PLIST_DST"

mkdir -p /usr/local/bin
install -o root -g wheel -m 0755 "$CTL_SRC" "$CTL_DST"

launchctl enable "system/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap system "$PLIST_DST"

echo "Simmer helper installed: $HELPER_DST"
echo "simmerctl installed: $CTL_DST"

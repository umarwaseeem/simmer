#!/bin/bash
# Removes the Simmer privileged helper and simmerctl, and restores default charging (SMC keys).
# Usage (as root): uninstall-helper.sh [--purge]
#   --purge  also delete /Library/Application Support/Simmer and /Library/Logs/simmerd.log
set -euo pipefail

LABEL="com.umarwaseem.simmer.helper"
HELPER="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
CTL="/usr/local/bin/simmerctl"
SUPPORT="/Library/Application Support/Simmer"
LOG="/Library/Logs/simmerd.log"

PURGE=0
for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        *) echo "usage: $0 [--purge]" >&2; exit 64 ;;
    esac
done
if [[ "$(id -u)" -ne 0 ]]; then
    echo "error: $0 must run as root" >&2
    exit 1
fi

# Stop the daemon first so that it cannot apply the limit again after the reset.
launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
for _ in $(seq 1 50); do
    launchctl print "system/$LABEL" >/dev/null 2>&1 || break
    sleep 0.1
done

# Restore all SMC keys (charging, adapter, LED) to their defaults.
if [[ -x "$HELPER" ]]; then
    "$HELPER" --reset || echo "warning: '$HELPER --reset' failed" >&2
fi

# Undo a lid-close sleep block that a crashed daemon may have left behind.
if [[ -f "$SUPPORT/sleep-disabled-by-simmer" ]]; then
    pmset -a disablesleep 0 || true
    rm -f "$SUPPORT/sleep-disabled-by-simmer"
fi

rm -f "$PLIST" "$HELPER" "$CTL"

if [[ $PURGE -eq 1 ]]; then
    rm -rf "$SUPPORT"
    rm -f "$LOG"
    echo "Removed settings in $SUPPORT"
fi

echo "Simmer helper uninstalled."

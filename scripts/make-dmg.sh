#!/usr/bin/env bash
# Packages dist/Simmer.app into a compressed, drag-to-install disk image.
#
#   scripts/make-dmg.sh                       # dist/Simmer.app -> dist/Simmer-<version>.dmg
#   APP=/path/Simmer.app OUT=/path/x.dmg scripts/make-dmg.sh
#
# Environment:
#   DIST        folder that holds Simmer.app (default: <repo>/dist)
#   APP         the app bundle to package (default: $DIST/Simmer.app)
#   OUT         the output .dmg (default: $DIST/Simmer-<CFBundleShortVersionString>.dmg)
#   VOLNAME     volume name (default: Simmer)
#   DMG_LAYOUT  1 = ask Finder to set the window layout and background (default)
#               0 = skip it (plain window; use this on headless machines)
#
# The layout step talks to Finder with AppleScript. The first run may ask you to let your terminal
# control Finder. If Finder does not answer within 60 s, the script continues without the layout,
# so the image is always valid: Simmer.app plus a link to /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${DIST:-$ROOT/dist}"
APP="${APP:-$DIST/Simmer.app}"
VOLNAME="${VOLNAME:-Simmer}"
DMG_LAYOUT="${DMG_LAYOUT:-1}"
BG_1X="$ROOT/docs/images/dmg/background.png"
BG_2X="$ROOT/docs/images/dmg/background@2x.png"

# Window geometry (points). Must match the background image (640 x 400).
WIN_W=640; WIN_H=400; ICON=128
APP_X=170; APP_Y=190; LINK_X=470; LINK_Y=190

[[ -d "$APP" ]] || { echo "error: $APP not found (run scripts/build.sh first)" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="${OUT:-$DIST/Simmer-$VERSION.dmg}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/simmer-dmg.XXXXXX")"
MOUNT=""
cleanup() {
    if [[ -n "$MOUNT" && -d "$MOUNT" ]]; then hdiutil detach "$MOUNT" -force -quiet || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> staging Simmer $VERSION"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Simmer.app"
ln -s /Applications "$STAGE/Applications"
if [[ -f "$BG_1X" ]]; then
    mkdir -p "$STAGE/.background"
    if [[ -f "$BG_2X" ]]; then
        # One multi-resolution TIFF so Retina screens get the sharp version.
        tiffutil -cathidpicheck "$BG_1X" "$BG_2X" -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
    else
        cp "$BG_1X" "$STAGE/.background/background.png"
    fi
fi
BG_NAME="$(ls "$STAGE/.background" 2>/dev/null | head -n1 || true)"

echo "==> creating writable image"
RW="$WORK/rw.dmg"
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size "${SIZE_MB}m" "$RW"

if [[ "$DMG_LAYOUT" == "1" ]]; then
    echo "==> setting the Finder window layout"
    MOUNT="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen -nobrowse \
        | awk -F '\t' '/\/Volumes\// {print $NF; exit}')"
    DISK_NAME="$(basename "$MOUNT")"
    BG_LINE=""
    [[ -n "$BG_NAME" ]] && BG_LINE="set background picture of opts to file \".background:$BG_NAME\""
    cat > "$WORK/layout.applescript" <<OSA
tell application "Finder"
    tell disk "$DISK_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H))}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to $ICON
        set text size of opts to 13
        $BG_LINE
        set position of item "Simmer.app" of container window to {$APP_X, $APP_Y}
        set position of item "Applications" of container window to {$LINK_X, $LINK_Y}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA
    osascript "$WORK/layout.applescript" >/dev/null 2>&1 &
    OSA_PID=$!
    for _ in $(seq 1 60); do
        kill -0 "$OSA_PID" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$OSA_PID" 2>/dev/null; then
        kill "$OSA_PID" 2>/dev/null || true
        echo "warning: Finder did not answer; the image has no custom layout" >&2
    elif ! wait "$OSA_PID"; then
        echo "warning: Finder layout failed (no Automation permission?); the image has no custom layout" >&2
    fi
    # Hide the background folder and make sure Finder has written .DS_Store.
    SetFile -a V "$MOUNT/.background" 2>/dev/null || chflags hidden "$MOUNT/.background" 2>/dev/null || true
    sync
    hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet
    MOUNT=""
fi

echo "==> compressing (UDZO)"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT"
hdiutil verify -quiet "$OUT"

echo "==> done"
echo "    $OUT ($(du -h "$OUT" | cut -f1 | tr -d ' '))"

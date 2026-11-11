#!/bin/bash
# Re-renders the README hero and screenshots from the CURRENT sources, with fixed demo data.
# No screen capture: the real SwiftUI views are drawn offscreen.
#
#   docs/images/render/render.sh            # hero + screenshots
#   docs/images/render/render.sh --dmg      # also the DMG window background
#
# Output: docs/images/hero.png, docs/images/screenshots/*.png (and docs/images/dmg/*.png)
# Raw 2x renders stay in .build/shots/out for inspection.
#
# How it works: the app and widget sources are copied into a throwaway SwiftPM package in
# .build/shots. The copy of AppModel/InsightsModel is patched so the harness can set their state and
# so live reloads do not replace the demo data. `.toggleStyle(.switch)` is swapped for a look-alike,
# because a real switch draws gray in an app that is not frontmost.
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$H/../../.." && pwd)"
P="$REPO/.build/shots"
OUT="$P/out"
IMAGES="$REPO/docs/images"

# 1. Fresh copies of the sources.
rm -rf "$P/Sources"
mkdir -p "$OUT" "$P/Sources/AppShots/App" "$P/Sources/AppShots/Intents" "$P/Sources/WidgetShots/Widget" "$P/Sources/WidgetShots/Intents"
cp "$H/harness/Package.swift.template" "$P/Package.swift"
ln -s "$REPO/Sources/SimmerShared" "$P/Sources/SimmerShared"
rsync -a --exclude SimmerApp.swift --exclude Updater.swift "$REPO/Sources/SimmerApp/" "$P/Sources/AppShots/App/"
rsync -a --exclude SimmerWidget.swift "$REPO/Sources/SimmerWidget/" "$P/Sources/WidgetShots/Widget/"
if [ -d "$REPO/Sources/SimmerIntents" ]; then
    rsync -a "$REPO/Sources/SimmerIntents/" "$P/Sources/AppShots/Intents/"
    rsync -a "$REPO/Sources/SimmerIntents/" "$P/Sources/WidgetShots/Intents/"
fi
cp "$H/harness/AppMain.swift" "$P/Sources/AppShots/main.swift"
cp "$H/harness/Mocks.swift" "$P/Sources/AppShots/Mocks.swift"
cp "$H/harness/WidgetMain.swift" "$P/Sources/WidgetShots/main.swift"
cp "$H/harness/Mocks.swift" "$P/Sources/WidgetShots/Mocks.swift"
MODELS=("$P/Sources/AppShots/App/AppModel.swift" "$P/Sources/AppShots/App/Insights/InsightsModel.swift")
perl -pi -e 's/\bprivate\(set\) var\b/var/g; s/^(\s*)private init\(\)/$1init()/' "${MODELS[@]}"
perl -pi -e 's/^(\s*func (?:start|refresh|loadVersion|reload\w*|scan\w*)\(\) \{)\s*$/$1 if HarnessFlags.frozen { return }\n/' "${MODELS[@]}"
find "$P/Sources/AppShots/App" -name '*.swift' -exec perl -pi -e 's/\.toggleStyle\(\.switch\)/.toggleStyle(HarnessSwitch())/g' {} +

# 2. Build and render the raw 2x images.
cd "$P"
swift build 2>&1 | grep -E "error:" && { echo "harness build failed (a view's API changed? update harness/*.swift)" >&2; exit 1; }
BIN="$(swift build --show-bin-path)"
"$BIN/AppShots" "$OUT"
"$BIN/WidgetShots" "$OUT"

# 3. Compose the hero and the screenshots, then shrink them (hero stays lossless if < 1.49 MB).
swift "$H/compose.swift" "$OUT" "$IMAGES" "$REPO/Resources/AppIcon.icns"
python3 "$H/optimize.py" "$IMAGES/hero.png" "$IMAGES/screenshots"

if [[ "${1:-}" == "--dmg" ]]; then
    swift "$H/dmg-background.swift" "$IMAGES/dmg"
fi
echo "done: $IMAGES"

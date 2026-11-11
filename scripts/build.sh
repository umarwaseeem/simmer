#!/usr/bin/env bash
# Builds Simmer and assembles an ad-hoc signed dist/Simmer.app plus dist/simmerctl.
#   - SwiftPM builds the root daemon (simmerd) and the CLI (simmerctl).
#   - XcodeGen + xcodebuild build the app and the widget (needed for App Intents and WidgetKit).
# Universal (arm64 + x86_64) by default; set ARCHS="arm64" for a faster local build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
ARCHS="${ARCHS:-arm64 x86_64}"
DIST="${DIST:-$ROOT/dist}"                       # override to build into another folder
DERIVED="${DERIVED_DATA:-$ROOT/.build/xcode}"     # override when several builds run at once
APP="$DIST/Simmer.app"

command -v xcodegen >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)" >&2; exit 1; }

ARCH_FLAGS=()
for a in $ARCHS; do ARCH_FLAGS+=(--arch "$a"); done

echo "==> swift build (simmerd, simmerctl) for: $ARCHS"
swift build -c release "${ARCH_FLAGS[@]}" --product simmerd
swift build -c release "${ARCH_FLAGS[@]}" --product simmerctl
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "==> xcodegen + xcodebuild (Simmer.app, SimmerWidget.appex)"
xcodegen generate --quiet
xcodebuild -project Simmer.xcodeproj -scheme Simmer -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES build -quiet

echo "==> assembling $APP"
rm -rf "$APP" "$DIST/simmerctl"
mkdir -p "$DIST"
ditto "$DERIVED/Build/Products/Release/Simmer.app" "$APP"

RES="$APP/Contents/Resources"
cp "$BIN/simmerd" "$RES/simmerd"
cp "$BIN/simmerctl" "$RES/simmerctl"
cp "$ROOT/scripts/install-helper.sh" "$RES/install-helper.sh"
cp "$ROOT/scripts/uninstall-helper.sh" "$RES/uninstall-helper.sh"
cp "$ROOT/Resources/com.umarwaseem.simmer.helper.plist" "$RES/com.umarwaseem.simmer.helper.plist"
cp "$ROOT/LICENSE" "$RES/LICENSE.txt"
cp "$ROOT/THIRD-PARTY-NOTICES.md" "$RES/THIRD-PARTY-NOTICES.md"
chmod 755 "$RES/simmerd" "$RES/simmerctl" "$RES/install-helper.sh" "$RES/uninstall-helper.sh"
chmod 644 "$RES/com.umarwaseem.simmer.helper.plist"
plutil -lint "$APP/Contents/Info.plist" "$RES/com.umarwaseem.simmer.helper.plist" >/dev/null

echo "==> signing (ad-hoc)"
# Inner binaries first, then the bundle (its seal covers Resources). The widget keeps the
# signature and entitlements xcodebuild gave it.
codesign --force -s - --timestamp=none --identifier com.umarwaseem.simmer.helper "$RES/simmerd"
codesign --force -s - --timestamp=none --identifier com.umarwaseem.simmer.ctl "$RES/simmerctl"
codesign --force -s - --timestamp=none --identifier com.umarwaseem.simmer "$APP"

cp "$BIN/simmerctl" "$DIST/simmerctl"
codesign --force -s - --timestamp=none --identifier com.umarwaseem.simmer.ctl "$DIST/simmerctl"

codesign --verify --strict --deep --verbose=1 "$APP"
codesign --verify --strict "$DIST/simmerctl"

echo "==> done"
echo "    $APP"
echo "    $DIST/simmerctl"

# Building Simmer

## Requirements

- macOS 14 or later (macOS 26 recommended for development)
- Xcode 26 or later (the macOS 26 SDK), command line tools selected with `xcode-select`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Optional: Node.js 20+ for the Raycast extension

## Quick start

```sh
make test     # swift test
make fast     # dist/Simmer.app for this Mac's architecture
make app      # universal (arm64 + x86_64) dist/Simmer.app, as released
make dmg      # dist/Simmer-<version>.dmg
make help     # all targets
```

## What `scripts/build.sh` does

1. `swift build -c release` for `simmerd` and `simmerctl` (universal by default).
2. `xcodegen generate`, then `xcodebuild` for `Simmer.app` and `SimmerWidget.appex`. Swift Package
   Manager fetches Sparkle on the first build.
3. Copies the daemon, the CLI, the install scripts and the LaunchDaemon plist into
   `Simmer.app/Contents/Resources`.
4. Signs everything ad hoc (`codesign -s -`) with fixed identifiers. The helper checks these
   identifiers, so do not change them.

Environment variables:

| Variable | Default | Use |
|---|---|---|
| `ARCHS` | `arm64 x86_64` | Set `ARCHS=arm64` for a faster local build |
| `DIST` | `dist` | Output folder |
| `DERIVED_DATA` | `.build/xcode` | Xcode DerivedData; use another folder when two builds run at once |

## Run your build

```sh
open dist/Simmer.app
```

The app installs the helper from its own bundle on first launch. To replace an installed helper with
your build from Terminal:

```sh
make install-helper     # sudo dist/Simmer.app/Contents/Resources/install-helper.sh dist/Simmer.app
```

Useful helper commands (root):

```sh
sudo dist/Simmer.app/Contents/Resources/simmerd --status    # one read-only tick, print JSON
sudo dist/Simmer.app/Contents/Resources/simmerd --reset     # charging on, adapter on, LED system
log stream --predicate 'subsystem == "com.umarwaseem.simmer"'
```

## Work in Xcode

```sh
make project && open Simmer.xcodeproj
```

The `Simmer` scheme builds the app and the widget. For the daemon and the CLI, open `Package.swift`
in Xcode or use `swift build`.

## Tests

```sh
swift test
```

The tests use a fake SMC, so they never touch your hardware and need no root.

## Raycast extension

```sh
cd raycast && npm install && npm run dev
```

## Screenshots and the hero image

The README images are rendered from the real SwiftUI views with fixed demo data (no screen
capture, no personal data). After a UI change, refresh them with:

```sh
docs/images/render/render.sh          # hero + screenshots
docs/images/render/render.sh --dmg    # also the DMG background
```

The script copies the current sources into a throwaway package in `.build/shots`, renders 2x PNGs
offscreen, composes `docs/images/hero.png` and `docs/images/screenshots/*`, and shrinks them with
Pillow (`pip install pillow`). If a view's initializer changed, update `docs/images/render/harness/`.

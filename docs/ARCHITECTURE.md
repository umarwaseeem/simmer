# Architecture

Simmer is four programs that share one library.

```
┌──────────────────────────── user session (you) ────────────────────────────┐
│                                                                            │
│  Simmer.app (SwiftUI, menu bar)        SimmerWidget.appex (WidgetKit)      │
│   ├─ PanelView, Settings, Insights      ├─ reads status.json/history.json  │
│   ├─ App Intents (Shortcuts)            └─ interactive buttons (intents)   │
│   ├─ simmer:// URL scheme                                                  │
│   └─ Sparkle updater                   simmerctl (CLI)                     │
│                 │                               │                          │
└─────────────────┼───────────────────────────────┼──────────────────────────┘
                  │  XPC: com.umarwaseem.simmer.helper (code signing check)  │
┌─────────────────▼───────────────────────────────▼──────────────────────────┐
│ simmerd  (root LaunchDaemon, /Library/PrivilegedHelperTools/…)             │
│   Engine (5 s tick) ─▶ ChargePolicy ─▶ ChargeControl ─▶ SMC (IOKit)        │
│   Scheduler · SleepManager · PowerModes · energy sampler · history         │
│   writes /Library/Application Support/Simmer/{status,history,energy}.json  │
└────────────────────────────────────────────────────────────────────────────┘
```

## Targets

| Target | Built by | Path | What it is |
|---|---|---|---|
| `SimmerShared` | SwiftPM | `Sources/SimmerShared` | Models, XPC protocol and client, SMC access, charge control, the pure charging policy, history, insights parsers, conflict scanner. No UI. |
| `simmerd` | SwiftPM | `Sources/simmerd` | The root daemon. The only code that writes SMC keys, runs `pmset`, or writes to `/Library/Application Support/Simmer`. |
| `simmerctl` | SwiftPM | `Sources/simmerctl` | Command-line client. `simmerctl help` lists the commands. |
| `SimmerTests` | SwiftPM | `Tests/SimmerTests` | Unit tests: policy, SMC encoding (with a fake SMC), scheduler, parsers. |
| `Simmer` | XcodeGen + xcodebuild | `Sources/SimmerApp`, `Sources/SimmerIntents` | The menu bar app. |
| `SimmerWidget` | XcodeGen + xcodebuild | `Sources/SimmerWidget`, `Sources/SimmerIntents` | The widget extension. |

Why two build systems? SwiftPM is fast and simple for the library, the daemon, the CLI and the tests.
App Intents and WidgetKit extensions need an Xcode project, which XcodeGen generates from
`project.yml` (the `.xcodeproj` is not committed).

## Main ideas

- **One writer.** Only `simmerd` touches the hardware. Everything else sends commands over XPC. A
  bug in the UI can show wrong numbers, but it cannot leave the SMC in a bad state.
- **Pure policy.** `ChargePolicy.decide(...)` takes plain inputs (battery, config, runtime state,
  time) and returns a decision. The engine applies it. Tests cover the policy without hardware.
- **Read back, then write.** The engine remembers what it wrote and reads the keys back on every
  tick, because macOS 26 resets some of them (see [HOW-IT-WORKS.md](HOW-IT-WORKS.md)).
- **Fail safe.** On any error, quit, uninstall or crash recovery, the hardware returns to "charging
  allowed, adapter on, LED system", unless the user chose to keep the limit.
- **Files for readers, XPC for writers.** The app and the widget read `status.json` and
  `history.json` directly. The widget is sandboxed and cannot use XPC to a root daemon.
- **Tolerant decoding.** All shared models decode with defaults, so an older app works with a newer
  helper and the other way round.

## Versions

`Simmer.helperVersion` (in `Sources/SimmerShared/Models.swift`) equals the app's
`MARKETING_VERSION` (in `project.yml`). `scripts/release.sh` sets both. The helper reports its
version in every status; when it differs from the app's, the app offers to reinstall the helper.

## Install layout

| Path | Owner | Created by |
|---|---|---|
| `/Applications/Simmer.app` | you | you (drag from the DMG) or Homebrew |
| `/Library/PrivilegedHelperTools/com.umarwaseem.simmer.helper` | root | `install-helper.sh` |
| `/Library/LaunchDaemons/com.umarwaseem.simmer.helper.plist` | root | `install-helper.sh` |
| `/usr/local/bin/simmerctl` | root | `install-helper.sh` |
| `/Library/Application Support/Simmer/` | root | `simmerd` |
| `/Library/Logs/simmerd.log` | root | launchd (stderr of `simmerd`) |
| `~/Library/Application Support/Simmer/Backups` | you | Simmer.app (weekly settings backups) |

The app runs `Contents/Resources/install-helper.sh` with administrator rights (one password prompt)
to copy the helper, the LaunchDaemon plist and `simmerctl` out of the app bundle.

## Repository map

```
Sources/            app, widget, intents, shared library, daemon, CLI
Tests/              unit tests
Resources/          Info.plists, entitlements, LaunchDaemon plist, app icon
scripts/            build.sh, make-dmg.sh, release.sh, install/uninstall-helper.sh, make-icon.swift
docs/               these documents and the README images
raycast/            Raycast extension (TypeScript, MIT)
Casks/simmer.rb     Homebrew cask (tap this repo directly)
appcast.xml         Sparkle update feed
.github/            CI, release workflow, issue and PR templates
```

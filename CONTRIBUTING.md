# Contributing to Simmer

Thank you for helping. Simmer is a small project, so every report, test and pull request counts.

## Ways to help

- **Report a bug.** Use the [bug report form](https://github.com/umarwaseeem/simmer/issues/new?template=bug_report.yml).
  Include the output of `simmerctl status --json`, your Mac model and your macOS version.
- **Test on an Intel Mac.** Intel support is written but has not run on real hardware. Follow
  [docs/INTEL-TESTING.md](docs/INTEL-TESTING.md) and send an
  [Intel test report](https://github.com/umarwaseeem/simmer/issues/new?template=intel_test_report.yml).
- **Suggest a feature.** Describe the problem first, then the idea.
- **Improve the docs or the help texts.** Short and clear beats long and complete.
- **Send code.** See below.

## Before you write code

Open an issue first for anything bigger than a small fix, so we can agree on the approach. Look for
issues labeled `good first issue` if you want a start.

## Set up

```sh
brew install xcodegen
git clone https://github.com/umarwaseeem/simmer.git && cd simmer
make test     # unit tests (SwiftPM)
make fast     # dist/Simmer.app for your Mac's architecture
```

You need Xcode 26 or later. [docs/BUILDING.md](docs/BUILDING.md) explains the build in detail, and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains where code lives.

To try your build with the real helper, install it from your build (this replaces an installed
helper):

```sh
make install-helper   # asks for your password
```

Quit any other charge limiter first. Two limiters write the same SMC keys and fight each other.

## Rules for code

- **Only `simmerd` writes SMC keys.** The app, the widget and `simmerctl` talk to it over XPC.
- **Keep the policy pure.** Charging decisions live in `ChargePolicy` (SimmerShared) and take plain
  inputs, so they are easy to test. Add a test for every behavior change.
- **Fail safe.** If something goes wrong, the hardware must end up in "charging allowed, adapter
  on". Never leave the adapter disabled.
- **Respect the user's Mac.** No network access except Sparkle's update check. No telemetry.
- **Match the existing style.** 4 spaces, Swift API naming, small files. `.editorconfig` has the
  basics.
- **User-facing text** is short, active and plain. Every new setting gets a help text (`Help.swift`).

## Pull requests

1. Branch from `main`.
2. Keep the change focused. One topic per pull request.
3. Run `make test` and build the app (`make fast`).
4. Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for user-visible changes.
5. Fill in the pull request template, including the hardware you tested on.

CI runs `swift test` and a full universal build on every pull request.

## License of contributions

Simmer is GPL-3.0. By sending a pull request you agree that your contribution is licensed under
the same license. The Raycast extension in `raycast/` is MIT.

## Code of Conduct

Everyone who takes part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

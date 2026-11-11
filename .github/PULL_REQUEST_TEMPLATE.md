## What does this change?

<!-- One or two sentences. Link the issue: "Fixes #123". -->

## How did you test it?

<!-- For example: `swift test`, built with `make fast`, ran on MacBook Air M2 / macOS 26.4, limit 60% overnight. -->

- [ ] `swift test` passes
- [ ] The app builds (`make fast` or `scripts/build.sh`)
- [ ] I tested on real hardware (model + macOS: )

## Checklist

- [ ] Only `simmerd` writes SMC keys; the app and the CLI go through XPC.
- [ ] New user-visible text is short and clear, and new settings have help text.
- [ ] I added an entry under `## [Unreleased]` in `CHANGELOG.md` (user-visible changes only).
- [ ] Docs updated if behavior changed (`README.md`, `docs/`).

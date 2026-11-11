# Releasing Simmer

A release is a Git tag `vX.Y.Z`. The release workflow builds the universal app, makes the DMG and the
Sparkle ZIP, signs the ZIP, publishes the GitHub release, and commits the new `appcast.xml` entry and
the updated cask back to `main`.

## Pieces

| Piece | Where | Notes |
|---|---|---|
| Version | `project.yml` → `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` | `CURRENT_PROJECT_VERSION` is the build number Sparkle compares. It must grow with every release. |
| Helper version | `Sources/SimmerShared/Models.swift` → `Simmer.helperVersion` | Must equal `MARKETING_VERSION`. When the installed helper reports another version, the app offers to reinstall it. |
| Release notes | `CHANGELOG.md`, section `## [X.Y.Z]` | Copied into the GitHub release and the Sparkle update window. |
| Update feed | `appcast.xml` on `main` | Read by the app from `SUFeedURL`. |
| Feed URL | `Resources/Info.plist` → `SUFeedURL` | `https://raw.githubusercontent.com/umarwaseeem/simmer/main/appcast.xml` |
| Public key | `Resources/Info.plist` → `SUPublicEDKey` | `XO0I3/0CGVUHmemq+HL/tJbstfVEUTrl33ePkdYzMlc=` |
| Private key | Maintainer's login keychain (account `simmer`) and the `SPARKLE_PRIVATE_KEY` secret | Never commit it. |
| Cask | `Casks/simmer.rb` (tapped directly from this repo) | `release.sh` fills in `version` and `sha256`. |

**Why raw.githubusercontent.com for the feed?** It needs no extra setup (no GitHub Pages branch), it
serves exactly what is on `main`, and the release workflow already commits there. GitHub caches raw
files for about 5 minutes, which is fine for an update feed. To move to GitHub Pages later, change
`SUFeedURL` in a release first and keep the old URL working until most users have updated.

## Secrets

| Secret | Value |
|---|---|
| `SPARKLE_PRIVATE_KEY` | The text of the exported EdDSA private key (one line of base64). |

The workflow uses the built-in `GITHUB_TOKEN` (with `contents: write`) for the release and the
commit to `main`. If `main` is protected, allow `github-actions[bot]` to push, or change the last
workflow step to open a pull request.

Export the key on the maintainer's Mac and add it as a secret:

```sh
# Sparkle's tools are in the SwiftPM artifacts after a build, or in the Sparkle release archive:
SPARKLE_BIN=.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin
"$SPARKLE_BIN/generate_keys" --account simmer -p                 # prints the public key: must match SUPublicEDKey
"$SPARKLE_BIN/generate_keys" --account simmer -x sparkle_private_key
gh secret set SPARKLE_PRIVATE_KEY --repo umarwaseeem/simmer < sparkle_private_key
rm -P sparkle_private_key
```

**Keep a backup of the private key** (for example in a password manager). If it is lost, existing
installs cannot verify new updates, and every user must download the next version by hand. If it
leaks, an attacker who also controls the feed could ship an update; rotate the key in a release
that is still signed with the old key.

## First release (one time)

1. Create the GitHub repository `umarwaseeem/simmer` (public), push `main`.
2. Set the repository description, topics and social preview (see below).
3. Add the `SPARKLE_PRIVATE_KEY` secret.
4. Follow "Every release" below for `1.0.0`.
5. The cask is served from this repository (`Casks/simmer.rb`, updated by the release workflow). Test:
   `brew tap umarwaseeem/simmer https://github.com/umarwaseeem/simmer && brew install --cask simmer`.

Suggested repository metadata:

- **Description:** Free, open-source battery charge limiter and battery insights for macOS. Keep your
  MacBook below the boil.
- **Topics:** `macos`, `battery`, `charge-limiter`, `menu-bar-app`, `swiftui`, `apple-silicon`,
  `battery-health`, `smc`, `widgets`, `shortcuts`, `open-source`
- **Social preview:** `docs/images/hero.png` (2400 × 1200)

## Every release

1. Move the `## [Unreleased]` items in `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD` and update the
   links at the bottom.
2. Bump the versions:

   ```sh
   scripts/release.sh X.Y.Z --bump-only
   ```

   This sets `MARKETING_VERSION`, increases `CURRENT_PROJECT_VERSION` by one, and sets
   `Simmer.helperVersion`.
3. Commit, tag and push:

   ```sh
   git commit -am "Release X.Y.Z"
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```

4. Watch the **Release** workflow. It runs `scripts/release.sh X.Y.Z --no-bump`, publishes the
   release with `Simmer-X.Y.Z.dmg` and `Simmer-X.Y.Z.zip`, and pushes the appcast and cask update to
   `main`.
5. Copy the updated `Casks/simmer.rb` from `main` to the tap and push it.
6. Check: download the DMG, open it on a clean account, and run **Check for Updates…** in the
   previous version.

A version with a suffix (`1.2.0-beta.1`) becomes a GitHub pre-release, and its appcast entry gets
`<sparkle:channel>beta</sparkle:channel>`, so only apps that opt in to the beta channel see it.

## Release from your Mac instead

`scripts/release.sh X.Y.Z` does everything locally: bump, build, DMG, ZIP, sign (with the keychain
key, account `simmer`), appcast, cask. It prints the `gh release create` command to publish. Useful
when CI is down. Options:

| Option | Effect |
|---|---|
| `--bump-only` | Only change the versions |
| `--no-bump` | Expect the versions to be set already (CI) |
| `--skip-build` | Reuse `dist/Simmer.app` |

Environment: `SPARKLE_PRIVATE_KEY` (key text) or `SPARKLE_KEY_FILE` (path) instead of the keychain;
`SPARKLE_BIN` for the Sparkle tools; `DIST` for the output folder; `DMG_LAYOUT=0` to skip the Finder
window layout on a headless machine.

## How the DMG is made

`scripts/make-dmg.sh` stages `Simmer.app` and a link to `/Applications`, creates a writable HFS+
image, asks Finder (AppleScript) to set the icon positions and the background from
`docs/images/dmg/`, then converts the image to compressed UDZO. If Finder does not answer within
60 seconds (no GUI session, no Automation permission), the image is still valid, only without the
custom layout.

## Signing

Builds are ad-hoc signed. There is no notarization. Users open the app the first time with
right-click → Open, and the README says so. With an Apple Developer ID later:

1. Sign with `codesign --options runtime --timestamp -s "Developer ID Application: …"`.
2. Notarize the DMG with `xcrun notarytool submit --wait` and staple it.
3. Add the Team ID to the helper's client requirement in `Sources/simmerd/XPCService.swift`.

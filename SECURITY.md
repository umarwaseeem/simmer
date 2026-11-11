# Security policy

Simmer installs a helper that runs as root, so security reports get priority.

## Report a vulnerability

Please **do not open a public issue**. Report privately through
[GitHub security advisories](https://github.com/umarwaseeem/simmer/security/advisories/new).
Include the Simmer version, your macOS version and the steps to reproduce.

You get an answer within 7 days. A fix for a confirmed problem ships as soon as it is ready, and you
are credited in the release notes unless you ask not to be.

## Supported versions

Only the latest release gets security fixes. Sparkle installs updates automatically, unless you
turned that off.

## Security model

Simmer has three parts. Only one of them has privileges.

| Part | Runs as | Can do |
|---|---|---|
| `Simmer.app` (and its widget) | You | Show data, send commands to the helper |
| `simmerctl` | You | Send commands to the helper |
| `simmerd` (`/Library/PrivilegedHelperTools/com.umarwaseem.simmer.helper`) | root, LaunchDaemon | Write SMC charging keys, LED, power modes, sleep settings |

**The helper accepts only Simmer clients.** It listens on the XPC Mach service
`com.umarwaseem.simmer.helper`, and every connection must satisfy this code signing requirement:

```
identifier "com.umarwaseem.simmer" or identifier "com.umarwaseem.simmer.ctl"
```

XPC checks the requirement for every message, before the helper sees it. (`simmerd` has an
`--insecure-xpc` flag that skips the check for debugging. The installed LaunchDaemon never uses it,
and only root can change the LaunchDaemon.)

**The helper offers a fixed set of commands.** Get status, get or set the configuration, and named
actions such as set limit, top up, discharge, calibrate, LED mode, power mode, sleep, run a
scheduled task, and remove a *known* helper of another charge limiter (matched on exact, built-in
paths). Values are range-checked. The helper never runs a shell command or opens a path that a client
sends.

**Files.** Settings and state live in `/Library/Application Support/Simmer/` (owned by root). The
helper writes `status.json` and `history.json` there as world-readable files, so the app and the
widget can show data without an XPC call. They contain battery data only.

## Known limits

- **Ad-hoc signing.** Releases are signed ad hoc, not with an Apple Developer ID, because the
  project has no paid Apple account. An ad-hoc signature has no Team ID, so the identifier check
  above cannot prove that a client was built by this project. A program that already runs as your
  user could sign itself with Simmer's identifier and then do what Simmer can do: change the charge
  limit, the LED, the power modes or put the Mac to sleep. It cannot run code as root through the
  helper. With a Developer ID, the requirement would also pin the Team ID; that is planned if the
  project gets one.
- **Gatekeeper.** Because the app is not notarized, you open it once with right-click → Open. Check
  that you downloaded it from this repository's Releases page.
- **Updates are signed.** Every update archive carries an EdDSA (ed25519) signature. Sparkle refuses
  an update whose signature does not match the public key built into the app (`SUPublicEDKey`), so a
  changed download or a changed appcast cannot install code.

## Release signing key

The Sparkle private key never enters the repository. It lives in the maintainer's keychain and in
the `SPARKLE_PRIVATE_KEY` secret of the release workflow. See [docs/RELEASING.md](docs/RELEASING.md).

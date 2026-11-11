# Privacy

**Short version: Simmer collects nothing.** No telemetry, no analytics, no crash reporter, no
account, no ads.

## Network

Simmer makes exactly one kind of network request: the **update check** (Sparkle).

- What: an HTTPS GET of `https://raw.githubusercontent.com/umarwaseeem/simmer/main/appcast.xml`, and
  the update download from GitHub Releases when you accept an update.
- When: once a day while automatic checks are on, and when you click **Check for Updates…**.
- What it sends: the normal HTTP headers, including a `User-Agent` with the app name and version.
  Simmer turns off Sparkle's optional system profile, so no hardware or OS details are added. GitHub
  sees your IP address, as with any download from GitHub.
- How to turn it off: **Settings → Helper & Updates**, switch off automatic update checks. Simmer then
  makes no network requests at all.

The helper (`simmerd`), `simmerctl`, the widget and the Raycast extension make **no** network
requests.

## Data on your Mac

Everything Simmer records stays on your Mac:

| Data | Where | Why |
|---|---|---|
| Settings, schedule | `/Library/Application Support/Simmer/config.json` | So the helper applies them, also when the app is closed |
| Battery history (charge, temperature, power, daily health) | `/Library/Application Support/Simmer/history.json` | Charts and the battery passport |
| Latest status, energy use per app | `status.json`, `energy.json` in the same folder | The app and the widget read them |
| Settings backups | `~/Library/Application Support/Simmer/Backups` (last 8) | Restore after a reset |
| Logs | Unified log (`com.umarwaseem.simmer`), `/Library/Logs/simmerd.log` | Troubleshooting |

The battery passport PDF and settings exports are created only when you ask, and saved where you
choose. They include your battery's serial number, so check before you share them.

Uninstalling with **Uninstall and Delete Settings** (or `uninstall-helper.sh --purge`) removes the
folder in `/Library/Application Support/Simmer` and the log file.

## Permissions

| Permission | Why |
|---|---|
| Administrator password (once, and for helper updates) | To install the root helper that writes SMC keys |
| Notifications (optional) | Limit reached, heat protection, calibration steps |

Simmer does not ask for Accessibility, Full Disk Access, Screen Recording, location, contacts or
any other personal data.

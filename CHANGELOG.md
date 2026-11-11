# Changelog

All notable changes to Simmer are listed here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Simmer uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`scripts/release.sh <version>` copies the section for that version into the GitHub release and the
Sparkle update window, so write entries for people, not for the commit log.

## [Unreleased]

## [1.0.0] - Unreleased

The first public release.

### Charging
- Charge limit from 20% to 100%, written straight to the SMC by a small root helper.
- Sailing mode: let the charge drift a few percent below the limit before charging again.
- Heat protection: pause charging when the battery is hot.
- Discharge while plugged in, also with the lid closed (Simmer keeps the Mac awake).
- Automatic discharge when the charge is above the limit.
- Top up to 100% once, then go back to the limit.
- Calibration: a guided full cycle to recalibrate the battery gauge.
- Stop charging while the Mac sleeps, or block sleep until the limit is reached.
- Keep the limit active when Simmer quits.
- Desk mode, smart "ready by" top-up, and cheap or green charging windows.
- Schedule with templates and catch-up for missed events.

### Display and control
- Menu bar panel with live power flow, hardware percentage and time estimates.
- MagSafe LED modes, custom colors per state and LED notifications.
- Low Power and High Power mode switching.
- Desktop widgets (several kinds, configurable, interactive).
- Shortcuts actions (App Intents), the `simmer://` URL scheme and the `simmerctl` command-line tool.
- Raycast extension.
- Notifications for limit reached, heat, calibration and more.

### Insights
- Battery history charts.
- Top energy apps and processes, sleep drain detective and "why won't my Mac sleep".
- Battery sessions, component power, USB power, charger report.
- Battery stress meter and cell balance.
- Battery passport PDF export.

### Safety and housekeeping
- Conflict doctor: finds the native macOS Charge Limit and leftover helpers of other tools.
- Settings backup and restore.
- Automatic updates with Sparkle (EdDSA-signed).
- Intel Mac support (beta, untested: please report).

[Unreleased]: https://github.com/umarwaseeem/simmer/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/umarwaseeem/simmer/releases/tag/v1.0.0

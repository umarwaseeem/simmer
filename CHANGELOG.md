# Changelog

All notable changes to Simmer are listed here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Simmer uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`scripts/release.sh <version>` copies the section for that version into the GitHub release and the
Sparkle update window, so write entries for people, not for the commit log.

## [Unreleased]

## [1.1.0] - 2026-11-11

### New
- **Stove knob and glowing battery** in the menu bar panel. Turn the knob to set the limit (drag, scroll,
  arrow keys or VoiceOver); the jar shows the live charge, steams while charging and glows green at the
  limit. Prefer the classic slider? Settings → Menu Bar Panel → Look.
- **Time to limit:** "80% in 25 min" while charging or discharging toward the limit (also in `simmerctl status`).
- **Ready for macOS 27:** if macOS blocks direct charge control, Simmer switches to the macOS Charge Limit
  automatically (80–100% in steps). Settings → Charging → Charge control, or `simmerctl set charge-control`.
- **Power flow in the panel by default**, with one plain sentence about what is happening right now.
- **Close power-hungry apps and processes** from Settings → Energy (Quit, End, and Force options).
- **Refresh buttons (⌘R)** on all insight pages, with "updated … ago".

### Changed
- The menu bar panel uses Simmer's warm plum and ember colours.
- New Simmer jar icon in the menu bar (the battery symbol is still an option).

## [1.0.0] - 2026-11-11

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

# How Simmer works

This page explains how Simmer stops and starts charging, which SMC keys it uses on which Macs, and
what we measured on macOS 26. It is for curious users and for contributors.

## The short version

A MacBook's **System Management Controller (SMC)** decides whether the charger charges the battery.
macOS exposes a few SMC keys that switch charging off, or switch the adapter off so that the Mac runs
from the battery. Only root can write them.

Simmer's helper, `simmerd`, runs as root. Every **5 seconds** (and right away on plug, unplug, wake and
every command) it:

1. reads the battery from IOKit (`AppleSmartBattery`) and a few SMC sensors,
2. asks the charging policy what the hardware should do now,
3. writes the SMC keys only if they differ from what it wrote last time, and reads them back to catch
   anything that changed them.

```
            ┌────────────────────┐   XPC (Mach service)   ┌─────────────────────────────────┐
 you ──────▶│ Simmer.app         │ ─────────────────────▶ │ simmerd (root LaunchDaemon)      │
            │ simmerctl, widget  │ ◀── status.json ─────── │  battery ─▶ policy ─▶ SMC writes │
            └────────────────────┘                         └─────────────────────────────────┘
```

## The charging policy

The policy (`ChargePolicy` in `Sources/SimmerShared`) is a pure function: plain inputs in, one
decision out. That makes it easy to test. In order of priority:

1. **Calibration** overrides everything: charge to 100%, hold, discharge low, charge to 100%, hold,
   then go back to the limit.
2. **Discharge** (manual or automatic): switch the adapter off until the battery reaches the limit.
3. **Top up**: allow charging to 100% once.
4. **Heat protection**: stop charging above the threshold, start again a little below it
   (hysteresis, so it does not flicker).
5. **Limit with sailing**: stop charging at the limit. With sailing on, charging starts again only
   after the battery drifts *sailing level* percent below the limit. This avoids many tiny top-ups.

The **effective limit** can be lower or higher than your slider for a while: desk mode lowers it when
the Mac stays plugged in for days, the smart "ready by" top-up raises it just before you usually leave,
and cheap or green windows decide *when* charging happens. The panel always shows why
(`limitReason`).

## SMC keys by Mac family

Simmer picks a backend by checking which keys exist, in this order:

| Backend | Macs | Stop charging | Run from battery while plugged in | Notes |
|---|---|---|---|---|
| `chte` | Apple silicon with macOS 15+ firmware (verified: M5 Pro, macOS 26.4) | `CHTE` (ui32, little endian): `01 00 00 00` = stop, `00 00 00 00` = allow | `CHIE` (1 byte): `0x08` = adapter off, `0x00` = on | The only charging keys on the M5 Pro. |
| `ch0b` | Apple silicon with older firmware; Intel Macs of the T2 era | `CH0B` and `CH0C` = `0x02` stop, `0x00` allow | `CH0J` = `0x20`, or `CH0I` = `0x01` | Single-byte keys. |
| `bclm` | Older Intel Macs | — | — | `BCLM` (ui8) = maximum charge level. The SMC enforces it by itself, also while the Mac sleeps or is off. |

**BCLM offset.** On BCLM Macs the level macOS shows tends to settle a few percent above the BCLM value,
because the SMC compares BCLM with the raw gauge level. Simmer writes `limit − 3` by default (configurable
from −10 to 0, `intelBCLMOffset` in the settings) and always writes `100` for "no limit". BCLM Macs have no
sailing, heat pause, discharge, top up or calibration: the hardware only knows a fixed maximum.
Simmer writes BCLM only when the value changes, to spare the SMC flash.

### Other keys

| Key | Type | Use |
|---|---|---|
| `ACLC` | ui8 | MagSafe LED: `00` system, `01` off, `03` green, `04` orange, `05` orange slow blink, `06` orange fast blink |
| `TB0T` | flt | Battery temperature (°C) |
| `PSTR` | flt | System power (W) |
| `PDTR` | flt | Power delivered by the adapter (W) |
| `ACFP` | ui8 | Adapter present (stays 1 while Simmer has the adapter off) |

Intel support follows the public documentation of these keys from open-source tools (bclm, batt, the battery CLI)
and is covered by tests with a fake SMC. It has **not** run on Intel hardware yet. Please help:
[INTEL-TESTING.md](INTEL-TESTING.md).

## What we verified on macOS 26

Measured on a MacBook Pro with M5 Pro (`Mac17,9`), macOS 26.4, 96 W USB-C charger:

1. **Only `CHTE` and `CHIE` exist.** `CH0B`, `CH0C`, `CH0I`, `BCLM` and `CHWA` are absent.
2. **macOS resets `CHIE` once.** About 1 second after the first write of `CHIE = 0x08`, macOS
   writes it back to `0x00` (powerd and the native charge limit). It can also reset `CHTE`. So the
   helper reads both keys back on every tick and writes again when the hardware no longer matches.
3. **With the adapter off, macOS thinks it is unplugged.** While `CHIE = 0x08`, both
   `ExternalConnected` and `AppleRawExternalConnected` read *No*. `AdapterDetails.Watts` keeps the
   charger's value (94) and `ACFP` stays 1. A real unplug clears `AdapterDetails` to
   `{FamilyCode = 0}`. Simmer uses this to tell "adapter switched off by us" from "cable pulled", and
   ignores a flag drop shorter than a short debounce (the 1-second reset above causes one).
4. **Lid close sleeps the Mac while discharging.** With `CHIE = 0x08`, closing the lid triggers
   *Clamshell Sleep* (on battery), which turns external displays off. To discharge with the lid
   closed, Simmer sets `pmset -a disablesleep 1` for that time only. A marker file in
   `/Library/Application Support/Simmer` records it, so a crash or a reboot never leaves sleep
   disabled: the helper undoes it at start, and `uninstall-helper.sh` undoes it too.
5. **The native Charge Limit (macOS 26.4).** System Settings → Battery → Charging → Charge Limit is
   handed by PowerUIAgent to powerd as a `ChargeCtrlPolicy` with reason `manualChargeLimit` and
   `soclimit` = the limit. powerd stores active policies in
   `/Library/Preferences/com.apple.powerd.charging.plist` (world-readable). The Conflict doctor reads
   it. If macOS limits at 80%, Simmer cannot charge above 80% (top up and calibration then stop
   early), so set the native limit to 100% and let Simmer handle it. A native value below 100% was
   decoded from the format, not yet observed on a live system.
6. **The MagSafe LED is `ACLC`.** Writing `00` hands the LED back to macOS.

## Sleep and shutdown

- **Before sleep** the helper gets a synchronous IOKit notification. With *Stop charging when
  sleeping* on, it stops charging before the Mac sleeps, because nothing runs to stop it at the limit
  during sleep.
- **Disable sleep until the limit** holds a `PreventUserIdleSystemSleep` assertion while charging
  toward the limit.
- **After wake** the next tick writes every key again.
- **When the helper stops** (quit with *keep the limit* off, uninstall, shutdown), it leaves the
  hardware safe: charging allowed, adapter on, LED back to macOS. With *keep the limit when quit* on,
  charging stays blocked while the helper is stopped. On BCLM Macs the BCLM value persists by itself.

## Data files

The helper writes world-readable JSON files to `/Library/Application Support/Simmer/` so the app and
the widget can read data without XPC:

| File | Content | Updated |
|---|---|---|
| `status.json` | Latest status | On change, at least every 60 s |
| `history.json` | 5-minute samples and one health record per day | Every 5 minutes |
| `energy.json` | Top apps and processes by estimated power | Every sample window |
| `config.json`, `state.json` | Settings and runtime state (root-owned) | On change |

The helper logs to the unified log (subsystem `com.umarwaseem.simmer`) and to
`/Library/Logs/simmerd.log`.

## Updating the helper

Sparkle updates only `Simmer.app`. The helper is a separate install. Each release sets
`Simmer.helperVersion` to the app version, and the helper reports its own version in the status. When
they differ, the panel shows a banner that reinstalls the helper (one password prompt).

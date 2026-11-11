# Testing Simmer on an Intel Mac

Intel support is **beta and untested**. The code follows the public documentation of the Intel SMC
keys and passes tests with a fake SMC, but nobody has run it on a real Intel Mac yet. If you have one,
about 30 minutes of your time helps a lot.

Send the results with the
[Intel test report form](https://github.com/umarwaseeem/simmer/issues/new?template=intel_test_report.yml).
"It all works" is a useful report too.

## What to expect

| Your Mac | Backend Simmer should pick | What works |
|---|---|---|
| Intel with T2 chip (2018–2020), or keys `CH0B`/`CH0C` present | `ch0b` | Limit, sailing, heat protection, top up, calibration; discharge if `CH0I` or `CH0J` exists; LED on MagSafe models |
| Older Intel (no `CH0B`) with `BCLM` | `bclm` | A fixed maximum level only. The SMC holds it by itself, also when the Mac is off. No sailing, discharge, top up or calibration. |
| Neither | `none` | Monitoring only |

## Before you start

- Quit and remove other charge limiters (bclm, batt, Battery Toolkit, battery and similar apps). The Conflict
  doctor in Simmer lists them.
- Set the macOS battery settings to their defaults (Optimized Battery Charging can stay on).
- Have the charger at hand. Start with the battery between 50% and 90%.

## 1. Read-only checks (no password needed)

```sh
sysctl -n hw.model
sw_vers -productVersion
/Applications/Simmer.app/Contents/Resources/simmerd --status
```

`--status` reads the battery and the SMC once and prints JSON without writing anything. Copy the
whole output into the "SMC key probe" field. Look at `backend` and `capabilities`.

Optional, also read-only: show what Simmer *would* write, once every 5 seconds (Ctrl-C to stop):

```sh
/Applications/Simmer.app/Contents/Resources/simmerd --dry-run
```

## 2. Install and watch

1. Open Simmer, install the helper, and set the limit **5% below** the current charge.
2. Keep the charger connected. Within a minute, the panel should say *Charge Limit Reached* or
   *Not charging*, and `simmerctl status` should show `chargingInhibited: true`.
   - On a `bclm` Mac, macOS may keep charging to a level a few percent above the limit. Note the
     level where it stops. That number helps tune the default offset.
3. Set the limit **10% above** the current charge. Charging should start again.
4. If discharge is supported: `simmerctl discharge on`. The Mac should run from the battery while
   plugged in (`ExternalConnected` may read *No*). Then `simmerctl discharge off`.
5. If your Mac has a MagSafe LED: `simmerctl led smart`, then `simmerctl led system`.
6. Sleep the Mac for a few minutes and wake it. The limit should still apply.

## 3. Restore

Uninstall the helper from **Settings → Helper & Updates → Uninstall Helper…**, or:

```sh
sudo /Applications/Simmer.app/Contents/Resources/uninstall-helper.sh
```

Uninstalling writes the default values back (charging allowed, adapter on, LED system, `BCLM` 100).
Check that the Mac charges normally afterwards.

## What to include

- The `--status` output, the Mac model and the macOS version
- Which steps worked, and what you saw where they did not
- On `bclm` Macs: the limit you set and the level where charging really stopped
- `tail -n 100 /Library/Logs/simmerd.log` if something failed

Thank you.

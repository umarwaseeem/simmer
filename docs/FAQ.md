# FAQ

## General

### Which limit should I use?

For a Mac that is plugged in most of the day, **60–80%** is a good balance. Use **Top Up** before a
day away from a socket. If you are on battery most of the time, a limit gives little benefit: let it
charge to 100% and keep the Mac cool.

### Is a limit really good for the battery?

Lithium-ion cells wear faster at a high state of charge and at high temperature. A battery that sits
at 100% on a warm desk ages faster than one that rests at 60–80%. That is why phones and laptops
now ship with "optimized" or limited charging. A limit does not stop aging; it slows it.

### What is sailing?

Without sailing, the Mac tops up every time the charge drops a little below the limit: many tiny
charge cycles. With sailing, the battery may drift a few percent below the limit (you choose how
many) before charging starts again. The charger still powers the Mac the whole time.

### Why does the battery sometimes go *down* while plugged in?

That is either **discharge** (you or automatic discharge asked for it: the battery runs the Mac
until it reaches the limit) or a heavy load that needs more power than your charger delivers. The
panel's power flow shows which. The charger report tells you if your charger is too weak.

### Does Simmer work when the app is closed?

Yes. The helper applies the limit by itself. With **Keep the limit when Simmer quits** off, quitting
the app hands charging back to macOS.

### What happens when the Mac sleeps or is shut down?

During sleep, nothing runs to stop charging at the exact limit, so Simmer can **stop charging before
sleep** (Settings → Sleep). When the Mac is shut down, Apple silicon Macs can charge past the limit
until macOS and the helper start again. Intel Macs that use the `BCLM` key keep the limit even when
off.

### What is the hardware percentage?

macOS shows a smoothed percentage that keeps a small reserve. The hardware percentage is the raw
gauge reading (`AppleRawCurrentCapacity / AppleRawMaxCapacity`). They can differ by a few percent.

## Install and permissions

### Why do I have to right-click → Open?

Simmer is signed *ad hoc*, without a paid Apple Developer ID, so macOS cannot check who made it.
Right-click → Open tells Gatekeeper that you trust it. You do this once. Alternative:
`xattr -dr com.apple.quarantine /Applications/Simmer.app`.

### Why does Simmer need my administrator password?

Only root can write the SMC keys that control charging. Simmer installs a small helper that runs as
root and does only that. The app itself never runs as root. See [SECURITY.md](../SECURITY.md).

### Why does Simmer ask for my password again after an update?

Sparkle updates the app, but the helper is a separate install. When the new app brings a new helper
version, Simmer shows a banner to update it, which needs your password once.

## Other tools

### Can I use Simmer together with another charge limiter?

No. They write the same SMC keys and fight each other: one stops charging, the other starts it again.
Remove the other tool's helper first. **Settings → Conflict Doctor** finds leftovers of the common
tools and can remove known helper files for you.

### Should I turn off the macOS Charge Limit?

On macOS 26.4 and later, set **System Settings → Battery → Charging → Charge Limit** to 100%. If
macOS holds at 80%, Simmer cannot charge above 80%, so Top Up and calibration stop early. Optimized
Battery Charging can stay on, but with a limit of 80% or lower it rarely has an effect.

### Who makes Simmer?

Simmer is an independent, from-scratch open-source project by Umar Waseem. It contains no code or
assets from any other charge-limiter product. It uses the documented SMC keys that every charge
limiter on macOS uses, and it is not affiliated with Apple or with any other battery app.

## Troubleshooting

### The panel says the helper is not reachable

1. Check that it is installed: `ls /Library/PrivilegedHelperTools/com.umarwaseem.simmer.helper`.
2. Check that launchd runs it: `sudo launchctl print system/com.umarwaseem.simmer.helper | head`.
3. Reinstall from **Settings → Helper & Updates**.
4. Look at `tail -n 50 /Library/Logs/simmerd.log`.

### The Mac charges past the limit

- Is another limiter installed? Run the Conflict doctor.
- Is the limiter on (`simmerctl status`)? Is a top up or calibration running?
- On Intel Macs with `BCLM`, the shown percentage settles a few percent above the limit. That is
  expected.
- Open an issue with `simmerctl status --json`, your Mac model and macOS version.

### External displays turn off when I close the lid while discharging

macOS treats the Mac as "on battery" while the adapter is switched off, and sleeps on lid close.
Simmer prevents that by blocking sleep while it discharges (Settings → Sleep → **Stay awake with the lid
closed**). Turn that on if it is off.

### How do I remove everything?

See [Uninstall](../README.md#uninstall) in the README.

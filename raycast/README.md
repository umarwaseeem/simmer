# Simmer for Raycast

Control [Simmer](https://github.com/umarwaseeem/simmer), the open-source battery charge limiter for
macOS, from Raycast.

## Commands

| Command | What it does |
| --- | --- |
| **Battery Status** | Battery level, charging state, limit, power flow, health and temperature. Actions for every command below. |
| **Set Charge Limit** | Sets the limit. Type the value as the argument: `Set Charge Limit 80`. |
| **Charge to 100% Once** | Charges to 100% once, then goes back to the limit. Run it again to stop. |
| **Discharge to Limit** | Runs from the battery down to the limit while plugged in. Run it again to stop. |
| **Pause Charging Here** | Sets the limit to the current percentage. |
| **Toggle Charge Limiter** | Turns the limiter on or off. |

## Requirements

- Simmer installed, with its helper. Simmer installs `simmerctl` to `/usr/local/bin/simmerctl`
  together with the helper. The extension runs that tool and nothing else.
- If you installed `simmerctl` somewhere else, set **simmerctl Path** in the extension preferences.

## Development

```sh
cd raycast
npm install
npm run dev     # opens the extension in Raycast in development mode
npm run lint
```

The extension calls `simmerctl status --json`, `simmerctl config --json` and the action commands
(`limit`, `topup`, `discharge`, `pause`, `limiter`). Run `simmerctl help` for the full list.

## License

This extension is available under the MIT license (a requirement of the Raycast Store), so you can
copy it into the [raycast/extensions](https://github.com/raycast/extensions) repository. The Simmer
app itself is GPL-3.0.

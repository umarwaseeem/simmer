import { Action, ActionPanel, Color, Detail, Icon, Keyboard, open } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import {
  STATE_TITLES,
  SimmerStatus,
  formatMinutes,
  getConfig,
  getStatus,
  healthPercent,
  runAndReport,
} from "./simmerctl";

const LIMIT_PRESETS = [50, 60, 70, 75, 80, 85, 90, 95, 100];

function stateColor(state: string): Color {
  switch (state) {
    case "charging":
    case "topUp":
      return Color.Orange;
    case "limitReached":
    case "sailing":
      return Color.Green;
    case "discharging":
    case "calibration":
      return Color.Blue;
    case "heatProtection":
    case "unsupported":
      return Color.Red;
    default:
      return Color.SecondaryText;
  }
}

function watts(w?: number | null): string | undefined {
  return w == null ? undefined : `${Math.abs(w).toFixed(1)} W`;
}

function bar(percent: number, limit: number): string {
  const cells = 20;
  const filled = Math.round((percent / 100) * cells);
  const mark = Math.min(cells - 1, Math.max(0, Math.round((limit / 100) * cells) - 1));
  return Array.from({ length: cells }, (_, i) => (i === mark ? "┃" : i < filled ? "█" : "░")).join("");
}

function markdown(s: SimmerStatus): string {
  const limit = s.effectiveLimit ?? s.targetPercent;
  const title = STATE_TITLES[s.state] ?? s.state;
  const lines = [
    `# ${s.battery.percent}%  ·  ${title}`,
    "",
    "`" + bar(s.battery.percent, limit) + "`  limit " + limit + "%",
  ];
  if (s.lastError) lines.push("", `> ⚠️ ${s.lastError}`);
  return lines.join("\n");
}

export default function Command() {
  const { data, isLoading, error, revalidate } = usePromise(async () => {
    const [status, config] = await Promise.all([getStatus(), getConfig()]);
    return { status, config };
  });

  const act = async (args: string[]) => {
    if (await runAndReport(args)) revalidate();
  };

  if (error) {
    return (
      <Detail
        markdown={`# Simmer is not reachable\n\n${error.message}\n\nOpen the Simmer app and install its helper, then try again.`}
        actions={
          <ActionPanel>
            <Action title="Open Simmer" icon={Icon.AppWindow} onAction={() => open("simmer://open")} />
            <Action title="Retry" icon={Icon.ArrowClockwise} onAction={revalidate} />
          </ActionPanel>
        }
      />
    );
  }

  const s = data?.status;
  const config = data?.config;
  const health = s ? healthPercent(s) : undefined;
  const remaining = s ? formatMinutes(s.battery.timeRemainingMin) : undefined;
  const temperature = s ? (s.smcTemperatureC ?? s.battery.temperatureC) : undefined;

  return (
    <Detail
      isLoading={isLoading}
      markdown={s ? markdown(s) : ""}
      metadata={
        s && (
          <Detail.Metadata>
            <Detail.Metadata.TagList title="State">
              <Detail.Metadata.TagList.Item text={STATE_TITLES[s.state] ?? s.state} color={stateColor(s.state)} />
            </Detail.Metadata.TagList>
            <Detail.Metadata.Label title="Charge limit" text={`${s.effectiveLimit ?? s.targetPercent}%`} />
            <Detail.Metadata.Label title="Limiter" text={config?.limiterEnabled ? "On" : "Off"} />
            <Detail.Metadata.Label title="Hardware percentage" text={`${s.battery.hardwarePercent.toFixed(1)}%`} />
            {remaining && (
              <Detail.Metadata.Label title={s.battery.isCharging ? "Time to full" : "Time left"} text={remaining} />
            )}
            <Detail.Metadata.Separator />
            <Detail.Metadata.Label
              title="Power adapter"
              text={s.battery.externalConnected ? `${s.battery.adapterName || "Connected"}` : "Not connected"}
            />
            {watts(s.adapterPowerW) && <Detail.Metadata.Label title="From adapter" text={watts(s.adapterPowerW)} />}
            {watts(s.systemPowerW) && <Detail.Metadata.Label title="System power" text={watts(s.systemPowerW)} />}
            <Detail.Metadata.Label
              title="Battery power"
              text={`${(s.battery.voltageV * s.battery.amperageA).toFixed(1)} W`}
            />
            <Detail.Metadata.Separator />
            {health !== undefined && <Detail.Metadata.Label title="Health" text={`${health.toFixed(1)}%`} />}
            <Detail.Metadata.Label title="Cycle count" text={String(s.battery.cycleCount)} />
            {temperature !== undefined && (
              <Detail.Metadata.Label title="Temperature" text={`${temperature.toFixed(1)} °C`} />
            )}
            <Detail.Metadata.Separator />
            <Detail.Metadata.Label title="Helper" text={`${s.helperVersion} (${s.backend})`} />
          </Detail.Metadata>
        )
      }
      actions={
        s && (
          <ActionPanel>
            <ActionPanel.Submenu title="Set Charge Limit" icon={Icon.BatteryCharging}>
              {LIMIT_PRESETS.map((v) => (
                <Action key={v} title={`${v}%`} onAction={() => act(["limit", String(v)])} />
              ))}
            </ActionPanel.Submenu>
            <Action
              title={s.runtime.topUp ? "Stop Charging to 100%" : "Charge to 100% Once"}
              icon={Icon.Plug}
              onAction={() => act(["topup", s.runtime.topUp ? "off" : "on"])}
            />
            {s.supportsDischarge && (
              <Action
                title={s.runtime.manualDischarge ? "Stop Discharge" : "Discharge to Limit"}
                icon={Icon.BatteryDisabled}
                onAction={() => act(["discharge", s.runtime.manualDischarge ? "off" : "on"])}
              />
            )}
            <Action title="Pause Charging Here" icon={Icon.Pause} onAction={() => act(["pause"])} />
            <Action
              title={config?.limiterEnabled ? "Disable Limiter" : "Enable Limiter"}
              icon={Icon.Power}
              onAction={() => act(["limiter", config?.limiterEnabled ? "off" : "on"])}
            />
            <Action
              title="Refresh"
              icon={Icon.ArrowClockwise}
              shortcut={Keyboard.Shortcut.Common.Refresh}
              onAction={revalidate}
            />
            <Action title="Open Simmer" icon={Icon.AppWindow} onAction={() => open("simmer://open")} />
          </ActionPanel>
        )
      }
    />
  );
}

import { getPreferenceValues, showHUD } from "@raycast/api";
import { showFailureToast } from "@raycast/utils";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const DEFAULT_PATH = "/usr/local/bin/simmerctl";

/** The parts of `simmerctl status --json` that this extension reads. */
export interface SimmerStatus {
  helperVersion: string;
  backend: string;
  state: string;
  targetPercent: number;
  effectiveLimit?: number;
  limitReason?: string;
  chargingInhibited: boolean;
  adapterDisabled: boolean;
  supportsDischarge: boolean;
  smcTemperatureC?: number | null;
  systemPowerW?: number | null;
  adapterPowerW?: number | null;
  lastError?: string | null;
  runtime: {
    topUp: boolean;
    manualDischarge: boolean;
    calibrationPhase?: string | null;
  };
  battery: {
    percent: number;
    hardwarePercent: number;
    externalConnected: boolean;
    isCharging: boolean;
    voltageV: number;
    amperageA: number;
    temperatureC: number;
    cycleCount: number;
    designCapacity: number;
    rawMaxCapacity: number;
    timeRemainingMin?: number | null;
    adapterWatts: number;
    adapterName: string;
  };
}

/** The parts of `simmerctl config --json` that this extension reads. */
export interface SimmerConfig {
  chargeLimit: number;
  limiterEnabled: boolean;
}

export const STATE_TITLES: Record<string, string> = {
  notPluggedIn: "On Battery",
  charging: "Charging",
  limitReached: "Charge Limit Reached",
  sailing: "Sailing",
  discharging: "Discharging",
  heatProtection: "Heat Protection",
  topUp: "Top Up",
  calibration: "Calibration",
  limiterOff: "Limiter Off",
  unsupported: "Unsupported Hardware",
};

function binaryPath(): string {
  const prefs = getPreferenceValues<{ simmerctlPath?: string }>();
  return prefs.simmerctlPath?.trim() || DEFAULT_PATH;
}

/** Runs simmerctl and returns stdout. Throws an Error with simmerctl's own message on failure. */
export async function simmerctl(args: string[]): Promise<string> {
  const path = binaryPath();
  try {
    const { stdout } = await execFileAsync(path, args, { timeout: 15_000 });
    return stdout.trim();
  } catch (error) {
    const err = error as NodeJS.ErrnoException & { stderr?: string };
    if (err.code === "ENOENT") {
      throw new Error(`simmerctl was not found at ${path}. Open Simmer and install its helper first.`);
    }
    const message = (err.stderr || err.message || String(error)).trim().split("\n")[0];
    throw new Error(message.replace(/^simmerctl: /, ""));
  }
}

export async function getStatus(): Promise<SimmerStatus> {
  return JSON.parse(await simmerctl(["status", "--json"])) as SimmerStatus;
}

export async function getConfig(): Promise<SimmerConfig> {
  return JSON.parse(await simmerctl(["config", "--json"])) as SimmerConfig;
}

/** Runs one command and reports the result as a HUD (success) or a toast (failure). */
export async function runAndReport(args: string[]): Promise<boolean> {
  try {
    const output = await simmerctl(args);
    await showHUD(output.split("\n")[0] || "Done");
    return true;
  } catch (error) {
    await showFailureToast(error, { title: "Simmer" });
    return false;
  }
}

export function healthPercent(s: SimmerStatus): number | undefined {
  const { designCapacity, rawMaxCapacity } = s.battery;
  return designCapacity > 0 ? (rawMaxCapacity / designCapacity) * 100 : undefined;
}

export function formatMinutes(min?: number | null): string | undefined {
  if (min == null || min <= 0 || min > 60 * 24) return undefined;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return h > 0 ? `${h} h ${m} min` : `${m} min`;
}

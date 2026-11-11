import { showFailureToast } from "@raycast/utils";
import { getStatus, runAndReport } from "./simmerctl";

// Starts discharging to the limit while plugged in, or stops it.
export default async function Command() {
  try {
    const status = await getStatus();
    if (!status.supportsDischarge && !status.runtime.manualDischarge) {
      throw new Error("This Mac cannot run from the battery while the charger is connected.");
    }
    await runAndReport(["discharge", status.runtime.manualDischarge ? "off" : "on"]);
  } catch (error) {
    await showFailureToast(error, { title: "Simmer" });
  }
}

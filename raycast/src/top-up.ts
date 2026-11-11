import { showFailureToast } from "@raycast/utils";
import { getStatus, runAndReport } from "./simmerctl";

// Starts a top up to 100%, or stops the one that is running.
export default async function Command() {
  try {
    const status = await getStatus();
    await runAndReport(["topup", status.runtime.topUp ? "off" : "on"]);
  } catch (error) {
    await showFailureToast(error, { title: "Simmer" });
  }
}

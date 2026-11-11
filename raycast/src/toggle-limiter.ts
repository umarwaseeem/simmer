import { showFailureToast } from "@raycast/utils";
import { getConfig, runAndReport } from "./simmerctl";

export default async function Command() {
  try {
    const config = await getConfig();
    await runAndReport(["limiter", config.limiterEnabled ? "off" : "on"]);
  } catch (error) {
    await showFailureToast(error, { title: "Simmer" });
  }
}

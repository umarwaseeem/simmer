import { LaunchProps } from "@raycast/api";
import { showFailureToast } from "@raycast/utils";
import { runAndReport } from "./simmerctl";

export default async function Command(props: LaunchProps<{ arguments: { limit: string } }>) {
  const value = Number.parseInt(props.arguments.limit.replace("%", "").trim(), 10);
  if (!Number.isInteger(value) || value < 20 || value > 100) {
    await showFailureToast(new Error("Enter a whole number from 20 to 100."), { title: "Invalid charge limit" });
    return;
  }
  await runAndReport(["limit", String(value)]);
}

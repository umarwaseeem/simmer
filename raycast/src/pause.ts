import { runAndReport } from "./simmerctl";

// Sets the charge limit to the current percentage, so the battery stays where it is.
export default async function Command() {
  await runAndReport(["pause"]);
}

#!/usr/bin/env node
import { homedir } from "node:os";
import { join } from "node:path";
import { createWorldServer } from "./server.ts";
import { formatStatusTable, readCivilizationStatus } from "./status.ts";

const [command, ...args] = process.argv.slice(2);
const registryPath = join(homedir(), ".claude", "civilization.json");
if (command === "world") {
  const portFlag = args.indexOf("--port");
  const portValue = portFlag === -1 ? "4877" : args[portFlag + 1];
  const port = Number(portValue);
  if (
    !Number.isInteger(port) ||
    port < 1 ||
    port > 65535 ||
    args.some(
      (argument, index) =>
        argument !== "--port" && (portFlag === -1 || index !== portFlag + 1),
    )
  ) {
    console.error("Usage: fortkit world [--port <1-65535>]");
    process.exitCode = 2;
  } else {
    createWorldServer(registryPath).listen(port, "127.0.0.1", () => {
      console.log(`fortkit world listening at http://127.0.0.1:${port}`);
    });
  }
} else if (
  command !== "status" ||
  args.some((argument) => argument !== "--json")
) {
  console.error(
    "Usage: fortkit status [--json]\n       fortkit world [--port <1-65535>]",
  );
  process.exitCode = 2;
} else {
  const forts = await readCivilizationStatus(registryPath);
  console.log(
    args.includes("--json")
      ? JSON.stringify(forts, null, 2)
      : formatStatusTable(forts),
  );
}

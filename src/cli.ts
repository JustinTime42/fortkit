#!/usr/bin/env node
import { homedir } from "node:os";
import { join } from "node:path";

import { formatStatusTable, readCivilizationStatus } from "./status.ts";

const [command, ...args] = process.argv.slice(2);
if (command !== "status" || args.some((argument) => argument !== "--json")) {
  console.error("Usage: fortkit status [--json]");
  process.exitCode = 2;
} else {
  const forts = await readCivilizationStatus(
    join(homedir(), ".claude", "civilization.json"),
  );
  console.log(
    args.includes("--json")
      ? JSON.stringify(forts, null, 2)
      : formatStatusTable(forts),
  );
}

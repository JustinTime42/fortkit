#!/usr/bin/env node
import { homedir } from "node:os";
import { join } from "node:path";
import { formatDigest, readCivilizationDigest } from "./digest.ts";
import { createWorldServer } from "./server.ts";
import { formatStatusTable, readCivilizationStatus } from "./status.ts";

const [command, ...args] = process.argv.slice(2);
const registryPath = join(homedir(), ".claude", "civilization.json");
if (command === "digest") {
  const sinceIndex = args.indexOf("--since");
  const untilIndex = args.indexOf("--until");
  const since = sinceIndex === -1 ? undefined : args[sinceIndex + 1];
  const until = untilIndex === -1 ? undefined : args[untilIndex + 1];
  const sinceInstant = typeof since === "string" ? Date.parse(since) : NaN;
  const untilInstant = typeof until === "string" ? Date.parse(until) : NaN;
  const allowed = new Set(["--since", "--until", "--json", since, until]);
  const jsonCount = args.filter((argument) => argument === "--json").length;
  const expectedArgumentCount = 2 + (until === undefined ? 0 : 2) + jsonCount;
  const valid =
    typeof since === "string" &&
    !Number.isNaN(sinceInstant) &&
    (until === undefined || !Number.isNaN(untilInstant)) &&
    (until === undefined || sinceInstant < untilInstant) &&
    args.every((argument) => allowed.has(argument)) &&
    args.length === expectedArgumentCount &&
    args.filter((argument) => argument === "--since").length === 1 &&
    args.filter((argument) => argument === "--until").length <= 1 &&
    jsonCount <= 1;
  if (!valid) {
    console.error(
      "Usage: fortkit digest --since <timestamp> [--until <timestamp>] [--json]",
    );
    process.exitCode = 2;
  } else {
    const digest = await readCivilizationDigest(
      registryPath,
      since,
      until ?? new Date().toISOString(),
    );
    console.log(
      args.includes("--json")
        ? JSON.stringify(digest, null, 2)
        : formatDigest(digest),
    );
  }
} else if (command === "world") {
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
    "Usage: fortkit status [--json]\n       fortkit world [--port <1-65535>]\n       fortkit digest --since <timestamp> [--until <timestamp>] [--json]",
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

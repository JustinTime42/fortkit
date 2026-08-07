#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { formatAmbientDay, fortSeedFor } from "./ambient.ts";
import { formatDigest, readCivilizationDigest } from "./digest.ts";
import { createWorldServer } from "./server.ts";
import { formatStatusTable, readCivilizationStatus } from "./status.ts";

const [command, ...args] = process.argv.slice(2);
const registryPath = join(homedir(), ".claude", "civilization.json");
async function currentFortName(): Promise<string> {
  try {
    const charter = await readFile(
      join(process.cwd(), "fort", "charter.md"),
      "utf8",
    );
    return /^#\s+(.+?)\s+Charter\b/m.exec(charter)?.[1] ?? "this fort";
  } catch {
    return "this fort";
  }
}

if (command === "ambient") {
  const sinceIndex = args.indexOf("--since");
  const citizen = args[0] ?? "";
  const since =
    sinceIndex === -1 ? new Date().toISOString() : (args[sinceIndex + 1] ?? "");
  const valid =
    citizen.length > 0 &&
    !Number.isNaN(Date.parse(since)) &&
    args.length === (sinceIndex === -1 ? 1 : 3) &&
    (sinceIndex === -1 || sinceIndex === 1) &&
    args.filter((argument) => argument === "--since").length <= 1;
  if (!valid) {
    console.error("Usage: fortkit ambient <citizen> [--since <timestamp>]");
    process.exitCode = 2;
  } else {
    const fortName = await currentFortName();
    console.log(formatAmbientDay(citizen, since, fortSeedFor(fortName)));
  }
} else if (command === "digest") {
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
    "Usage: fortkit status [--json]\n       fortkit world [--port <1-65535>]\n       fortkit digest --since <timestamp> [--until <timestamp>] [--json]\n       fortkit ambient <citizen> [--since <timestamp>]",
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

#!/usr/bin/env node
import { homedir } from "node:os";
import { join, resolve, sep } from "node:path";
import {
  formatAmbientDay,
  formatAmbientSince,
  fortSeedFor,
} from "./ambient.ts";
import { formatDigest, readCivilizationDigest } from "./digest.ts";
import { readRegistry } from "./readers/registry.ts";
import { createWorldServer } from "./server.ts";
import { formatStatusTable, readCivilizationStatus } from "./status.ts";

const [command, ...args] = process.argv.slice(2);
const registryPath = join(homedir(), ".claude", "civilization.json");
async function currentFortName(): Promise<string> {
  const cwd = resolve(process.cwd());
  const fort = (await readRegistry(registryPath)).find(
    ({ path }) => cwd === path || cwd.startsWith(`${path}${sep}`),
  );
  if (fort === undefined) {
    throw new Error(
      `ambient: ${cwd} is not a registered fort in ${registryPath}; refusing to invent a fort seed`,
    );
  }
  return fort.name;
}

if (command === "ambient") {
  const sinceIndex = args.indexOf("--since");
  const onIndex = args.indexOf("--on");
  const citizen = args[0] ?? "";
  const timestampIndex = sinceIndex === -1 ? onIndex : sinceIndex;
  const timestamp =
    timestampIndex === -1
      ? new Date().toISOString()
      : (args[timestampIndex + 1] ?? "");
  const valid =
    citizen.length > 0 &&
    !Number.isNaN(Date.parse(timestamp)) &&
    args.length === (timestampIndex === -1 ? 1 : 3) &&
    (timestampIndex === -1 || timestampIndex === 1) &&
    args.filter((argument) => argument === "--since").length <= 1 &&
    args.filter((argument) => argument === "--on").length <= 1 &&
    !(sinceIndex !== -1 && onIndex !== -1);
  if (!valid) {
    console.error(
      "Usage: fortkit ambient <citizen> [--on <timestamp> | --since <timestamp>]",
    );
    process.exitCode = 2;
  } else {
    try {
      const fortName = await currentFortName();
      const seed = fortSeedFor(fortName);
      const output =
        sinceIndex === -1
          ? formatAmbientDay(citizen, timestamp, seed)
          : formatAmbientSince(citizen, timestamp, seed);
      console.log(output);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(message);
      process.exitCode = 1;
    }
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
    "Usage: fortkit status [--json]\n       fortkit world [--port <1-65535>]\n       fortkit digest --since <timestamp> [--until <timestamp>] [--json]\n       fortkit ambient <citizen> [--on <timestamp> | --since <timestamp>]",
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

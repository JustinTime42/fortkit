#!/usr/bin/env node
import { homedir } from "node:os";
import { join, resolve, sep } from "node:path";
import {
  ambientIdFor,
  formatAmbientDay,
  formatAmbientSince,
  fortSeedFor,
} from "./ambient.ts";
import {
  fetchHandoffSections,
  formatDigest,
  readCivilizationDigest,
} from "./digest.ts";
import { readRegistry } from "./readers/registry.ts";
import { recall } from "./recall.ts";
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
      const citizenId = ambientIdFor(citizen);
      const output =
        sinceIndex === -1
          ? formatAmbientDay(citizenId, timestamp, seed)
          : formatAmbientSince(citizenId, timestamp, seed);
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
  const eventCapIndex = args.indexOf("--max-events-per-fort");
  const fetchIndex = args.indexOf("--fetch");
  const since = sinceIndex === -1 ? undefined : args[sinceIndex + 1];
  const until = untilIndex === -1 ? undefined : args[untilIndex + 1];
  const eventCap = eventCapIndex === -1 ? undefined : args[eventCapIndex + 1];
  const fetch = fetchIndex === -1 ? undefined : args[fetchIndex + 1];
  const sinceInstant = typeof since === "string" ? Date.parse(since) : NaN;
  const untilInstant = typeof until === "string" ? Date.parse(until) : NaN;
  const allowed = new Set([
    "--since",
    "--until",
    "--json",
    "--max-events-per-fort",
    "--fetch",
    since,
    until,
    eventCap,
    fetch,
  ]);
  const jsonCount = args.filter((argument) => argument === "--json").length;
  const expectedArgumentCount =
    2 +
    (until === undefined ? 0 : 2) +
    (eventCap === undefined ? 0 : 2) +
    (fetch === undefined ? 0 : 2) +
    jsonCount;
  const valid =
    typeof since === "string" &&
    !Number.isNaN(sinceInstant) &&
    (until === undefined || !Number.isNaN(untilInstant)) &&
    (eventCap === undefined ||
      (/^[1-9]\d*$/.test(eventCap) &&
        Number.isSafeInteger(Number(eventCap)))) &&
    (fetch === undefined || fetch.split(",").every((id) => id.length > 0)) &&
    (until === undefined || sinceInstant < untilInstant) &&
    args.every((argument) => allowed.has(argument)) &&
    args.length === expectedArgumentCount &&
    args.filter((argument) => argument === "--since").length === 1 &&
    args.filter((argument) => argument === "--until").length <= 1 &&
    args.filter((argument) => argument === "--max-events-per-fort").length <=
      1 &&
    args.filter((argument) => argument === "--fetch").length <= 1 &&
    jsonCount <= 1;
  if (!valid) {
    console.error(
      "Usage: fortkit digest --since <timestamp> [--until <timestamp>] [--max-events-per-fort <positive integer>] [--fetch <id>[,<id>...]] [--json]",
    );
    process.exitCode = 2;
  } else {
    try {
      const windowUntil = until ?? new Date().toISOString();
      const digest = await readCivilizationDigest(
        registryPath,
        since,
        windowUntil,
        {
          ...(eventCap === undefined
            ? {}
            : { maxEventsPerFort: Number(eventCap) }),
        },
      );
      if (fetch !== undefined) {
        const handoffSections = await fetchHandoffSections(
          registryPath,
          since,
          windowUntil,
          fetch.split(","),
        );
        console.log(JSON.stringify({ handoffSections }, null, 2));
      } else {
        console.log(
          args.includes("--json")
            ? JSON.stringify(digest, null, 2)
            : formatDigest(digest),
        );
      }
    } catch (error) {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    }
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
} else if (command === "recall") {
  const flags = new Set(["--seat", "--topic", "--bead", "--since", "--until"]);
  const filters: Record<string, string> = {};
  const query: string[] = [];
  let valid = true;
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === undefined) continue;
    if (flags.has(argument)) {
      const value = args[index + 1];
      if (
        value === undefined ||
        value.startsWith("--") ||
        filters[argument] !== undefined
      ) {
        valid = false;
        break;
      }
      filters[argument] = value;
      index += 1;
    } else if (argument.startsWith("--")) {
      valid = false;
      break;
    } else query.push(argument);
  }
  if (query.length === 0) valid = false;
  if (!valid) {
    console.error(
      "Usage: fortkit recall <query> [--seat <seat>] [--topic <topic>] [--bead <bead>] [--since <timestamp>] [--until <timestamp>]",
    );
    process.exitCode = 2;
  } else {
    try {
      const result = await recall(process.cwd(), query.join(" "), {
        ...(filters["--seat"] === undefined ? {} : { seat: filters["--seat"] }),
        ...(filters["--topic"] === undefined
          ? {}
          : { topic: filters["--topic"] }),
        ...(filters["--bead"] === undefined ? {} : { bead: filters["--bead"] }),
        ...(filters["--since"] === undefined
          ? {}
          : { since: filters["--since"] }),
        ...(filters["--until"] === undefined
          ? {}
          : { until: filters["--until"] }),
      });
      console.log(JSON.stringify(result, null, 2));
    } catch (error) {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    }
  }
} else if (
  command !== "status" ||
  args.some((argument) => argument !== "--json")
) {
  console.error(
    "Usage: fortkit status [--json]\n       fortkit world [--port <1-65535>]\n       fortkit digest --since <timestamp> [--until <timestamp>] [--json]\n       fortkit ambient <citizen> [--on <timestamp> | --since <timestamp>]\n       fortkit recall <query> [--seat <seat>] [--topic <topic>] [--bead <bead>] [--since <timestamp>] [--until <timestamp>]",
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

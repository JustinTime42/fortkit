#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import {
  fetchHandoffSections,
  formatDigest,
  readCivilizationDigest,
} from "./digest.ts";
import { lintDraft } from "./herald-lint.ts";
import { recall } from "./recall.ts";
import { formatStatusTable, readCivilizationStatus } from "./status.ts";

const [command, ...args] = process.argv.slice(2);
const registryPath = join(homedir(), ".claude", "civilization.json");

if (command === "herald-lint") {
  const draftPath = args.find((argument) => !argument.startsWith("--"));
  const json = args.filter((argument) => argument === "--json").length;
  const valid =
    draftPath !== undefined &&
    args.length === 1 + json &&
    json <= 1 &&
    args.every((argument) => argument === draftPath || argument === "--json");
  if (!valid) {
    console.error("Usage: fortkit herald-lint <draft.md> [--json]");
    process.exitCode = 2;
  } else {
    try {
      const result = lintDraft(await readFile(draftPath, "utf8"));
      console.log(
        args.includes("--json")
          ? JSON.stringify(result, null, 2)
          : `${result.verdict.toUpperCase()} (${result.counts.postChars} chars)\n${result.checks.map(({ id, result: checkResult, detail }) => `${checkResult.toUpperCase()} ${id}: ${detail}`).join("\n")}`,
      );
      process.exitCode = result.verdict === "pass" ? 0 : 1;
    } catch (error) {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 2;
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
      if (fetch !== undefined) {
        const handoffSections = await fetchHandoffSections(
          registryPath,
          since,
          windowUntil,
          fetch.split(","),
        );
        console.log(JSON.stringify({ handoffSections }, null, 2));
      } else {
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
} else if (command === "recall") {
  const flags = new Set([
    "--seat",
    "--topic",
    "--bead",
    "--since",
    "--until",
    "--limit",
  ]);
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
  const limit =
    filters["--limit"] === undefined ? undefined : Number(filters["--limit"]);
  if (limit !== undefined && (!Number.isInteger(limit) || limit < 1))
    valid = false;
  if (!valid) {
    console.error(
      "Usage: fortkit recall <query> [--seat <seat>] [--topic <topic>] [--bead <bead>] [--since <timestamp>] [--until <timestamp>] [--limit <positive integer>]",
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
        ...(limit === undefined ? {} : { limit }),
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
    "Usage: fortkit status [--json]\n       fortkit herald-lint <draft.md> [--json]\n       fortkit digest --since <timestamp> [--until <timestamp>] [--max-events-per-fort <positive integer>] [--fetch <id>[,<id>...]] [--json]\n       fortkit recall <query> [--seat <seat>] [--topic <topic>] [--bead <bead>] [--since <timestamp>] [--until <timestamp>] [--limit <positive integer>]",
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

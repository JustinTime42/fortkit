#!/usr/bin/env node
// Replay one fixed Mayor transcript window. This command is intentionally
// output-only: all inputs are read in place and only --out is written.
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { loadForts, prefixOf } from "../lib/forts.mjs";
import { summariseMayor } from "../lib/mayor-summary.mjs";
import {
  extractHighlights,
  mayorTranscriptPath,
  resolveBeadFacts,
  summaryFactsBlock,
  windowCounts,
} from "../lib/mayor-summary-extract.mjs";
import { parseExport } from "../lib/readers.mjs";

function argumentsOf(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!/^--(?:fort|session|start|end|out)$/.test(flag ?? "") || !value)
      throw new Error(
        "usage: replay-summary.mjs --fort KEY --session ID --start ISO --end ISO --out FILE",
      );
    result[flag.slice(2)] = value;
  }
  for (const key of ["fort", "session", "start", "end", "out"])
    if (!result[key]) throw new Error(`--${key} is required`);
  if (!Number.isFinite(Date.parse(result.start)))
    throw new Error("--start must be an ISO timestamp");
  if (!Number.isFinite(Date.parse(result.end)))
    throw new Error("--end must be an ISO timestamp");
  if (Date.parse(result.start) >= Date.parse(result.end))
    throw new Error("--start must precede --end");
  return result;
}

export async function replaySummary(argv, options = {}) {
  const args = argumentsOf(argv);
  const fileSystem = options.fileSystem ?? fs;
  const env = options.env ?? process.env;
  const fort = (options.loadForts ?? loadForts)({ env, fileSystem }).find(
    (candidate) => candidate.key === args.fort,
  );
  if (!fort) throw new Error(`unknown production fort: ${args.fort}`);
  const exportPath = path.join(fort.repo, ".beads/issues.jsonl");
  const exportStat = fileSystem.statSync(exportPath);
  const parsed = parseExport(fileSystem.readFileSync(exportPath, "utf8"));
  const eventsDirectory = path.join(fort.repo, "fort/events");
  let events = [];
  try {
    events = fileSystem
      .readdirSync(eventsDirectory)
      .filter((name) => /^events-.*\.jsonl$/.test(name))
      .flatMap((name) =>
        fileSystem
          .readFileSync(path.join(eventsDirectory, name), "utf8")
          .split("\n")
          .filter(Boolean)
          .flatMap((line) => {
            try {
              return [JSON.parse(line)];
            } catch {
              return [];
            }
          }),
      );
  } catch {
    // A fort with no event directory has no event facts for this replay.
  }
  const entry = {
    fort: { ...fort, prefix: prefixOf(parsed.byId.values()) },
    byId: parsed.byId,
    events: { events },
    fleet: { workers: [] },
  };
  const transcriptPath = mayorTranscriptPath(
    { cwd: fort.repo, sessionId: args.session },
    { home: env.HOME ?? "" },
  );
  const extracted = await extractHighlights(transcriptPath, args.start, {
    fileSystem,
    windowEnd: args.end,
  });
  if (extracted.reason) throw new Error(extracted.reason);
  const counts = windowCounts(entry, args.start, args.end, {
    fileSystem,
    now: () => Date.parse(args.end),
  });
  const record = await summariseMayor(
    {
      fort,
      session: { sessionId: args.session },
      transcriptPath,
      windowStart: args.start,
      windowEnd: args.end,
      firstRun: false,
      windowReason: "fixed replay window",
      fingerprint: null,
      highlights: extracted.highlights,
      beadFacts: resolveBeadFacts(extracted.highlights, [entry], entry),
      counts,
      factsBlock: summaryFactsBlock(entry, counts),
      malformedLines: extracted.malformedLines,
      keepRefreshedAt: null,
      beadExport: {
        path: exportPath,
        mtime: exportStat.mtime.toISOString(),
        readOnly: true,
      },
    },
    {
      fileSystem,
      fetch: options.fetch ?? globalThis.fetch,
      now: options.now,
      persist: false,
    },
  );
  fileSystem.writeFileSync(args.out, `${JSON.stringify(record, null, 2)}\n`, {
    mode: 0o600,
    flag: "wx",
  });
  return record;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  replaySummary(process.argv.slice(2)).catch((error) => {
    console.error(error.message ?? error);
    process.exitCode = 1;
  });
}

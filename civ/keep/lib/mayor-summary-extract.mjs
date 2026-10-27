// Read-only inputs for a per-fort Mayor summary. This module deliberately does
// not invoke bd: the Keep's refreshed state is the authoritative bead snapshot.
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { graphContext, needsYou } from "./graph.mjs";
import { idPattern } from "./readers.mjs";

function samePath(left, right) {
  return path.resolve(left) === path.resolve(right);
}

function dateValue(value) {
  const result = Date.parse(value ?? "");
  return Number.isNaN(result) ? null : result;
}

// `sessions` contains adjacent secret key files. Listing only numeric json names
// is intentional: no caller may ever read a session's .key file.
export function findLiveMayor(fort, options = {}) {
  const fileSystem = options.fileSystem ?? fs;
  const procRoot = options.procRoot ?? "/proc";
  const sessionsDirectory = options.sessionsDirectory;
  if (!sessionsDirectory) throw new Error("sessionsDirectory is required");
  let names;
  try {
    names = fileSystem.readdirSync(sessionsDirectory);
  } catch {
    return null;
  }
  const candidates = [];
  for (const name of names) {
    if (!/^\d+\.json$/.test(name)) continue;
    let session;
    try {
      session = JSON.parse(
        fileSystem.readFileSync(path.join(sessionsDirectory, name), "utf8"),
      );
    } catch {
      continue;
    }
    const pid = String(session.pid ?? "");
    const processPath = path.join(procRoot, pid);
    if (!/^\d+$/.test(pid) || !fileSystem.existsSync(processPath)) continue;
    let environ;
    try {
      environ = fileSystem.readFileSync(
        path.join(processPath, "environ"),
        "utf8",
      );
    } catch {
      continue;
    }
    if (!environ.split("\0").includes("FORT_MASKED=mayor")) continue;
    let cwd = session.cwd;
    try {
      cwd = fileSystem.readlinkSync(path.join(processPath, "cwd"));
    } catch {
      // A process can deny its cwd link while its session record remains useful.
    }
    if (typeof cwd !== "string" || !samePath(cwd, fort.repo)) continue;
    candidates.push(session);
  }
  candidates.sort(
    (left, right) =>
      (dateValue(right.startedAt) ?? 0) - (dateValue(left.startedAt) ?? 0),
  );
  return candidates[0] ?? null;
}

export async function extractHighlights(
  transcriptPath,
  windowStart,
  options = {},
) {
  const fileSystem = options.fileSystem ?? fs;
  const start =
    typeof windowStart === "number" ? windowStart : dateValue(windowStart);
  if (start === null) throw new Error("windowStart must be a valid timestamp");
  const highlights = [];
  let malformedLines = 0;
  const input = fileSystem.createReadStream(transcriptPath, {
    encoding: "utf8",
  });
  const lines = readline.createInterface({ input, crlfDelay: Infinity });
  for await (const line of lines) {
    let record;
    try {
      record = JSON.parse(line);
    } catch {
      malformedLines += 1;
      continue;
    }
    if (record.type !== "assistant" || record.isSidechain === true) continue;
    const timestamp = dateValue(record.timestamp);
    if (timestamp === null || timestamp <= start) continue;
    const blocks = record.message?.content;
    if (!Array.isArray(blocks)) continue;
    for (const block of blocks) {
      if (block?.type === "text" && typeof block.text === "string")
        highlights.push({ timestamp: record.timestamp, text: block.text });
    }
  }
  return { highlights, malformedLines };
}

export function resolveBeadFacts(highlights, states) {
  const entries = [...states];
  const prefixes = entries.map((entry) => entry.fort.prefix).filter(Boolean);
  const candidate = prefixes.length
    ? new RegExp(
        `\\b(?:${prefixes.map((prefix) => String(prefix).replace(/[.*+?^${}()|[\\]\\\\]/g, "\\$&")).join("|")})-[\\w.-]+\\b`,
        "g",
      )
    : null;
  const facts = [];
  const seen = new Set();
  for (const highlight of highlights) {
    if (!candidate) break;
    for (const match of String(highlight.text).matchAll(candidate)) {
      const id = match[0];
      if (seen.has(id)) continue;
      seen.add(id);
      const entry = entries.find(
        (item) => item.fort.prefix && idPattern(item.fort.prefix).test(id),
      );
      const bead = entry?.byId.get(id);
      if (!bead) {
        facts.push({ id, status: "unknown" });
        continue;
      }
      facts.push({
        id,
        fort: entry.fort.key,
        title: bead.title,
        status: bead.status,
        assignee: bead.assignee ?? null,
        labels: bead.labels ?? [],
      });
    }
  }
  return facts;
}

function inWindow(value, start, end) {
  const timestamp = dateValue(value);
  return timestamp !== null && timestamp > start && timestamp <= end;
}

export function windowCounts(
  fort,
  beads,
  windowStart,
  windowEnd,
  options = {},
) {
  const fileSystem = options.fileSystem ?? fs;
  const now = options.now ?? (() => Date.now());
  const start =
    typeof windowStart === "number" ? windowStart : dateValue(windowStart);
  const end = typeof windowEnd === "number" ? windowEnd : dateValue(windowEnd);
  if (start === null || end === null)
    throw new Error("window bounds must be valid timestamps");
  const values = [...(beads.values ? beads.values() : beads)];
  const result = {
    closed: values.filter((bead) => inWindow(bead.closed_at, start, end))
      .length,
    filed: values.filter((bead) => inWindow(bead.created_at, start, end))
      .length,
    merged: 0,
    halts: [],
    wardenVerdicts: [],
    gateDecisions: [],
    waitingOnOverseer: [],
  };
  const context = graphContext(
    values,
    [],
    [],
    now(),
    fort.waitingLabels,
    fort.whoseMove,
  );
  for (const bead of values)
    if (needsYou(bead, context)) result.waitingOnOverseer.push(bead.id);
  const directory = path.join(fort.repo, "fort/events");
  let names = [];
  try {
    names = fileSystem.readdirSync(directory);
  } catch {
    return result;
  }
  for (const name of names.filter((value) =>
    /^events-.*\.jsonl$/.test(value),
  )) {
    let text;
    try {
      text = fileSystem.readFileSync(path.join(directory, name), "utf8");
    } catch {
      continue;
    }
    for (const line of text.split("\n")) {
      let event;
      try {
        event = JSON.parse(line);
      } catch {
        continue;
      }
      if (!inWindow(event.ts, start, end)) continue;
      if (event.category === "merge") result.merged += 1;
      if (event.category === "halt")
        result.halts.push({ reason: event.reason ?? event.detail ?? "" });
      if (event.category === "review.verdict")
        result.wardenVerdicts.push({
          id: event.target ?? null,
          verdict:
            event.payload?.verdict ?? event.verdict ?? event.detail ?? null,
        });
      if (
        ["gate.approved", "gate.declined", "decision.recorded"].includes(
          event.category,
        )
      )
        result.gateDecisions.push({
          category: event.category,
          id: event.target ?? null,
        });
    }
  }
  return result;
}

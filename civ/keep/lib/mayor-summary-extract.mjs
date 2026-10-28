// Read-only inputs for a per-fort Mayor summary. This module deliberately does
// not invoke bd: the Keep's refreshed state is the authoritative bead snapshot.
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { graphContext, needsYou } from "./graph.mjs";
import { escapeRegExp, idPattern } from "./readers.mjs";

function samePath(left, right) {
  return path.resolve(left) === path.resolve(right);
}

function dateValue(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const result = Date.parse(value ?? "");
  return Number.isNaN(result) ? null : result;
}

export function mayorTranscriptPath(session, options = {}) {
  const home = options.home;
  if (!home) throw new Error("home is required");
  if (!session?.sessionId || typeof session.cwd !== "string") return null;
  return path.join(
    home,
    ".claude/projects",
    session.cwd.replace(/[^A-Za-z0-9]/g, "-"),
    `${session.sessionId}.jsonl`,
  );
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
  const selected = candidates[0];
  return selected ? { ...selected, candidateCount: candidates.length } : null;
}

export async function extractHighlights(
  transcriptPath,
  windowStart,
  options = {},
) {
  const fileSystem = options.fileSystem ?? fs;
  const start = dateValue(windowStart);
  const end =
    options.windowEnd === undefined ? null : dateValue(options.windowEnd);
  if (start === null) throw new Error("windowStart must be a valid timestamp");
  if (options.windowEnd !== undefined && end === null)
    throw new Error("windowEnd must be a valid timestamp");
  const highlights = [];
  let malformedLines = 0;
  let input;
  try {
    input = fileSystem.createReadStream(transcriptPath, { encoding: "utf8" });
  } catch (error) {
    if (error?.code === "ENOENT")
      return { highlights, malformedLines, reason: "no live Mayor transcript" };
    throw error;
  }
  const lines = readline.createInterface({ input, crlfDelay: Infinity });
  try {
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
      if (
        timestamp === null ||
        timestamp <= start ||
        (end !== null && timestamp > end)
      )
        continue;
      const blocks = record.message?.content;
      if (!Array.isArray(blocks)) continue;
      for (const block of blocks) {
        if (block?.type === "text" && typeof block.text === "string")
          highlights.push({ timestamp: record.timestamp, text: block.text });
      }
    }
  } catch (error) {
    if (error?.code === "ENOENT")
      return { highlights, malformedLines, reason: "no live Mayor transcript" };
    throw error;
  }
  return { highlights, malformedLines };
}

function validUnknownId(id, prefix) {
  return new RegExp(`^${escapeRegExp(prefix)}-[a-z0-9]{2,8}(?:\\.\\d+)*$`).test(
    id,
  );
}

export function resolveBeadFacts(highlights, states, ownState = null) {
  const entries = [...states];
  const prefixes = entries.map((entry) => entry.fort.prefix).filter(Boolean);
  const candidate = prefixes.length
    ? new RegExp(
        `\\b(?:${prefixes.map((prefix) => escapeRegExp(String(prefix))).join("|")})-[\\w.-]+\\b`,
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
        const prefix = entries.find((item) =>
          id.startsWith(`${item.fort.prefix}-`),
        )?.fort.prefix;
        if (prefix && validUnknownId(id, prefix))
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
  // A bare suffix is meaningful only in the speaking fort's own state.  Do
  // not search every loaded fort: identical suffixes are common across forts.
  if (ownState?.fort?.prefix && ownState?.byId) {
    const bareFacts = new Map();
    for (const bead of ownState.byId.values()) {
      const prefix = `${ownState.fort.prefix}-`;
      if (!String(bead.id).startsWith(prefix)) continue;
      const suffix = bead.id.slice(prefix.length);
      if (!/^[a-z0-9]{2,8}(?:\.\d+)*$/.test(suffix)) continue;
      bareFacts.set(suffix, bead);
    }
    for (const highlight of highlights) {
      // A suffix token permits ordinary prose punctuation and hyphens after it.
      // The optional child suffix is consumed as one token, so `hird0.1` can
      // resolve only to its child and never to `hird0`.
      for (const match of String(highlight.text).matchAll(
        /(?<![A-Za-z0-9])[a-z0-9]{2,8}(?:\.\d+)*(?![A-Za-z0-9]|\.\d)/g,
      )) {
        const bead = bareFacts.get(match[0]);
        if (!bead || seen.has(bead.id)) continue;
        seen.add(bead.id);
        facts.push({
          id: bead.id,
          fort: ownState.fort.key,
          title: bead.title,
          status: bead.status,
          assignee: bead.assignee ?? null,
          labels: bead.labels ?? [],
        });
      }
    }
  }
  return facts;
}

function inWindow(value, start, end) {
  const timestamp = dateValue(value);
  return timestamp !== null && timestamp > start && timestamp <= end;
}

export function windowCounts(entry, windowStart, windowEnd, options = {}) {
  if (!entry?.byId || !entry.fort)
    throw new Error("entry with fort and byId is required");
  const fileSystem = options.fileSystem ?? fs;
  const now = options.now ?? (() => Date.now());
  const start = dateValue(windowStart);
  const end = dateValue(windowEnd);
  if (start === null || end === null)
    throw new Error("window bounds must be valid timestamps");
  const values = [...entry.byId.values()];
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
  if (!Array.isArray(entry.events?.events))
    throw new Error("entry.events.events is required");
  const context = graphContext(
    values,
    entry.events.events,
    entry.fleet?.workers ?? [],
    now(),
    entry.fort.waitingLabels,
    entry.fort.whoseMove,
  );
  for (const bead of values)
    if (needsYou(bead, context)) result.waitingOnOverseer.push(bead.id);
  const directory = path.join(entry.fort.repo, "fort/events");
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
        result.halts.push({
          target: event.target ?? null,
          reason: event.detail ?? "",
        });
      if (event.category === "review.verdict")
        result.wardenVerdicts.push({
          id: event.target ?? null,
          verdict: event.payload?.verdict ?? null,
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

export function summaryFactsBlock(entry, counts) {
  const byId = entry?.byId;
  if (!byId) throw new Error("entry.byId is required");
  const beadFact = (id) => {
    const bead = byId.get(id);
    return bead ? { id, title: bead.title } : null;
  };
  const escalations = [];
  const seen = new Set();
  for (const verdict of counts.wardenVerdicts ?? []) {
    if (verdict.verdict !== "ESCALATE" || !verdict.id || seen.has(verdict.id))
      continue;
    const fact = beadFact(verdict.id);
    seen.add(verdict.id);
    escalations.push(fact ?? { id: verdict.id, title: null });
  }
  return {
    waitingOnOverseer: (counts.waitingOnOverseer ?? [])
      .map(beadFact)
      .filter(Boolean),
    escalations,
    counts: {
      closed: counts.closed ?? 0,
      filed: counts.filed ?? 0,
      merged: counts.merged ?? 0,
      halts: Array.isArray(counts.halts) ? counts.halts.length : 0,
      verdicts: Array.isArray(counts.wardenVerdicts)
        ? counts.wardenVerdicts.length
        : 0,
    },
  };
}

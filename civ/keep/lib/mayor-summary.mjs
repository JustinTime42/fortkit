// Local-model Mayor-summary generation and private run-record storage.
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const MAYOR_SUMMARY_MODEL = "greenlab-qwen2.5:7b-instruct-32k";
export const MAYOR_SUMMARY_CONTEXT = 32768;
export const MAYOR_SUMMARY_RESERVE = 2048;
const here = path.dirname(fileURLToPath(import.meta.url));
const promptPath = path.join(here, "../prompts/mayor-summary.md");

function iso(timestamp) {
  return new Date(timestamp).toISOString();
}
function estimate(value) {
  return Math.ceil(value.length / 3);
}
function safeKey(value) {
  if (!/^[a-z0-9][a-z0-9-]*$/i.test(value ?? ""))
    throw new Error("fort key is invalid");
  return value;
}
export function summaryDirectory(stateHome, fort) {
  return path.join(stateHome, "civ-keep", "summaries", safeKey(fort));
}
function writePrivate(fileSystem, file, value) {
  fileSystem.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  fileSystem.chmodSync(path.dirname(file), 0o700);
  const temporary = `${file}.${process.pid}.${Date.now()}.tmp`;
  fileSystem.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, {
    mode: 0o600,
  });
  fileSystem.chmodSync(temporary, 0o600);
  fileSystem.renameSync(temporary, file);
  fileSystem.chmodSync(file, 0o600);
}
export function readSummaryReadMark(stateHome, fort, options = {}) {
  const fileSystem = options.fileSystem ?? fs;
  try {
    const mark = JSON.parse(
      fileSystem.readFileSync(
        path.join(summaryDirectory(stateHome, fort), "read-mark.json"),
        "utf8",
      ),
    );
    if (
      typeof mark.markedAt !== "string" ||
      typeof mark.upTo !== "string" ||
      !Number.isFinite(Date.parse(mark.markedAt)) ||
      !Number.isFinite(Date.parse(mark.upTo))
    )
      return null;
    return { markedAt: mark.markedAt, upTo: mark.upTo };
  } catch {
    return null;
  }
}
export function writeSummaryReadMark(stateHome, fort, mark, options = {}) {
  const fileSystem = options.fileSystem ?? fs;
  writePrivate(
    fileSystem,
    path.join(summaryDirectory(stateHome, fort), "read-mark.json"),
    mark,
  );
  return mark;
}
export function hasSuccessfulSummaryWindowEnd(
  stateHome,
  fort,
  upTo,
  options = {},
) {
  const fileSystem = options.fileSystem ?? fs;
  const runs = path.join(summaryDirectory(stateHome, fort), "runs");
  try {
    return fileSystem.readdirSync(runs).some((name) => {
      if (!name.endsWith(".json")) return false;
      try {
        const record = JSON.parse(
          fileSystem.readFileSync(path.join(runs, name), "utf8"),
        );
        return record.status === "success" && record.windowEnd === upTo;
      } catch {
        return false;
      }
    });
  } catch {
    return false;
  }
}
export function readLatestSummary(stateHome, fort, options = {}) {
  const fileSystem = options.fileSystem ?? fs;
  try {
    return JSON.parse(
      fileSystem.readFileSync(
        path.join(summaryDirectory(stateHome, fort), "latest.json"),
        "utf8",
      ),
    );
  } catch {
    return null;
  }
}
export function readLastFailure(stateHome, fort, options = {}) {
  const fileSystem = options.fileSystem ?? fs;
  const runs = path.join(summaryDirectory(stateHome, fort), "runs");
  try {
    const names = fileSystem
      .readdirSync(runs)
      .filter((name) => name.endsWith(".json"))
      .sort()
      .reverse();
    for (const name of names) {
      let record;
      try {
        record = JSON.parse(
          fileSystem.readFileSync(path.join(runs, name), "utf8"),
        );
      } catch {
        return { reason: "unreadable run record" };
      }
      if (record.status === "success") return null;
      if (record.status === "failed") return record;
    }
    return null;
  } catch {
    return null;
  }
}
function promptAndHash(fileSystem) {
  const prompt = fileSystem.readFileSync(promptPath, "utf8");
  return { prompt, sha256: createHash("sha256").update(prompt).digest("hex") };
}
function factsBlock(input) {
  return `FACTS (authoritative JSON):\n${JSON.stringify({ beadFacts: input.beadFacts, factsBlock: input.factsBlock })}`;
}
function jsonData(label, value) {
  return `${label} (authoritative JSON data):\n${JSON.stringify(value)}`;
}
export function splitText(text, fits) {
  if (fits(text)) return [{ text, split: false }];
  const pieces = [];
  let remaining = text;
  while (remaining) {
    if (fits(remaining)) {
      pieces.push({ text: remaining, split: true });
      break;
    }
    let low = 1;
    let high = remaining.length;
    while (low < high) {
      const middle = Math.ceil((low + high) / 2);
      if (fits(remaining.slice(0, middle))) low = middle;
      else high = middle - 1;
    }
    let at = remaining.lastIndexOf("\n\n", low);
    if (at < Math.floor(low / 3)) at = remaining.lastIndexOf("\n", low);
    if (at < 1) at = low;
    pieces.push({ text: remaining.slice(0, at), split: true });
    remaining = remaining.slice(at).replace(/^\n+/, "");
  }
  return pieces;
}
function fitsRequest(prompt, message) {
  return (
    estimate(prompt + message) + MAYOR_SUMMARY_RESERVE <= MAYOR_SUMMARY_CONTEXT
  );
}
function messageRequest(input, chunk, multiple) {
  return `${factsBlock(input)}\n\n${multiple ? "Write notes, not a final summary.\n" : ""}${jsonData("MAYOR MESSAGES", chunk)}`;
}
function notesRequest(input, group, final) {
  return `${factsBlock(input)}\n\n${final ? "Write the final summary" : "Write compact notes for a later combine"}.\n${jsonData("CHUNK NOTES", group)}`;
}
function chunksFor(input, prompt) {
  if (!fitsRequest(prompt, messageRequest(input, "", true)))
    throw new Error("facts exceed model context");
  const splitMarker = "\n[message split]";
  const messages = input.highlights.flatMap((item) => {
    const text = `[${item.timestamp}]\n${item.text}`;
    return splitText(text, (part) =>
      fitsRequest(prompt, messageRequest(input, `${part}${splitMarker}`, true)),
    );
  });
  const chunks = [];
  let current = "";
  for (const item of messages) {
    const itemText = `${item.text}${item.split ? splitMarker : ""}`;
    const candidate = `${current ? `${current}\n\n` : ""}${itemText}`;
    if (
      current &&
      !fitsRequest(prompt, messageRequest(input, candidate, true))
    ) {
      chunks.push(current);
      current = "";
    }
    current += `${current ? "\n\n" : ""}${itemText}`;
  }
  if (current || !chunks.length) chunks.push(current);
  return chunks;
}
export function packNotes(notes, input, prompt) {
  if (!fitsRequest(prompt, notesRequest(input, "", false)))
    throw new Error("facts exceed model context");
  const pieces = notes.flatMap((note, index) =>
    splitText(JSON.stringify({ chunk: index + 1, notes: note }), (part) =>
      fitsRequest(prompt, notesRequest(input, part, false)),
    ),
  );
  const groups = [];
  let current = "";
  for (const piece of pieces) {
    const candidate = `${current ? `${current}\n\n` : ""}${piece.text}`;
    if (
      current &&
      !fitsRequest(prompt, notesRequest(input, candidate, false))
    ) {
      groups.push(current);
      current = "";
    }
    current += `${current ? "\n\n" : ""}${piece.text}`;
  }
  if (current) groups.push(current);
  return groups;
}
export async function ask(fetchImpl, prompt, messages) {
  const chars = prompt.length + messages.length;
  const estTokens = estimate(prompt + messages);
  if (estTokens + MAYOR_SUMMARY_RESERVE > MAYOR_SUMMARY_CONTEXT)
    throw new Error(`request exceeds context (${estTokens} estimated tokens)`);
  const response = await fetchImpl("http://127.0.0.1:11434/api/chat", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model: MAYOR_SUMMARY_MODEL,
      stream: false,
      truncate: false,
      options: { num_ctx: MAYOR_SUMMARY_CONTEXT, num_predict: 2048 },
      messages: [
        { role: "system", content: prompt },
        { role: "user", content: messages },
      ],
    }),
    signal: AbortSignal.timeout(300000),
  });
  if (!response.ok) throw new Error(`Ollama returned HTTP ${response.status}`);
  const body = await response.json();
  if (
    typeof body.prompt_eval_count !== "number" ||
    body.prompt_eval_count >= MAYOR_SUMMARY_CONTEXT - MAYOR_SUMMARY_RESERVE
  )
    throw new Error("Ollama response may have truncated the prompt");
  if (body.done_reason === "length")
    throw new Error("Ollama response was truncated by output length");
  const text = body.message?.content;
  if (typeof text !== "string" || !text.trim())
    throw new Error("Ollama returned no summary text");
  return {
    chars,
    estTokens,
    promptEvalCount: body.prompt_eval_count,
    notes: text,
  };
}
export function unverifiedNumbers(summary, facts) {
  const { highlights, ...otherFacts } = facts ?? {};
  // Highlight timestamps are transport metadata, not facts supplied to the model.
  const suppliedFacts = {
    ...otherFacts,
    highlights: Array.isArray(highlights)
      ? highlights.map((highlight) => highlight?.text ?? "")
      : highlights,
  };
  const supplied = new Set(JSON.stringify(suppliedFacts).match(/\d+/g) ?? []);
  const protectedRanges = [];
  const protectedPattern =
    /\b\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?Z?)?\b|\b\d{1,2}:\d{2}(?::\d{2})?\b/g;
  for (const match of summary.matchAll(protectedPattern))
    protectedRanges.push([match.index, (match.index ?? 0) + match[0].length]);
  const unverified = [];
  for (const match of summary.matchAll(/\d+/g)) {
    const index = match.index ?? 0;
    if (protectedRanges.some(([start, end]) => index >= start && index < end))
      continue;
    // Markdown-style list markers are structure, not model-supplied facts.
    const lineStart = summary.lastIndexOf("\n", index - 1) + 1;
    const listMarker = /^\s*\d+[.)]\s/.exec(summary.slice(lineStart));
    if (listMarker && index === lineStart + (listMarker[0].search(/\d/) ?? 0))
      continue;
    if (!supplied.has(match[0])) unverified.push(match[0]);
  }
  return unverified;
}
export async function summariseMayor(input, options = {}) {
  const fileSystem = options.fileSystem ?? fs;
  const fetchImpl = options.fetch ?? globalThis.fetch;
  const now = options.now ?? (() => Date.now());
  const started = now();
  const at = iso(started);
  let prompt;
  let directory;
  const record = {
    fort: input.fort.key,
    status: "failed",
    sessionId: input.session?.sessionId ?? null,
    transcriptPath: input.transcriptPath ?? null,
    windowStart: input.windowStart,
    windowEnd: input.windowEnd,
    firstRun: Boolean(input.firstRun),
    windowReason: input.windowReason ?? null,
    fingerprint: input.fingerprint ?? null,
    model: MAYOR_SUMMARY_MODEL,
    promptSha256: null,
    generatedAt: at,
    highlights: input.highlights,
    beadFacts: input.beadFacts,
    counts: input.counts,
    factsBlock: input.factsBlock,
    chunks: [],
    malformedLines: input.malformedLines ?? 0,
    keepRefreshedAt: input.keepRefreshedAt ?? null,
  };
  try {
    directory = summaryDirectory(options.stateHome, input.fort.key);
    const promptAndDigest = promptAndHash(fileSystem);
    prompt = promptAndDigest.prompt;
    record.promptSha256 = promptAndDigest.sha256;
    if (typeof fetchImpl !== "function") throw new Error("fetch is required");
    const chunks = chunksFor(input, prompt);
    const notes = [];
    for (const chunk of chunks) {
      const note = await ask(
        fetchImpl,
        prompt,
        messageRequest(input, chunk, chunks.length > 1),
      );
      notes.push(note);
      record.chunks.push(note);
    }
    let currentNotes = notes.map((note) => note.notes);
    while (currentNotes.length > 1) {
      const groups = packNotes(currentNotes, input, prompt);
      if (groups.length >= currentNotes.length)
        throw new Error("combine round did not reduce note count");
      const next = [];
      for (const group of groups) {
        const final = groups.length === 1;
        const response = await ask(
          fetchImpl,
          prompt,
          notesRequest(input, group, final),
        );
        record.chunks.push(response);
        next.push(response.notes);
      }
      currentNotes = next;
    }
    const summary = currentNotes[0];
    record.summary = summary;
    record.unverifiedNumbers = unverifiedNumbers(summary, {
      beadFacts: input.beadFacts,
      factsBlock: input.factsBlock,
      highlights: input.highlights,
    });
    record.durationMs = now() - started;
    const successRecord = { ...record, status: "success" };
    writePrivate(
      fileSystem,
      path.join(directory, "latest.json"),
      successRecord,
    );
    writePrivate(
      fileSystem,
      path.join(directory, "runs", `${at}.json`),
      successRecord,
    );
    record.status = "success";
    return record;
  } catch (error) {
    record.reason = String(error?.message ?? error);
    record.durationMs = now() - started;
    if (directory) {
      try {
        writePrivate(
          fileSystem,
          path.join(directory, "runs", `${at}.json`),
          record,
        );
      } catch (writeError) {
        // The original error explains the failed generation; a second storage
        // failure must not replace it at the caller.
        (options.log ?? console.error)(
          "summary failed-run write failed",
          writeError,
        );
      }
    }
    throw error;
  }
}

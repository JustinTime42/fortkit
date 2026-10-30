// Local-model Mayor-summary generation and private run-record storage.
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const MAYOR_SUMMARY_MODEL = "greenlab-qwen2.5:7b-instruct-32k";
export const MAYOR_SUMMARY_CONTEXT = 32768;
export const MAYOR_SUMMARY_RESERVE = 2048;
export const MAYOR_SUMMARY_PASS_INSTRUCTIONS = Object.freeze({
  background:
    "Write compact background notes for a later final pass. These messages are EARLIER state that later messages may have changed.",
  combine:
    "Combine these background notes into fewer compact notes for a later final pass. They describe EARLIER state that later messages may have changed.",
  final:
    "Write the final summary. Describe the state at the END of the window. A later message supersedes an earlier one. A proposal, recommendation, or question is NOT done or decided unless a later message says it was done or answered. A question the Overseer answered is resolved and must be reported as decided, with his actual answer when supplied, never as waiting on him. Attribute each statement to its actual speaker (Mayor, Overseer, Warden, or Forge) as the messages name them.",
});
const BACKGROUND_NOTES_RESERVE_CHARS = MAYOR_SUMMARY_RESERVE * 3;
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
function promptAndHash(fileSystem, file = promptPath) {
  const prompt = fileSystem.readFileSync(file, "utf8");
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
function backgroundRequest(input, chunk, instructions) {
  return `${factsBlock(input)}\n\n${instructions.background}\n${jsonData("EARLIER CONVERSATION", chunk)}`;
}
function notesRequest(input, group, instructions) {
  return `${factsBlock(input)}\n\n${instructions.combine}\n${jsonData("BACKGROUND NOTES", group)}`;
}
function finalRequest(input, backgroundNotes, recentMessages, instructions) {
  return `${factsBlock(input)}\n\n${instructions.final}\n${jsonData("BACKGROUND NOTES (EARLIER AND POSSIBLY SUPERSEDED)", backgroundNotes)}\n\n${jsonData("RECENT CONVERSATION (FULL, IN TIME ORDER)", recentMessages)}`;
}
function chunksFor(messages, input, prompt, instructions) {
  if (!fitsRequest(prompt, backgroundRequest(input, [], instructions)))
    throw new Error("facts exceed model context");
  const splitMarker = "\n[message split]";
  const pieces = messages.flatMap((item) => {
    const text = JSON.stringify(item);
    return splitText(text, (part) =>
      fitsRequest(
        prompt,
        backgroundRequest(input, `${part}${splitMarker}`, instructions),
      ),
    );
  });
  const chunks = [];
  let current = "";
  for (const item of pieces) {
    const itemText = `${item.text}${item.split ? splitMarker : ""}`;
    const candidate = `${current ? `${current}\n\n` : ""}${itemText}`;
    if (
      current &&
      !fitsRequest(prompt, backgroundRequest(input, candidate, instructions))
    ) {
      chunks.push(current);
      current = "";
    }
    current += `${current ? "\n\n" : ""}${itemText}`;
  }
  if (current || !chunks.length) chunks.push(current);
  return chunks;
}
export function packNotes(
  notes,
  input,
  prompt,
  instructions = MAYOR_SUMMARY_PASS_INSTRUCTIONS,
) {
  if (!fitsRequest(prompt, notesRequest(input, "", instructions)))
    throw new Error("facts exceed model context");
  const pieces = notes.flatMap((note, index) =>
    splitText(JSON.stringify({ chunk: index + 1, notes: note }), (part) =>
      fitsRequest(prompt, notesRequest(input, part, instructions)),
    ),
  );
  const groups = [];
  let current = "";
  for (const piece of pieces) {
    const candidate = `${current ? `${current}\n\n` : ""}${piece.text}`;
    if (
      current &&
      !fitsRequest(prompt, notesRequest(input, candidate, instructions))
    ) {
      groups.push(current);
      current = "";
    }
    current += `${current ? "\n\n" : ""}${piece.text}`;
  }
  if (current) groups.push(current);
  return groups;
}
export async function ask(fetchImpl, prompt, messages, experiment = {}) {
  const chars = prompt.length + messages.length;
  const estTokens = estimate(prompt + messages);
  if (estTokens + MAYOR_SUMMARY_RESERVE > MAYOR_SUMMARY_CONTEXT)
    throw new Error(`request exceeds context (${estTokens} estimated tokens)`);
  const options = { num_ctx: MAYOR_SUMMARY_CONTEXT, num_predict: 2048 };
  if (experiment.temperature !== undefined)
    options.temperature = experiment.temperature;
  const response = await fetchImpl("http://127.0.0.1:11434/api/chat", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model: experiment.model ?? MAYOR_SUMMARY_MODEL,
      stream: false,
      truncate: false,
      options,
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
async function summariseBackground(
  messages,
  input,
  prompt,
  fetchImpl,
  record,
  attempt,
  experiment,
) {
  if (!messages.length) return [];
  const chunks = chunksFor(
    messages,
    input,
    prompt,
    experiment.passInstructions,
  );
  const notes = [];
  for (const chunk of chunks) {
    const response = await ask(
      fetchImpl,
      prompt,
      backgroundRequest(input, chunk, experiment.passInstructions),
      experiment,
    );
    notes.push(response.notes);
    record.chunks.push({ ...response, phase: "background", attempt });
  }
  let current = notes;
  while (current.length > 1) {
    const groups = packNotes(
      current,
      input,
      prompt,
      experiment.passInstructions,
    );
    if (groups.length >= current.length)
      throw new Error("combine round did not reduce note count");
    const next = [];
    for (const group of groups) {
      const response = await ask(
        fetchImpl,
        prompt,
        notesRequest(input, group, experiment.passInstructions),
        experiment,
      );
      record.chunks.push({ ...response, phase: "background-combine", attempt });
      next.push(response.notes);
    }
    current = next;
  }
  return current;
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
  const experiment = {
    model: options.model ?? MAYOR_SUMMARY_MODEL,
    temperature: options.temperature,
    passInstructions: {
      ...MAYOR_SUMMARY_PASS_INSTRUCTIONS,
      ...options.passInstructions,
    },
  };
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
    model: experiment.model,
    temperature: experiment.temperature ?? null,
    promptSha256: null,
    promptText: null,
    passInstructions: experiment.passInstructions,
    generatedAt: at,
    highlights: input.highlights,
    beadFacts: input.beadFacts,
    counts: input.counts,
    factsBlock: input.factsBlock,
    recentBoundary: null,
    recentMessages: [],
    backgroundMessages: [],
    backgroundNotes: [],
    chunks: [],
    malformedLines: input.malformedLines ?? 0,
    keepRefreshedAt: input.keepRefreshedAt ?? null,
    beadExport: input.beadExport ?? null,
  };
  try {
    if (options.persist !== false)
      directory = summaryDirectory(options.stateHome, input.fort.key);
    const promptAndDigest = promptAndHash(fileSystem, options.promptPath);
    prompt = promptAndDigest.prompt;
    record.promptSha256 = promptAndDigest.sha256;
    record.promptText = prompt;
    if (typeof fetchImpl !== "function") throw new Error("fetch is required");
    const twoHoursAgo = Date.parse(input.windowEnd) - 2 * 60 * 60 * 1000;
    let split = input.highlights.findIndex(
      (message) => Date.parse(message.timestamp) >= twoHoursAgo,
    );
    if (split < 0) split = input.highlights.length;
    let backgroundMessages = input.highlights.slice(0, split);
    let recentMessages = input.highlights.slice(split);
    const reservedNotes = ["x".repeat(BACKGROUND_NOTES_RESERVE_CHARS)];
    while (
      recentMessages.length &&
      !fitsRequest(
        prompt,
        finalRequest(
          input,
          reservedNotes,
          recentMessages,
          experiment.passInstructions,
        ),
      )
    ) {
      backgroundMessages.push(recentMessages[0]);
      recentMessages = recentMessages.slice(1);
    }
    let attempt = 1;
    let backgroundNotes = await summariseBackground(
      backgroundMessages,
      input,
      prompt,
      fetchImpl,
      record,
      attempt,
      experiment,
    );
    while (
      recentMessages.length &&
      !fitsRequest(
        prompt,
        finalRequest(
          input,
          backgroundNotes,
          recentMessages,
          experiment.passInstructions,
        ),
      )
    ) {
      const firstChunk = record.chunks.length;
      let move = 1;
      while (
        move < recentMessages.length &&
        !fitsRequest(
          prompt,
          finalRequest(
            input,
            backgroundNotes,
            recentMessages.slice(move),
            experiment.passInstructions,
          ),
        )
      )
        move += 1;
      for (const chunk of record.chunks)
        if (chunk.attempt === attempt) chunk.discarded = true;
      backgroundMessages = [
        ...backgroundMessages,
        ...recentMessages.slice(0, move),
      ];
      recentMessages = recentMessages.slice(move);
      attempt += 1;
      backgroundNotes = await summariseBackground(
        backgroundMessages,
        input,
        prompt,
        fetchImpl,
        record,
        attempt,
        experiment,
      );
      if (record.chunks.length === firstChunk)
        throw new Error("background retry produced no run-record chunks");
    }
    const request = finalRequest(
      input,
      backgroundNotes,
      recentMessages,
      experiment.passInstructions,
    );
    if (!fitsRequest(prompt, request))
      throw new Error("facts and background notes exceed model context");
    record.backgroundMessages = backgroundMessages;
    record.recentMessages = recentMessages;
    record.backgroundNotes = backgroundNotes;
    record.recentBoundary = recentMessages[0]?.timestamp ?? input.windowEnd;
    const final = await ask(fetchImpl, prompt, request, experiment);
    record.chunks.push({ ...final, phase: "final", attempt });
    const summary = final.notes;
    record.summary = summary;
    record.unverifiedNumbers = unverifiedNumbers(summary, {
      beadFacts: input.beadFacts,
      factsBlock: input.factsBlock,
      highlights: input.highlights,
    });
    record.durationMs = now() - started;
    const successRecord = { ...record, status: "success" };
    if (options.persist !== false) {
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
    }
    record.status = "success";
    return record;
  } catch (error) {
    record.reason = String(error?.message ?? error);
    record.durationMs = now() - started;
    if (directory && options.persist !== false) {
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

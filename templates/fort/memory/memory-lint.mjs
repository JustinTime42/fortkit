#!/usr/bin/env node
import { readdir, readFile } from "node:fs/promises";
import { basename, join } from "node:path";

const root = process.argv[2] ?? process.cwd();
const factsDirectory = join(root, "fort", "memory", "facts");
const required = ["source", "declared-by", "date", "origin"];
const coreFactOverheadLines = 12;
const coreFactBudget = 30;
const coreLineBudget = 300;
const failures = [];

function parseFact(text) {
  const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/u.exec(text);
  if (match === null) return null;
  const frontmatter = Object.fromEntries(
    [...match[1].matchAll(/^([a-z-]+):\s*(.*)$/gmu)].map(([, key, value]) => [
      key,
      value === "null" ? null : value.replace(/^"|"$/gu, ""),
    ]),
  );
  const provenance =
    /^provenance:\s*\r?\n((?:\s+.+\r?\n?)+)/mu.exec(match[1])?.[1] ?? "";
  for (const [, key, value] of provenance.matchAll(/^\s+([a-z-]+):\s*(.*)$/gmu))
    frontmatter[key] = value.replace(/^"|"$/gu, "");
  const scope = /^scope:\s*\r?\n((?:\s+.+\r?\n?)+)/mu.exec(match[1])?.[1] ?? "";
  return { frontmatter, scope, body: match[2].trim() };
}

function scopeSeats(scope) {
  const match = /^\s+seats:\s*\[([^\]]*)\]\s*$/mu.exec(scope);
  if (match === null) return [];
  return match[1]
    .split(",")
    .map((seat) => seat.trim())
    .filter(Boolean);
}

let files = [];
try {
  files = (await readdir(factsDirectory))
    .filter((file) => file.endsWith(".md"))
    .sort();
} catch {
  failures.push("fort/memory/facts is unreadable");
}
let seats = [];
try {
  seats = (await readdir(join(root, "fort", "seats")))
    .filter((file) => file.endsWith(".md"))
    .map((file) => basename(file, ".md"))
    .sort();
} catch {
  // A partial fixture may have facts before its seat directory is founded.
}
const coreBySeat = new Map(seats.map((seat) => [seat, { facts: 0, lines: 0 }]));
let sharedCoreFacts = 0;
let sharedCoreLines = 0;
const supersededFactKeys = [];
const activeCoreFactKeys = [];
for (const file of files) {
  const path = join(factsDirectory, file);
  const parsed = parseFact(await readFile(path, "utf8"));
  if (parsed === null) {
    failures.push(`${path}: missing YAML frontmatter`);
    continue;
  }
  const { frontmatter, scope, body } = parsed;
  const key = basename(file, ".md");
  if (frontmatter.key !== key)
    failures.push(`${path}: key must equal filename`);
  if (!["active", "superseded"].includes(frontmatter.status))
    failures.push(`${path}: invalid status`);
  if (!["core", "on-demand"].includes(frontmatter.tier))
    failures.push(`${path}: invalid tier`);
  if (scope.trim() === "") failures.push(`${path}: scope is required`);
  if (body === "") failures.push(`${path}: body is required`);
  for (const field of required)
    if (!frontmatter[field])
      failures.push(`${path}: provenance.${field} is required`);
  if (!["trusted", "untrusted"].includes(frontmatter.origin))
    failures.push(`${path}: invalid provenance.origin`);
  if (frontmatter.origin === "untrusted" && frontmatter.tier === "core")
    failures.push(`${path}: untrusted facts cannot be core`);
  if (frontmatter.status === "superseded" && !frontmatter["superseded-by"])
    failures.push(`${path}: superseded facts need superseded-by`);
  if (frontmatter.status === "superseded") supersededFactKeys.push(key);
  if (
    frontmatter["superseded-by"] &&
    !files.includes(`${frontmatter["superseded-by"]}.md`)
  )
    failures.push(`${path}: superseded-by does not resolve`);
  if (frontmatter.tier === "core" && frontmatter.status === "active")
    activeCoreFactKeys.push(key);
  if (frontmatter.tier === "core") {
    const factSeats = scopeSeats(scope);
    const factLines = body.split(/\r?\n/u).length + coreFactOverheadLines;
    const shared = factSeats.includes("all");
    if (shared) {
      sharedCoreFacts += 1;
      sharedCoreLines += factLines;
    }
    for (const seat of factSeats) {
      if (seat === "all" || shared) continue;
      if (!coreBySeat.has(seat)) coreBySeat.set(seat, { facts: 0, lines: 0 });
      const total = coreBySeat.get(seat);
      total.facts += 1;
      total.lines += factLines;
    }
  }
}
const retiredReferences = ["fort/remember.md", ...supersededFactKeys];
const selfReferentialRetirementGuards = new Set([
  "scripts/memory-lint.mjs",
  "templates/fort/memory/memory-lint.mjs",
]);
const pointerStubWriter = "bin/fort-init";

async function filesBelow(directory, predicate) {
  let entries = [];
  try {
    entries = await readdir(join(root, directory), { withFileTypes: true });
  } catch {
    return [];
  }
  const files = [];
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...(await filesBelow(path, predicate)));
    else if (entry.isFile() && predicate(path)) files.push(path);
  }
  return files;
}

function isHistoricalCharterReference(path, text, referenceIndex) {
  if (path !== "fort/charter.md") return false;
  const paragraphStart = text.lastIndexOf("\n\n", referenceIndex) + 2;
  const paragraphEnd = text.indexOf("\n\n", referenceIndex);
  const paragraph = text.slice(
    paragraphStart,
    paragraphEnd === -1 ? text.length : paragraphEnd,
  );
  return (
    /\b(amended|historical|migrat(?:ed|ion)|retir(?:ed|ement))\b/iu.test(
      paragraph,
    ) && !/\b(read|consult|open|use|follow)\b/iu.test(paragraph)
  );
}

const retiredReferenceFiles = [
  "AGENTS.md",
  "CLAUDE.md",
  "fort/charter.md",
  ...(await filesBelow("fort/seats", (path) => path.endsWith(".md"))),
  ...(await filesBelow("templates", () => true)),
  ...(await filesBelow("fort/scripts", (path) =>
    /^fort\/scripts\/[^/]+\.sh$/u.test(path),
  )),
  ...(await filesBelow("bin", () => true)),
];
for (const instructionFile of retiredReferenceFiles) {
  if (
    selfReferentialRetirementGuards.has(instructionFile) ||
    instructionFile === pointerStubWriter
  )
    continue;
  const path = join(root, instructionFile);
  let text;
  try {
    text = await readFile(path, "utf8");
  } catch {
    continue;
  }
  for (const reference of retiredReferences) {
    let referenceIndex = text.indexOf(reference);
    let liveReference = false;
    while (referenceIndex !== -1) {
      if (
        !isHistoricalCharterReference(instructionFile, text, referenceIndex)
      ) {
        liveReference = true;
        break;
      }
      referenceIndex = text.indexOf(
        reference,
        referenceIndex + reference.length,
      );
    }
    if (liveReference)
      failures.push(`${path}: references retired memory item ${reference}`);
  }
}
// fortkit-c1kj — THE MEMORY STALENESS GATE.
//
// Nothing regenerated fort/memory/current.md and no verifier detected it as
// stale, so for a day the distilled view served a SUPERSEDED core fact — the
// cycle-7 write boundaries — to every seat at session start, while the ledger
// and the seat file had both been corrected (fortkit-1gz3). It is the
// widest-read of the three places that record lived.
//
// THE GATE KEYS ON IDENTITY, NEVER ON PROSE. Two earlier shapes were rejected
// with a measurement each: regenerating and diffing the whole file goes red on
// ordinary bead traffic (a regeneration after fifteen closures produced a diff
// whose only content was "232 -> 228 open beads"), and pinning a substring of
// the rendering goes red on a benign reflow that changes no truth. Both turn
// the correct action into a red build and get disabled within a day. What is
// asserted here instead is set equality between the facts the ledger says
// belong in the view and the fact paths the view actually links, which is
// immune to reflow, to wording, and to bead churn.
//
// scripts/consolidate-memory.mjs renders exactly `status: active` + `tier:
// core` and links each as `fort/memory/facts/<key>.md`, so that path IS the
// identity anchor. Both directions are checked, and the second is why the
// converse was safe to assert: the bead warned that "every active fact
// renders" would be wrong, and it would be — `tier: on-demand` facts correctly
// do not render — but "every active CORE fact renders" is precisely the
// generator's own filter.
const viewPath = join(root, "fort", "memory", "current.md");
let view = null;
try {
  view = await readFile(viewPath, "utf8");
} catch {
  // A fort mid-founding may have a ledger before its first generated view.
  // SKIPPING IS ANNOUNCED, NEVER SILENT: a checker that checks nothing must
  // never report success without saying so.
  console.log(
    "distilled view: fort/memory/current.md absent — staleness gate SKIPPED (generate it with consolidate-memory.mjs)",
  );
}
if (view !== null) {
  const coreHeading = "## Core facts";
  const headingIndex = view.indexOf(coreHeading);
  if (headingIndex === -1)
    failures.push(
      `${viewPath}: no "${coreHeading}" section — the view is not in the shape consolidate-memory.mjs generates, so the staleness gate cannot read it`,
    );
  else {
    const sectionStart = headingIndex + coreHeading.length;
    const nextHeading = view.indexOf("\n## ", sectionStart);
    const section = view.slice(
      sectionStart,
      nextHeading === -1 ? view.length : nextHeading,
    );
    const rendered = new Set(
      [...section.matchAll(/fort\/memory\/facts\/([a-z0-9-]+)\.md/gu)].map(
        ([, key]) => key,
      ),
    );
    console.log(
      `distilled view: ${rendered.size} core facts rendered / ${activeCoreFactKeys.length} active in the ledger`,
    );
    for (const key of supersededFactKeys)
      if (rendered.has(key))
        failures.push(
          `${viewPath}: renders SUPERSEDED fact '${key}' — the view is stale and every seat reads it at session start; regenerate with consolidate-memory.mjs`,
        );
    for (const key of activeCoreFactKeys)
      if (!rendered.has(key))
        failures.push(
          `${viewPath}: omits ACTIVE core fact '${key}' — the view is stale; regenerate with consolidate-memory.mjs`,
        );
  }
}
console.log(
  `core shared floor [all]: ${sharedCoreFacts} facts / ${sharedCoreLines} lines`,
);
for (const [seat, ownCore] of coreBySeat) {
  const facts = ownCore.facts + sharedCoreFacts;
  const lines = ownCore.lines + sharedCoreLines;
  console.log(`core budget [${seat}]: ${facts} facts / ${lines} lines`);
  if (facts > coreFactBudget)
    failures.push(
      `core tier exceeds ${coreFactBudget} facts for seat ${seat} (${facts})`,
    );
  if (lines > coreLineBudget)
    failures.push(
      `core tier exceeds ${coreLineBudget} lines for seat ${seat} (${lines})`,
    );
}
if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
}

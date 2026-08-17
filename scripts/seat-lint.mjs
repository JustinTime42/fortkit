#!/usr/bin/env node
// fortkit-x508 — THE SEAT-FILE LINT. Three rules over fort/seats/*.md, run by the
// verifier in every session of every fort, plus one cross-check against the charter.
//
// WHY THIS IS NOT IN bin/fort-init, which is where fortkit-8rh and fortkit-fd2
// originally put it. The Overseer ruled 2026-08-14 that the factory grows a SEAT
// ROSTER ONLY — seats, no personhood — so at founding there is no name to collide,
// no citizen to inherit, and nothing for either bead to check. And fort-init runs
// ONCE per fort while roster edits happen forever afterward, at every moot, every
// reseating, every seat added. fortkit-8rh asked for the check "at fort founding AND
// at every roster edit"; the verifier is the instrument that delivers the second half.
//
// SKIPPING IS ANNOUNCED, NEVER SILENT, and zero seat files is a FAILURE rather than a
// pass. This fort has shipped an anti-vacuity harness wired into nothing
// (fortkit-52vf.12 finding 4) and a probe suite with no permitted control
// (fortkit-vhk.5.1 finding 8) in the same month; a checker that checks nothing must
// say so in the same breath it exits 0.
import { execFile } from "node:child_process";
import { readdir, readFile, realpath } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

const root = process.argv[2] ?? process.cwd();
const seatsDirectory = join(root, "fort", "seats");
// bin/fort-init:223 reads the registry the same way, FORT_REGISTRY first. Honouring
// the same variable is what lets a test — and a masked seat, for whom
// $HOME/.claude is kernel read-only — point this lint at a registry it can reach.
const registryPath =
  process.env.FORT_REGISTRY ?? join(homedir(), ".claude", "civilization.json");
const failures = [];
const warnings = [];
const notes = [];

// Distance 1 is a HARD REFUSE and distance 2 a WARN, WITHIN one fort's roster only.
// Overseer ruling on fortkit-8rh 2026-08-13, verbatim: "I agree with your
// recommendation. kind of similar names in different forts are fine." The collision
// that matters is the one inside a single roster, which is where kestra/kethra sat.
// Cross-fort near-collisions must NOT be refused: oswin (civ) and orin (Farlantern
// Forge) sit at distance 2 in a roster the civilization already runs today.
const COLLISION_REFUSE = 1;
const COLLISION_WARN = 2;

function editDistance(a, b) {
  let previous = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let i = 1; i <= a.length; i += 1) {
    const current = [i];
    for (let j = 1; j <= b.length; j += 1) {
      current[j] =
        a[i - 1] === b[j - 1]
          ? previous[j - 1]
          : 1 + Math.min(previous[j - 1], previous[j], current[j - 1]);
    }
    previous = current;
  }
  return previous[b.length];
}

// A seat file's identity region is exactly two lines, and the rules below read those
// two and nothing else. That bound IS the attribution exception the Overseer's ruling
// on rule 2 requires: a comment crediting another fort's seat for a finding is
// provenance, not inheritance (two live examples in
// templates/fort/scripts/lib/seat-sandbox.sh:127,455 credit Ilva Trueglass), and a
// whole-file scan would refuse them. The rule is about Held-by and Personality.
function parseSeat(text) {
  const heldByLine = /^\*\*Held by:.*$/mu.exec(text)?.[0] ?? null;
  const personalityLine = /^\*\*Personality\b.*$/mu.exec(text)?.[0] ?? null;
  let name = null;
  if (heldByLine !== null && !heldByLine.includes("{{")) {
    // Filled form: `**Held by: Emrith Cairnwright** (she/her, declared ...)`.
    name = /^\*\*Held by:\s*(.+?)\*\*/u.exec(heldByLine)?.[1]?.trim() ?? null;
  }
  return { heldByLine, personalityLine, name };
}

// Until fortkit-be4 gives actor ids an explicit field, the id is derived from the
// display name the way every actor id in this civilization already was: the first
// word, lowercased (emrith, kethra, ilva, saelin). be4's field lands here when it
// exists, and this function is the single place that has to change.
function actorId(name) {
  return name
    .split(/\s+/u)[0]
    .toLowerCase()
    .replace(/[^a-z]/gu, "");
}

async function seatFilesIn(directory) {
  const entries = await readdir(directory);
  return entries.filter((file) => file.endsWith(".md")).sort();
}

let seatFiles = [];
try {
  seatFiles = await seatFilesIn(seatsDirectory);
} catch {
  failures.push(`${seatsDirectory}: unreadable — the roster cannot be linted`);
}
if (failures.length === 0 && seatFiles.length === 0)
  failures.push(
    `${seatsDirectory}: contains no seat files, so this lint proved nothing`,
  );

const seats = [];
for (const file of seatFiles) {
  const path = join(seatsDirectory, file);
  const text = await readFile(path, "utf8");
  const parsed = parseSeat(text);
  if (parsed.heldByLine === null)
    failures.push(
      `${path}: no "**Held by:" line — the seat has no occupant record`,
    );
  seats.push({ ...parsed, path, text, seat: basename(file, ".md") });
}

// ---------------------------------------------------------------------------
// The registry decides two things: whether the moot has been held (rule 3) and who
// this civilization's other citizens are (rule 2). Both degrade to an ANNOUNCED skip
// rather than to a pass, because "I could not read the registry" and "the roster is
// clean" are different sentences and only one of them is evidence.
// ---------------------------------------------------------------------------
let registry = null;
try {
  registry = JSON.parse(await readFile(registryPath, "utf8"));
} catch {
  notes.push(
    `registry: ${registryPath} unreadable — rules 2 (foreign citizens) and 3 (placeholders) SKIPPED`,
  );
}

// THE REGISTRY LISTS CANONICAL CHECKOUTS, AND THE FORGE WORKS IN WORKTREES.
// scripts/verify-impl.sh:136-147 records this exact problem being solved once
// already, at real cost: a check that resolved paths against the CURRENT tree was
// false in every checkout but one, and it broke the Forge's whole lane because
// forge.sh runs the verifier from a worktree. Resolve the canonical checkout from
// git's common dir so a worktree run is placed in the registry rather than skipped.
// The Warden's scratch has no .git at all, so she falls through to the announced
// skip below — which is correct, not a regression: she reviews, she does not reseat.
async function canonicalCheckout(directory) {
  try {
    const { stdout } = await run("git", [
      "-C",
      directory,
      "rev-parse",
      "--git-common-dir",
    ]);
    const gitCommonDir = stdout.trim();
    if (gitCommonDir === "") return directory;
    const resolved = gitCommonDir.startsWith("/")
      ? gitCommonDir
      : join(directory, gitCommonDir);
    return await realpath(dirname(resolved)).catch(() => dirname(resolved));
  } catch {
    return directory;
  }
}

async function resolveRepo(path) {
  return await realpath(path).catch(() => path);
}

let entry = null;
// The RESOLVED path of this fort's own entry. Rule 2's self-skip compares against
// this rather than against the raw `fort.repo` string (Warden finding 5 on
// fortkit-x508): a registry listing one repo under two spellings — a symlink, a
// trailing slash — would otherwise make this fort foreign to itself and hard-fail
// every seat file against its own citizens.
let entryRepo = null;
if (registry !== null) {
  const own = await realpath(root).catch(() => root);
  const canonical = await canonicalCheckout(own);
  if (canonical !== own)
    notes.push(
      `registry: ${own} is a worktree of ${canonical}; placed in the registry by its canonical checkout`,
    );
  for (const fort of registry.forts ?? []) {
    const fortRepo = await resolveRepo(fort.repo);
    if (fortRepo === canonical || fort.repo === root) {
      entry = fort;
      entryRepo = fortRepo;
      break;
    }
  }
  if (entry === null)
    notes.push(
      `registry: ${canonical} is not listed in ${registryPath} — rules 2 and 3 SKIPPED (found ${(registry.forts ?? []).length} fort(s), none matching this repo)`,
    );
}

// ---------------------------------------------------------------------------
// RULE 1 — no actor-id collision within this fort.
// ---------------------------------------------------------------------------
const filled = seats.filter((seat) => seat.name !== null);
for (let i = 0; i < filled.length; i += 1)
  for (let j = i + 1; j < filled.length; j += 1) {
    const [a, b] = [filled[i], filled[j]];
    const distance = editDistance(actorId(a.name), actorId(b.name));
    const pair = `'${actorId(a.name)}' (${a.seat}) and '${actorId(b.name)}' (${b.seat})`;
    if (distance <= COLLISION_REFUSE)
      failures.push(
        `${seatsDirectory}: actor ids ${pair} are at edit distance ${distance} — a roster whose ids are one keystroke apart mis-attributes events, beads and verdicts (fortkit-8rh)`,
      );
    else if (distance <= COLLISION_WARN)
      warnings.push(
        `seat-lint: actor ids ${pair} are at edit distance ${distance} — legal, and worth knowing before the next reseating (fortkit-8rh)`,
      );
  }
console.log(
  `seat-lint: ${filled.length} occupied of ${seats.length} seat file(s); ${(filled.length * (filled.length - 1)) / 2} id pair(s) compared`,
);

// ---------------------------------------------------------------------------
// RULE 2 — no foreign citizen in this fort's Held-by or Personality lines.
// The identity half of standing order 12: architecture ports between forts, identity
// never does. The roster of "foreign" is built from the OTHER forts the registry
// lists, read from their own seat files — this fort does not carry a hardcoded list
// of other settlements' people, because such a list is exactly the artefact the
// standing order forbids and it would rot the moment a fort reseats.
// ---------------------------------------------------------------------------
if (entry !== null) {
  const foreign = [];
  for (const fort of registry.forts ?? []) {
    if ((await resolveRepo(fort.repo)) === entryRepo) continue;
    const directory = join(fort.repo, "fort", "seats");
    let files = [];
    try {
      files = await seatFilesIn(directory);
    } catch {
      notes.push(
        `foreign roster: ${directory} unreadable — ${fort.fort_name ?? fort.project}'s citizens are NOT covered by rule 2 this run`,
      );
      continue;
    }
    for (const file of files) {
      const parsed = parseSeat(await readFile(join(directory, file), "utf8"));
      if (parsed.name !== null)
        foreign.push({
          name: parsed.name,
          fort: fort.fort_name ?? fort.project,
        });
    }
  }
  console.log(
    `seat-lint: rule 2 checked against ${foreign.length} citizen(s) of ${(registry.forts ?? []).length - 1} other fort(s)`,
  );
  for (const seat of seats)
    for (const { name, fort } of foreign) {
      // Full name and bare given name both, on word boundaries: fortkit-qu46 was a
      // whole citizen erased by convergence, and a half-copied name is the same
      // failure caught earlier. KNOWN LATENT COST of the bare-given-name half
      // (Warden finding 6 on fortkit-x508): a foreign given name that is also an
      // ordinary English word would false-red a Personality line. Every name in the
      // civilization today is invented, so this is unrealised; if it ever fires,
      // narrow to the full name rather than deleting the rule.
      const given = name.split(/\s+/u)[0];
      const pattern = new RegExp(
        `\\b(${name.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&")}|${given.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&")})\\b`,
        "u",
      );
      for (const [field, line] of [
        ["Held by", seat.heldByLine],
        ["Personality", seat.personalityLine],
      ])
        if (line !== null && pattern.test(line))
          failures.push(
            `${seat.path}: its ${field} line names ${name}, a citizen of ${fort} — a fort must never inherit another settlement's citizen (standing order 12, fortkit-fd2)`,
          );
    }
}

// ---------------------------------------------------------------------------
// RULE 3 — no surviving placeholder once the moot has been held.
// THE PRE-MOOT SIGNAL ALREADY EXISTS AND DID NOT NEED INVENTING: bin/fort-init:226
// writes the new fort into the registry with "fort_name": null, and the moot is what
// sets it. So fort_name null means placeholders are LEGAL and a correctly founded
// fort passes this lint on day zero while still full of them; fort_name set means a
// surviving placeholder is a FAILURE.
// ---------------------------------------------------------------------------
if (entry !== null) {
  if (entry.fort_name === null || entry.fort_name === undefined) {
    console.log(
      `seat-lint: rule 3 EXEMPT — ${entry.project} has fort_name null in the registry, so the moot has not been held and placeholders are legal`,
    );
  } else {
    for (const seat of seats)
      if (seat.text.includes("{{"))
        failures.push(
          `${seat.path}: still carries a {{placeholder}} after the moot named this fort ${entry.fort_name} — the seat file promises an occupant it does not have`,
        );
    console.log(
      `seat-lint: rule 3 enforced — ${entry.fort_name} is named in the registry, so every seat file must be filled`,
    );
  }
}

// ---------------------------------------------------------------------------
// THE OPEN QUESTION IN fortkit-x508, ANSWERED IN ONE DIRECTION ONLY, AND THE
// DECLINED DIRECTION IS PRINTED SO NO READER MISTAKES IT FOR COVERAGE.
//
// The bead asks which of fort/seats/*.md and the charter's occupants line is
// authoritative when they disagree. Answer: the SEAT FILE is authoritative, and every
// name in one must appear in the charter. The converse — every citizen named in the
// charter must hold a seat — is NOT checked, because the charter's occupants text is
// prose and not a roster: this fort's own charter names three citizens in one
// sentence at line 72 and a fourth in a different paragraph two lines later. A lint
// that parses that reliably does not exist, and one that guesses goes red on a benign
// rewording. scripts/memory-lint.mjs:200-209 records the same judgement being made
// for the same reason after two measured false reds.
// ---------------------------------------------------------------------------
const charterPath = join(root, "fort", "charter.md");
let charter = null;
try {
  charter = await readFile(charterPath, "utf8");
} catch {
  notes.push(`${charterPath}: unreadable — the charter cross-check SKIPPED`);
}
if (charter !== null) {
  for (const seat of filled)
    if (!charter.includes(seat.name))
      failures.push(
        `${charterPath}: does not name ${seat.name}, who holds the ${seat.seat} seat — the charter and the roster disagree about who lives here`,
      );
  console.log(
    `seat-lint: charter cross-check — ${filled.length} occupant(s) checked against ${basename(charterPath)}; the converse direction (charter names a citizen with no seat) is deliberately NOT checked, see the comment in this file`,
  );
}

for (const note of notes) console.log(note);
for (const warning of warnings) console.warn(warning);
if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
}

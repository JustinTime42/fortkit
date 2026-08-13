#!/usr/bin/env node
import { execFile } from "node:child_process";
/**
 * Detect template drift without ever changing a registered fort.  The command
 * seams below deliberately keep tests (and --dry-run) away from bd and emit.sh.
 *
 * IDENTITY IS (fort, path) AND NOT THE CONTENT FINGERPRINT (fortkit-zvz2,
 * edict E7 of fortkit-52vf, 2026-08-12).  Keying a finding on the hashes of
 * both file contents identified a content STATE rather than a PROBLEM: every
 * edict that rewrote a compared file re-minted the key, the dedupe correctly
 * reported no match, and the same drift was filed again under a new identity
 * (measured: 29 -> 51 open Drift beads in one run, 16 exact duplicates).  The
 * fingerprint survives, demoted to a CHANGE DETECTOR on an already-filed
 * finding: same identity + same fingerprint suppresses, same identity +
 * different fingerprint appends a comment to the existing bead rather than
 * filing a second one.  Appending, never skipping, because a changed
 * fingerprint on a known file is real new information (standing order 7).
 *
 * ARCHITECTURE PORTS BETWEEN FORTS; IDENTITY NEVER DOES (standing order 12,
 * fortkit-k1pq, and edict E9 of fortkit-52vf, 2026-08-13).  The order is
 * applied PER HUNK and never per file, because the two mix inside one file:
 * `fort/scripts/mayor.sh` diverges from the template both by its Mayor's name
 * and by a push-gate hardening the template lacks.  Two consequences run
 * through everything below.  First, `normalizer()` erases identity from BOTH
 * sides before anything is compared, so a file that differs only by who sits
 * in it is not a finding at all.  Second, a finding's diff body is the
 * remaining hunks of the IDENTITY-NORMALIZED texts, so a seat acting on a
 * finding is reading architecture with the names already redacted and cannot
 * port a citizen by copying what it was shown.
 *
 * THAT SECOND GUARANTEE HOLDS IN ONE DIRECTION ONLY, and fortkit-qu46 is the
 * other one.  The body is `--- template / +++ fort`, so a seat converging a
 * fort TOWARD the template applies the MINUS side — and the template's side of
 * an identity hunk is generic office prose (`the Mayor`) where the fort's is a
 * placeholder (`{{ACTOR}}`).  Redaction stops a name being COPIED OUT; nothing
 * about it stops one being OVERWRITTEN.  Normalization cannot close this,
 * because `the Mayor` and `{{ACTOR}}` are both post-normalization text and
 * nothing in the token substitution marks one as the office and the other as
 * the person.  So such hunks are LABELLED — see `identitySuspect()` — and no
 * record built from this file claims a hunk is architecture when it may not
 * be.  Standing order 12 is applied per hunk: if you cannot separate them,
 * stop and ask.  Converging the file is not the safe default; it is the
 * destructive one.
 */
import { createHash } from "node:crypto";
import { access, readdir, readFile, stat } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const compare = (left, right) => (left < right ? -1 : left > right ? 1 : 0);
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const scriptPath = fileURLToPath(import.meta.url);
const defaultRoot = join(dirname(scriptPath), "..", "..");
// `bd list --all --json` was 991 KB on 2026-08-12, against a 1 MB execFile
// default: an unattended watcher was days from dying of ENOBUFS.
const maxBuffer = 64 * 1024 * 1024;
// flock -n exits with this code, and ONLY this code, when the lock is held.
// Anything else came from the child (fortkit-bpuv).
const lockConflictExit = 75;
// A diff body is evidence for a reader, not an archive.  Caps DISCLOSE
// themselves in the body (standing order: no silent caps).
const diffLineCap = 60;
const diffColumnCap = 1200;
// Above this the line-level LCS is not worth its memory; say so rather than
// silently degrading.
const diffLineCeiling = 4000;

async function text(path) {
  return readFile(path, "utf8");
}

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function files(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const found = [];
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) found.push(...(await files(path)));
    else if (entry.isFile()) found.push(path);
  }
  return found.sort(compare);
}

const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");

/**
 * Word-guarded where the token is a word and unguarded where it is not.  A
 * repo path starts with `/`, and `\b` fails against a non-word character, so
 * anchoring every token the same way silently stops substituting paths — which
 * is how `/home/justin/dev/fortkit` survived normalization long enough to be
 * mistaken for architecture.
 */
function tokenPattern(token) {
  const head = /^\w/u.test(token) ? "(?<!\\w)" : "";
  const tail = /\w$/u.test(token) ? "(?!\\w)" : "";
  return new RegExp(`${head}${escapeRegExp(token)}${tail}`, "gu");
}

// An actor id is identity by definition and never ports, so `-a <id>` is
// collapsed positionally on BOTH sides.  The template spells it with the
// seat-office word (`-a mayor`) and a seated fort with its citizen's id
// (`-a emrith`); no token substitution can equate those, but their POSITION
// can.  `-s <seat>` is deliberately untouched: the seat is architecture.
//
// fortkit-o9iu finding 5: this was `-a\s+\S+`, which collapsed the token after
// ANY short `-a` flag, positionally, on both sides.  `rsync -a --delete`
// against `rsync -a --exclude=...` normalized EQUAL and the difference became
// INVISIBLE — the one direction this module's own doc comment says nothing
// downstream can recover.  Nothing was hidden yet only because the live
// instance (`rsync -a \` in warden.sh:74 and its template twin) swallowed the
// same continuation backslash on both sides.  Requiring ACTOR-ID SHAPE keeps
// every real actor position and matches no flag, no backslash and no path.
// RESIDUAL, disclosed rather than argued away: bash's own `[ x -a y ]` test
// operator would still be collapsed.  It does not occur in the corpus, and
// narrowing further would need to know which `-a` belongs to `emit.sh`, which
// is exactly the kind of cleverness that fails silently.
const actorFlag = /(^|\s)-a\s+([A-Za-z][\w-]*)(?=\s|$)/gmu;

/**
 * Erase identity from a text so that what remains is architecture.
 *
 * Conservative on purpose: under-normalizing reports identity as architecture,
 * which is a false alarm a reader can dismiss, while over-normalizing HIDES
 * architecture, which nothing downstream can recover.  Only tokens that are
 * identity by the charter's definition are substituted — the repo path, the
 * project, the fort name, the roster's citizens, and the actor-id position.
 */
export function normalizer(fort, roster) {
  const substitutions = new Map();
  const add = (from, to) => {
    if (from && !substitutions.has(from)) substitutions.set(from, to);
  };
  add(fort.path, "{{REPO_PATH}}");
  add(fort.name, "{{FORT_NAME}}");
  add(fort.project, "{{PROJECT}}");
  // fortkit-o9iu finding 5, two sub-items DECLINED with the reason recorded,
  // because for both of them the tightening costs more than the risk:
  //   * `add(first.toLowerCase())` substitutes a bare given name everywhere.
  //     It is how `-a emrith` and `Emrith Cairnwright` become one token, which
  //     is load-bearing.  A citizen whose given name is also a corpus word
  //     would over-normalize; no such name exists in any roster, the failure
  //     is a name away and would be visible as a vanished finding, and any
  //     length or dictionary guard would silently stop normalizing a real
  //     citizen — a worse failure in the direction that cannot be recovered.
  //   * `tokenPattern` does not stop substitution inside hyphenated compounds.
  //     That is REQUIRED here, not tolerated: the template writes
  //     `{{REPO_PATH}}-worktrees` (forge.sh:12, settings-permissions.json), so
  //     the substitution must reach inside `/home/justin/dev/fortkit-worktrees`
  //     or every worktree-bearing line reads as permanent drift.  Excluding
  //     `-` from the guard would regress a working case to fix a hypothetical.
  for (const actor of roster) {
    add(actor, "{{ACTOR}}");
    const first = actor.split(/\s+/u)[0];
    add(first, "{{ACTOR}}");
    add(first.toLowerCase(), "{{ACTOR}}");
  }
  // Longest first, so `/home/justin/dev/fortkit` is consumed before `fortkit`
  // and `Emrith Cairnwright` before `Emrith`.
  const ordered = [...substitutions.entries()]
    .sort(
      ([left], [right]) => right.length - left.length || compare(left, right),
    )
    .map(([from, to]) => [tokenPattern(from), to]);
  return (value) =>
    ordered
      .reduce((result, [pattern, to]) => result.replace(pattern, to), value)
      .replace(actorFlag, "$1-a {{ACTOR}}");
}

/**
 * The fort's citizens, read from its SEAT FILES and accepting BOTH spellings.
 *
 * fortkit-9qts: this read `fort/charter.md` for `**Held by:** Name`, which is
 * the TEMPLATE's spelling of a line that appears only in `fort/seats/*.md`.
 * Two faults, either alone sufficient: the wrong file, and a spelling no
 * seated fort uses — a fort writes `**Held by: Ilva Trueglass** (she/her...)`,
 * with the asterisks closing after the NAME.  The roster was therefore empty
 * in every fort that has ever existed, no citizen was ever normalized, and
 * every launcher carrying a name read as permanent architecture drift.  Both
 * spellings are pinned in the regression tests: a fix that satisfies only the
 * template spelling reintroduces the bug invisibly, which is how this one
 * survived from the watcher's first run.
 */
const occupantLine = /^\*\*Held by:(?:\*\*)?\s*([^\n(*]+)/mu;

export function rosterFromSeats(texts) {
  const occupants = new RegExp(occupantLine.source, "gmu");
  const found = [];
  for (const value of texts)
    for (const match of value.matchAll(occupants)) {
      const name = match[1].trim();
      // `{{UNFILLED — set at the Founding Moot}}` is the template's own
      // placeholder, not a citizen.
      if (name && !name.includes("{{")) found.push(name);
    }
  return [...new Set(found)];
}

async function readRoster(fortPath, gaps, fortName) {
  const directory = join(fortPath, "fort", "seats");
  try {
    const seats = (await files(directory)).filter((path) =>
      path.endsWith(".md"),
    );
    const texts = await Promise.all(seats.map(text));
    // An UNSEATED fort — one whose seat files still carry the template's
    // `{{UNFILLED}}` placeholder — has no roster by design, and that is not a
    // defect.  What is a defect is seat files in which the occupant line does
    // not parse AT ALL, because that is precisely the shape of fortkit-9qts:
    // the roster silently empties, every citizen's name survives into the
    // comparison, and identity reads as architecture drift forever.  Disclose
    // the second and never the first.
    if (seats.length > 0 && !texts.some((value) => occupantLine.test(value)))
      gaps.push({
        source: `${fortName}:fort/seats`,
        reason:
          "no occupant line parsed in any seat file; identity cannot be normalized and will read as architecture drift (fortkit-9qts)",
      });
    // fortkit-o9iu finding 6: the check above is ALL-OR-NOTHING, so a single
    // seat file spelled some third way dropped THAT citizen silently — the
    // same failure class as 9qts, one quarter as loud, and undisclosed.  The
    // per-file rule keys on a file that CLAIMS an occupant (`Held by`) and
    // yields none, which is why it adds no noise for an unseated fort: the
    // template's `{{UNFILLED}}` line parses, and is then discarded by
    // `rosterFromSeats` as the placeholder it is.  DELIBERATE LIMIT: a seat
    // file carrying no `Held by` at all raises nothing, because this rule
    // declines to guess which markdown files are meant to be seat files.
    for (const [index, path] of seats.entries())
      if (/Held by/u.test(texts[index]) && !occupantLine.test(texts[index]))
        gaps.push({
          source: `${fortName}:${relative(fortPath, path)}`,
          reason:
            "seat file carries a 'Held by' line that does not parse; THIS citizen is dropped from the roster and their name will read as architecture drift (fortkit-o9iu finding 6)",
        });
    return rosterFromSeats(texts);
  } catch (error) {
    gaps.push({
      source: `${fortName}:fort/seats`,
      reason: `roster unreadable, identity will read as architecture drift: ${String(error.message)}`,
    });
    return [];
  }
}

function headings(value) {
  return new Set(
    [...value.matchAll(/^#{1,6}\s+(.+?)\s*$/gmu)].map((match) =>
      match[1].trim(),
    ),
  );
}

function charterRequirements(template) {
  const requirements = [];
  for (const heading of [
    "Human gates (capability boundaries, not requests)",
    "Threat model",
  ]) {
    if (headings(template).has(heading))
      requirements.push({ kind: "heading", value: heading });
  }
  const standingOrderHeading = template.search(/^## Standing orders[^\n]*$/mu);
  const standingOrders =
    standingOrderHeading === -1
      ? undefined
      : template
          .slice(template.indexOf("\n", standingOrderHeading) + 1)
          .split(/^## /mu, 1)[0];
  if (standingOrders)
    for (const match of standingOrders.matchAll(/^\d+\.\s+(.+?)(?:\n|$)/gmu)) {
      const order = match[1].replace(/\*\*/gu, "").trim();
      const fingerprint = order.match(/^(.+?[.!?])(?:\s|$)/u)?.[1] ?? order;
      requirements.push({ kind: "standing-order", value: fingerprint });
    }
  return requirements;
}

function reportPath(fort, path) {
  return `${fort.name}:${path}`;
}

async function newerThan(left, right, gitTime) {
  const [leftStat, rightStat] = await Promise.all([stat(left), stat(right)]);
  if (leftStat.mtimeMs !== rightStat.mtimeMs)
    return leftStat.mtimeMs > rightStat.mtimeMs ? "fort" : "template";
  const [leftGit, rightGit] = await Promise.all([
    gitTime(left),
    gitTime(right),
  ]);
  if (leftGit !== rightGit) return leftGit > rightGit ? "fort" : "template";
  return "unknown";
}

/**
 * The changed regions between two texts, as whole lines.  Used only AFTER both
 * sides are identity-normalized, so every hunk it returns is architecture by
 * construction — that is the per-hunk half of standing order 12.
 */
export function lineHunks(before, after) {
  const left = before.split("\n");
  const right = after.split("\n");
  if (left.length > diffLineCeiling || right.length > diffLineCeiling)
    return [{ template: left, fort: right, coarse: true }];
  const rows = left.length;
  const columns = right.length;
  const common = Array.from(
    { length: rows + 1 },
    () => new Int32Array(columns + 1),
  );
  for (let row = rows - 1; row >= 0; row -= 1)
    for (let column = columns - 1; column >= 0; column -= 1)
      common[row][column] =
        left[row] === right[column]
          ? common[row + 1][column + 1] + 1
          : Math.max(common[row + 1][column], common[row][column + 1]);
  const hunks = [];
  let current = null;
  let row = 0;
  let column = 0;
  while (row < rows || column < columns) {
    if (row < rows && column < columns && left[row] === right[column]) {
      current = null;
      row += 1;
      column += 1;
      continue;
    }
    if (!current) {
      current = { template: [], fort: [] };
      hunks.push(current);
    }
    if (
      column >= columns ||
      (row < rows && common[row + 1][column] >= common[row][column + 1])
    )
      current.template.push(left[row++]);
    else current.fort.push(right[column++]);
  }
  return hunks;
}

/**
 * The first column at which a line and its counterpart diverge.
 */
function firstDifference(left, right) {
  if (typeof right !== "string") return 0;
  const limit = Math.min(left.length, right.length);
  let index = 0;
  while (index < limit && left[index] === right[index]) index += 1;
  return index;
}

/**
 * fortkit-o9iu finding 2.  E9 raised the per-line cap to 1200 on `mayor.sh`'s
 * evidence and STILL cut the divergence out of the largest real case: the
 * longest line in the compared corpus is `fort/scripts/warden.sh`'s smoke
 * prompt, byte-identical to roughly char 1123 and diverging after it, so a
 * clip taken from the START of the line kept 1123 characters nobody needed and
 * threw away the only part anybody did.
 *
 * The window FOLLOWS the divergence instead, which fixes the class rather than
 * the instance and — the reason this was preferred to raising the cap — costs
 * no extra bytes.  The sibling cost is real: every filed bead description and
 * appended comment carries this body, and `.beads/issues.jsonl` is git-tracked
 * and ships to the elder forts under fortkit-or2.1.  So `diffCharCap` stays at
 * 12000 and the existing budget is spent on the right part of the line.
 * The elision is disclosed in the body: degraded evidence a reader can SEE is
 * degraded, never a lie by omission.
 */
const clipLead = 200;
const clip = (line, focus = 0) => {
  if (line.length <= diffColumnCap) return line;
  const start = Math.max(
    0,
    Math.min(focus - clipLead, line.length - diffColumnCap),
  );
  const end = Math.min(line.length, start + diffColumnCap);
  return [
    start > 0 ? `…[${start} identical chars elided] ` : "",
    line.slice(start, end),
    end < line.length ? " …[clipped]" : "",
  ].join("");
};

/**
 * What `normalizer()` leaves behind where a PERSON or a SETTLEMENT used to be.
 *
 * `{{PROJECT}}` and `{{REPO_PATH}}` are deliberately NOT here, and the reason
 * is measured rather than aesthetic: a fort-local bead id carries the project
 * name (`ForgeOs-8c9`, `longburn-suti`), so it normalizes to
 * `{{PROJECT}}-8c9` — and counting those flagged 4 of 7 hunks in Farlantern's
 * `seat-sandbox.sh`, none of which is a citizen.  A label a reader learns to
 * dismiss protects nobody.  fortkit-qu46 names `{{ACTOR}}`/`{{FORT_NAME}}`
 * precisely, and the measured fixture (the capital's `mayor.sh`) is still
 * caught by both of them.
 */
const identityPlaceholder = /\{\{(?:ACTOR|FORT_NAME)\}\}/gu;

function placeholderCensus(lines) {
  const census = new Map();
  for (const line of lines)
    for (const match of line.matchAll(identityPlaceholder))
      census.set(match[0], (census.get(match[0]) ?? 0) + 1);
  return census;
}

/**
 * fortkit-qu46: does this hunk pair an identity placeholder against prose?
 *
 * Counts, not sets, because the measured case on the capital's `mayor.sh` is
 * `-a {{ACTOR}}` on one side against `"...summons {{ACTOR}}" -a {{ACTOR}}` on
 * the other: the same placeholder, a different number of times.  A mismatch
 * means one side says a citizen goes here and the other says office prose
 * does, which is precisely the hunk whose MINUS side overwrites a living
 * citizen.  Over-flagging is the safe direction and the label says SUSPECT
 * rather than forbidden: it asks a reader to look, which is what standing
 * order 12 asks for anyway.
 */
export function identitySuspect(hunk) {
  const template = placeholderCensus(hunk.template);
  const fort = placeholderCensus(hunk.fort);
  for (const key of new Set([...template.keys(), ...fort.keys()]))
    if ((template.get(key) ?? 0) !== (fort.get(key) ?? 0)) return true;
  return false;
}

/**
 * The budget is on the WHOLE body, not only on the line count, because the
 * lines that matter here are long: a launcher's `--append-system-prompt` is
 * one ~1400-character line, and the push-gate hardening that standing order 12
 * cites as the thing that MUST port sits at the end of it.  A per-line cap
 * tight enough to bound a 34-hunk file clipped that hardening out of the only
 * hunk anybody needed to read.  Measured on Manyhalls `fort/scripts/mayor.sh`,
 * 2026-08-13.
 */
const diffCharCap = 12000;

/**
 * The evidence a reader acts on: the hunks surviving identity normalization,
 * with identity already redacted to `{{ACTOR}}` and friends.  A seat that
 * copies what this shows it cannot port a citizen's name, because the name is
 * not in it — and a hunk whose MINUS side would OVERWRITE one is labelled
 * IDENTITY-SUSPECT (fortkit-qu46), because redaction does not cover that
 * direction and the count must not claim it does.
 */
export function diffBody(fortName, path, templateText, fortText) {
  const hunks = lineHunks(templateText, fortText);
  const body = [
    `--- ${path} (template, identity normalized)`,
    `+++ ${path} (${fortName}, identity normalized)`,
  ];
  let emitted = 0;
  let omitted = 0;
  let suspect = 0;
  let budget = diffCharCap;
  const full = () => emitted >= diffLineCap || budget <= 0;
  for (const [index, hunk] of hunks.entries()) {
    // Counted BEFORE the budget check: a hunk dropped for space is still a
    // hunk the reader must be told about, or the census under-reports exactly
    // when the body is too big to read.
    const flagged = identitySuspect(hunk);
    if (flagged) suspect += 1;
    if (full()) {
      omitted += hunk.template.length + hunk.fort.length;
      continue;
    }
    body.push(
      `@@ hunk ${index + 1} of ${hunks.length}${hunk.coarse ? " (whole file: too large for a line diff)" : ""}${flagged ? " [IDENTITY-SUSPECT — one side carries an identity placeholder the other does not; applying the '-' side may OVERWRITE A LIVING CITIZEN (fortkit-qu46). Standing order 12: separate them, or stop and ask]" : ""} @@`,
    );
    for (const [sign, lines, counterparts] of [
      ["-", hunk.template, hunk.fort],
      ["+", hunk.fort, hunk.template],
    ])
      for (const [position, line] of lines.entries()) {
        if (full()) {
          omitted += 1;
          continue;
        }
        // The clip window follows the divergence only when the two sides pair
        // up one-for-one; otherwise there is no counterpart to diverge from
        // and it falls back to the start of the line.
        const focus =
          lines.length === counterparts.length
            ? firstDifference(line, counterparts[position])
            : 0;
        const rendered = `${sign}${clip(line, focus)}`;
        body.push(rendered);
        emitted += 1;
        budget -= rendered.length;
      }
  }
  if (omitted > 0)
    body.push(
      `[${omitted} further changed lines omitted; ${hunks.length} hunks surviving identity normalization in total — read the files for the rest]`,
    );
  return { body: body.join("\n"), hunks: hunks.length, suspect };
}

/** The stable identity of a finding: a fort and a path, and nothing else. */
export function identityOf(fort, path) {
  return sha256(`${fort}\0${path}`);
}

function makeFinding(
  fort,
  path,
  fortContent,
  templateContent,
  suggestion,
  reason,
  normalize = (value) => value,
) {
  const fortHash = sha256(fortContent);
  const templateHash = sha256(templateContent);
  const { body, hunks, suspect } = diffBody(
    fort.name,
    path,
    normalize(templateContent),
    normalize(fortContent),
  );
  return {
    fort: fort.name,
    path,
    suggestion,
    reason,
    fortHash,
    templateHash,
    hunks,
    suspect,
    identity: identityOf(fort.name, path),
    fingerprint: sha256(`${fort.name}\0${path}\0${fortHash}\0${templateHash}`),
    diff: body,
  };
}

async function defaultGitTime(path) {
  try {
    const { stdout } = await execFileAsync("git", [
      "-C",
      dirname(path),
      "log",
      "-1",
      "--format=%ct",
      "--",
      path,
    ]);
    return Number.parseInt(stdout.trim(), 10) || 0;
  } catch {
    return 0;
  }
}

/** True when this fort's history has ever carried the path (fortkit-or2.8). */
async function defaultGitHistory(repo, path) {
  const { stdout } = await execFileAsync(
    "git",
    ["-C", repo, "log", "-1", "--all", "--format=%H", "--", path],
    { maxBuffer },
  );
  return stdout.trim().length > 0;
}

/**
 * An absent file is not automatically a regression (fortkit-or2.8).  A
 * regression means a fort LOST something it had; a template file the fort
 * never carried was simply never propagated, and for the capital — which is
 * the template SOURCE, and whose fort/scripts is installed by the Overseer's
 * hand — that state is structurally permanent.  Filing an unfixable bead
 * every run trains a fort to ignore its watcher.
 */
async function absence(fort, path, gitHistory, gaps) {
  try {
    return (await gitHistory(fort.path, path))
      ? {
          suggestion: "regression",
          reason:
            "template file is absent from fort but present in the fort's git history",
        }
      : {
          suggestion: "not-yet-propagated",
          reason:
            "template file has never been propagated to this fort (absent, and no history under this path)",
        };
  } catch (error) {
    gaps.push({
      source: reportPath(fort, path),
      reason: `git history unreadable, absence reported as a regression: ${String(error.message)}`,
    });
    return {
      suggestion: "regression",
      reason:
        "template file is absent from fort and the fort's git history could not be read",
    };
  }
}

async function loadRegistry(path) {
  const parsed = JSON.parse(await text(path));
  if (!Array.isArray(parsed.forts))
    throw new Error("registry has no forts array");
  const forts = [];
  const gaps = [];
  for (const [index, entry] of parsed.forts.entries()) {
    const number = index + 1;
    if (typeof entry !== "object" || entry === null) {
      gaps.push({
        source: `${path} entry ${number}`,
        reason: "registry entry is not an object",
      });
      continue;
    }
    const candidate = entry;
    const project =
      typeof candidate.project === "string" ? candidate.project : null;
    const name =
      typeof candidate.fort_name === "string" ? candidate.fort_name : project;
    if (name === null || typeof candidate.repo !== "string") {
      gaps.push({
        source: `${path} entry ${number}`,
        reason: "registry entry lacks a fort_name/project or repo",
      });
      continue;
    }
    forts.push({
      name,
      // The project is the {{PROJECT}} placeholder's value and is a SEPARATE
      // identity token from the fort name: Manyhalls is the fort, fortkit is
      // the project, and both appear in the launchers.  Keeping only the name
      // (which is what this did) left `{{PROJECT}}` unsubstituted forever.
      project,
      path: isAbsolute(candidate.repo)
        ? candidate.repo
        : resolve(dirname(path), candidate.repo),
    });
  }
  return { forts, gaps };
}

export async function scan({
  root = defaultRoot,
  registryPath = join(homedir(), ".claude", "civilization.json"),
  allowlistPath = join(root, "civ", "drift-allowlist.json"),
  gitTime = defaultGitTime,
  gitHistory = defaultGitHistory,
} = {}) {
  const gaps = [];
  const findings = [];
  let compared = 0;
  let forts = [];
  try {
    const registry = await loadRegistry(registryPath);
    forts = registry.forts;
    gaps.push(...registry.gaps);
  } catch (error) {
    return {
      fortsScanned: 0,
      filesCompared: 0,
      findings,
      suppressed: [],
      lapsed: [],
      gaps: [{ source: registryPath, reason: String(error.message) }],
    };
  }
  let allowlist = [];
  try {
    allowlist = JSON.parse(await text(allowlistPath)).entries ?? [];
  } catch (error) {
    gaps.push({ source: allowlistPath, reason: String(error.message) });
  }
  const templateRoot = join(root, "templates");
  const binarySurfaces = [
    [
      join("fort", "scripts"),
      join("fort", "scripts"),
      (path) => path.endsWith(".sh"),
    ],
    [join("fort", "profiles"), join("fort", "profiles"), () => true],
  ];
  for (const fort of forts.sort((left, right) =>
    compare(left.name, right.name),
  )) {
    try {
      const charter = await text(join(fort.path, "fort", "charter.md"));
      const roster = await readRoster(fort.path, gaps, fort.name);
      const normalize = normalizer(fort, roster);
      for (const [fortSurface, templateSurface, accepts] of binarySurfaces) {
        const templateDir = join(templateRoot, templateSurface);
        const fortDir = join(fort.path, fortSurface);
        const templateFiles = (await files(templateDir)).filter(accepts);
        for (const templateFile of templateFiles) {
          const local = relative(templateDir, templateFile);
          const fortFile = join(fortDir, local);
          const path = join(fortSurface, local);
          if (!(await exists(fortFile))) {
            const { suggestion, reason } = await absence(
              fort,
              path,
              gitHistory,
              gaps,
            );
            findings.push(
              makeFinding(
                fort,
                path,
                "",
                await text(templateFile),
                suggestion,
                reason,
                normalize,
              ),
            );
            continue;
          }
          const [fortContent, templateContent] = await Promise.all([
            text(fortFile),
            text(templateFile),
          ]);
          compared += 1;
          if (normalize(fortContent) === normalize(templateContent)) continue;
          const direction = await newerThan(fortFile, templateFile, gitTime);
          findings.push(
            makeFinding(
              fort,
              path,
              fortContent,
              templateContent,
              direction === "template" ? "upgrade-offer" : "backport",
              // fortkit-qu46: NOT "outside identity".  Normalization erases
              // tokens, not phrasing, so what survives it is not thereby
              // architecture — see identitySuspect().
              `${direction}-newer divergence surviving identity normalization`,
              normalize,
            ),
          );
        }
      }
      const templatePermissions =
        JSON.parse(
          await text(join(templateRoot, "config", "settings-permissions.json")),
        ).permissions ?? {};
      const fortPermissions =
        JSON.parse(await text(join(fort.path, ".claude", "settings.json")))
          .permissions ?? {};
      for (const key of ["allow", "deny"]) {
        // The fort's rules are normalized INTO the template's spelling, not the
        // other way round: the template writes `Bash({{REPO_PATH}}/...)` and a
        // founded fort writes the rendered path, so a raw comparison reported
        // every path-bearing rule as absent forever.  Measured in the capital
        // 2026-08-13: two of eight "absent" permissions were this artifact and
        // six were real (fortkit-9qts, same class, different surface).
        const held = new Set((fortPermissions[key] ?? []).map(normalize));
        for (const rule of templatePermissions[key] ?? []) {
          compared += 1;
          if (!held.has(rule))
            findings.push(
              makeFinding(
                fort,
                ".claude/settings.json",
                // Hashed inputs are UNCHANGED from the pre-E9 watcher on
                // purpose: the fingerprint is a change detector on an
                // already-filed finding, and re-minting it would append a
                // "drift changed" comment to every settings bead for a change
                // that happened in this file rather than in any fort (the E7
                // scar, fortkit-zvz2).
                JSON.stringify(fortPermissions),
                JSON.stringify(templatePermissions),
                "regression",
                `template permission ${rule} is absent`,
                normalize,
              ),
            );
        }
      }
      const templateCharter = await text(
        join(templateRoot, "fort", "charter.md"),
      );
      for (const requirement of charterRequirements(templateCharter)) {
        compared += 1;
        const present =
          requirement.kind === "heading"
            ? headings(charter).has(requirement.value)
            : charter.replace(/\*\*/gu, "").includes(requirement.value);
        if (!present)
          findings.push(
            makeFinding(
              fort,
              "fort/charter.md",
              charter,
              templateCharter,
              "regression",
              `template ${requirement.kind} is absent: ${requirement.value}`,
              normalize,
            ),
          );
      }
      for (const templateSeat of await files(
        join(templateRoot, "fort", "seats"),
      )) {
        const path = `fort/seats/${relative(join(templateRoot, "fort", "seats"), templateSeat)}`;
        const fortSeat = join(fort.path, path);
        if (!(await exists(fortSeat))) {
          const { suggestion, reason } = await absence(
            fort,
            path,
            gitHistory,
            gaps,
          );
          findings.push(
            makeFinding(
              fort,
              path,
              "",
              await text(templateSeat),
              suggestion,
              reason,
              normalize,
            ),
          );
          continue;
        }
        const [templateContent, fortContent] = await Promise.all([
          text(templateSeat),
          text(fortSeat),
        ]);
        // HEADINGS ONLY, and deliberately so: a seat file's protocol sections
        // are architecture and its prose is that citizen's own.  This is
        // standing order 12 already implemented correctly, and it is the model
        // the rest of the comparison follows.  Do not turn it into a content
        // comparison.
        for (const heading of headings(templateContent)) {
          compared += 1;
          if (!headings(fortContent).has(heading))
            findings.push(
              makeFinding(
                fort,
                path,
                fortContent,
                templateContent,
                "regression",
                `required protocol heading is absent: ${heading}`,
                normalize,
              ),
            );
        }
      }
    } catch (error) {
      gaps.push({
        source: reportPath(fort, fort.path),
        reason: String(error.message),
      });
    }
  }
  // Collapse per identity, not per fingerprint: one file's drift is one
  // finding however many reasons it accumulated.
  const distinct = new Map();
  for (const finding of findings) {
    const existing = distinct.get(finding.identity);
    if (existing) existing.reason = `${existing.reason}; ${finding.reason}`;
    else distinct.set(finding.identity, finding);
  }
  const suppressed = [];
  const lapsed = [];
  const active = [...distinct.values()].filter((finding) => {
    const entries = allowlist.filter(
      (item) => item.fort === finding.fort && item.path === finding.path,
    );
    const entry = entries.find(
      (item) => item["content-hash"] === finding.fortHash,
    );
    if (entry) {
      suppressed.push({ finding, by: "allowlist", bead: entry.bead });
      return false;
    }
    // RULING, E7 2026-08-12: the allowlist's content-hash pin is KEPT — an
    // entry must not go on suppressing a file that has changed into something
    // nobody approved.  What was wrong is that the lapse was silent, so a
    // deliberate suppression could stop suppressing with no one told.  A
    // lapsed entry is now disclosed in the report, the event payload and on
    // stderr, and the finding resurfaces as it always did.
    for (const stale of entries)
      lapsed.push({
        fort: finding.fort,
        path: finding.path,
        bead: stale.bead,
        approved: stale["content-hash"],
        observed: finding.fortHash,
      });
    return true;
  });
  return {
    fortsScanned: forts.length,
    filesCompared: compared,
    findings: active,
    suppressed,
    lapsed,
    gaps,
  };
}

const identityLine = /Drift identity:\s*([a-f0-9]{64})/iu;
const fingerprintLine = /Drift fingerprint:\s*([a-f0-9]{64})/giu;
const driftTitle = /^Drift:\s+(\S+)\s+(\S.*?)\s*$/u;
/**
 * The ONLY thing that lets a closed bead go on suppressing an ABSENCE: an
 * explicit, written decline.  See `decide()`.
 */
const declineMarker = /Drift decision:\s*declined/iu;

/**
 * A bead's identity, preferring the explicit machine-readable line.
 *
 * RULING, E7 2026-08-12: pre-existing Drift beads (51 open on the day of the
 * fix) were filed before that line existed and fall back to their TITLE, which
 * the watcher has always written as `Drift: <fort> <path>`.  The alternative —
 * a migration pass rewriting 51 descriptions — edits records in place, which
 * standing order 7 forbids.  The disclosed residual: rewording a legacy title
 * during triage breaks that bead's match and the watcher will file a fresh
 * one.  The window closes as legacy beads close; everything filed or commented
 * on from now on carries the explicit line.
 */
export function beadIdentity(bead) {
  const explicit =
    typeof bead?.description === "string"
      ? bead.description.match(identityLine)
      : null;
  if (explicit) return explicit[1];
  const title =
    typeof bead?.title === "string" ? bead.title.match(driftTitle) : null;
  return title ? identityOf(title[1], title[2]) : null;
}

function fingerprintsIn(value) {
  return typeof value === "string"
    ? [...value.matchAll(fingerprintLine)].map((match) => match[1])
    : [];
}

export function descriptionOf(finding) {
  return [
    finding.reason,
    `Suggested classification: ${finding.suggestion}`,
    `Hunks surviving identity normalization: ${finding.hunks}`,
    ...(finding.suspect > 0
      ? [
          `IDENTITY-SUSPECT hunks: ${finding.suspect} — at least one hunk pairs an identity placeholder against prose. Applying the '-' side of those hunks can OVERWRITE A LIVING CITIZEN (fortkit-qu46); standing order 12 is applied per hunk, so separate them or stop and ask.`,
        ]
      : []),
    `Drift identity: ${finding.identity}`,
    `Drift fingerprint: ${finding.fingerprint}`,
    "",
    finding.diff,
  ].join("\n");
}

export function commentOf(finding) {
  return [
    "DRIFT CHANGED — appended by the drift watcher rather than filed as a second bead.",
    "The same fort and path have drifted again since this bead was last recorded;",
    "the fingerprint below is the new content state.",
    "",
    finding.reason,
    `Suggested classification: ${finding.suggestion}`,
    `Hunks surviving identity normalization: ${finding.hunks}`,
    ...(finding.suspect > 0
      ? [
          `IDENTITY-SUSPECT hunks: ${finding.suspect} — at least one hunk pairs an identity placeholder against prose. Applying the '-' side of those hunks can OVERWRITE A LIVING CITIZEN (fortkit-qu46); standing order 12 is applied per hunk, so separate them or stop and ask.`,
        ]
      : []),
    `Drift identity: ${finding.identity}`,
    `Drift fingerprint: ${finding.fingerprint}`,
    "",
    finding.diff,
  ].join("\n");
}

/**
 * bd v2.0 moves `--json` output into an envelope (fortkit-pp1k).  Accept both
 * shapes so the watcher never needs a coordinated upgrade to keep working.
 */
export function rows(parsed) {
  if (Array.isArray(parsed)) return parsed;
  for (const key of ["data", "issues", "comments", "results", "items"])
    if (Array.isArray(parsed?.[key])) return parsed[key];
  throw new Error(
    `unrecognised bd --json shape: ${JSON.stringify(parsed).slice(0, 200)}`,
  );
}

function byIdentity(beads) {
  const open = new Map();
  const closed = new Map();
  for (const bead of beads) {
    const identity = beadIdentity(bead);
    if (!identity) continue;
    const target = bead?.status === "closed" ? closed : open;
    const list = target.get(identity) ?? [];
    list.push(bead);
    target.set(identity, list);
  }
  for (const map of [open, closed])
    for (const list of map.values())
      list.sort((left, right) => compare(left.id, right.id));
  return { open, closed };
}

/**
 * The three-way decision, plus the cases that are neither.
 *
 *   open bead, same fingerprint       -> suppress (unchanged drift)
 *   open bead, different fingerprint  -> comment on it (drift changed)
 *   no open bead                      -> file
 *   ...but a CLOSED bead carrying this exact fingerprint suppresses once
 *      (the spec's one-shot suppression: this content state was adjudicated),
 *   ...and a never-propagated file with no open bead is DEFERRED, not filed
 *      (fortkit-or2.8) — filing an unfixable bead every run trains a fort to
 *      ignore its watcher.
 *
 * ABSENCE IS NOT ADJUDICABLE BY CLOSURE (fortkit-6b8y, edict E9).  For an
 * absent file the fort-side hash is the hash of the empty string, so the
 * fingerprint is stable for as long as the TEMPLATE file is unchanged, and a
 * closed bead therefore silenced the finding INDEFINITELY while the fort still
 * lacked the file — measured on four beads (fortkit-bn7i, fortkit-p6pe,
 * fortkit-5913, fortkit-b3gb), every one of them a Researcher-seat file that
 * two settlements still do not have.  Closing them was reasonable triage; the
 * side effect was invisible to whoever closed them.  So a closed bead now
 * suppresses an absence ONLY when it carries an explicit written decline
 * (`Drift decision: declined`, in the description or a comment).  Absent that,
 * the finding is RE-OBSERVED: reported and counted, never re-filed, because
 * the bead already exists and a second one would inflate the board
 * (fortkit-fnjn).  Deferred and re-observed findings alike are counted in
 * `report.propagationGaps`, which is the census the parity gate reads.
 *
 * ONE CLAUSE ON THAT COMPLETENESS, because the comment used to overstate it
 * (fortkit-o9iu finding 7): the census is built from `decide()`'s decisions,
 * which derive from `scan()`'s ACTIVE findings, and allowlist-suppressed
 * findings are filtered before they reach either.  So an ALLOWLISTED absence
 * is absent from this census.  That is the intended behaviour — an allowlist
 * entry is an approved suppression, the analogue of the explicit written
 * decline above — but it is a stated exception rather than a gap in a census
 * that claims to have none.
 */
export async function decide(findings, beads, readComments) {
  const { open, closed } = byIdentity(beads);
  const decisions = [];
  for (const finding of findings) {
    const absent = finding.suggestion === "not-yet-propagated";
    const matches = open.get(finding.identity) ?? [];
    if (matches.length > 0) {
      const known = new Set(
        matches.flatMap((bead) => fingerprintsIn(bead.description)),
      );
      if (!known.has(finding.fingerprint))
        for (const bead of matches)
          for (const comment of await readComments(bead.id))
            for (const value of fingerprintsIn(comment)) known.add(value);
      decisions.push({
        finding,
        action: known.has(finding.fingerprint) ? "suppress" : "comment",
        bead: matches[0].id,
      });
      continue;
    }
    const adjudicated = (closed.get(finding.identity) ?? []).find((bead) =>
      fingerprintsIn(bead.description).includes(finding.fingerprint),
    );
    if (adjudicated) {
      if (!absent) {
        decisions.push({
          finding,
          action: "adjudicated",
          bead: adjudicated.id,
        });
        continue;
      }
      let declined = declineMarker.test(adjudicated.description ?? "");
      if (!declined)
        for (const comment of await readComments(adjudicated.id))
          if (declineMarker.test(comment)) {
            declined = true;
            break;
          }
      decisions.push({
        finding,
        action: declined ? "declined" : "re-observed",
        bead: adjudicated.id,
      });
      continue;
    }
    decisions.push({ finding, action: absent ? "defer" : "file" });
  }
  return decisions;
}

async function defaultCommands(root) {
  return {
    async beads() {
      const { stdout } = await execFileAsync(
        "bd",
        ["list", "--all", "--limit", "0", "--json"],
        { maxBuffer },
      );
      return rows(JSON.parse(stdout));
    },
    async comments(id) {
      const { stdout } = await execFileAsync("bd", ["comments", id, "--json"], {
        maxBuffer,
      });
      return rows(JSON.parse(stdout)).map((comment) =>
        typeof comment?.text === "string" ? comment.text : "",
      );
    },
    async file(finding) {
      await execFileAsync(
        "bd",
        [
          "create",
          `Drift: ${finding.fort} ${finding.path}`,
          "--type=task",
          "--priority=2",
          "--description",
          descriptionOf(finding),
        ],
        { maxBuffer },
      );
    },
    async comment(id, body) {
      await execFileAsync("bd", ["comment", id, body], { maxBuffer });
    },
    async emit(report) {
      const payload = JSON.stringify({
        fortsScanned: report.fortsScanned,
        filesCompared: report.filesCompared,
        findingsFiled: report.filed,
        findingsCommented: report.commented,
        findingsSuppressed: report.suppressed.length,
        findingsDeferred: report.deferred.length,
        propagationGaps: report.propagationGaps.length,
        propagationGapsReobserved: report.reobserved.length,
        allowlistLapsed: report.lapsed.length,
        sourcesUnreadable: report.gaps.length,
      });
      await execFileAsync(join(root, "fort", "scripts", "emit.sh"), [
        "drift.scan",
        `drift scan: ${report.filed} filed, ${report.commented} commented, ${report.suppressed.length} suppressed, ${report.propagationGaps.length} propagation gaps, ${report.gaps.length} gaps`,
        "-a",
        "watcher:drift",
        "-t",
        "drift-watch",
        "-p",
        payload,
      ]);
    },
  };
}

export async function run(options = {}) {
  const report = await scan(options);
  const commands =
    options.commands ?? (await defaultCommands(options.root ?? defaultRoot));
  // --dry-run reads the tracker (it must, to report what it WOULD do) and
  // touches no write seam.
  let beads;
  try {
    beads = await commands.beads();
  } catch (error) {
    throw new Error(
      `drift watcher could not read the tracker: ${error.message}`,
    );
  }
  const decisions = await decide(report.findings, beads, commands.comments);
  const chosen = (action) =>
    decisions.filter((decision) => decision.action === action);
  const toFile = chosen("file").map((decision) => decision.finding);
  const toComment = chosen("comment");
  for (const decision of chosen("suppress"))
    report.suppressed.push({
      finding: decision.finding,
      by: "identity",
      bead: decision.bead,
    });
  for (const decision of chosen("adjudicated"))
    report.suppressed.push({
      finding: decision.finding,
      by: "closed-bead",
      bead: decision.bead,
    });
  for (const decision of chosen("declined"))
    report.suppressed.push({
      finding: decision.finding,
      by: "declined",
      bead: decision.bead,
    });
  report.deferred = chosen("defer").map((decision) => decision.finding);
  report.reobserved = chosen("re-observed").map((decision) => ({
    fort: decision.finding.fort,
    path: decision.finding.path,
    bead: decision.bead,
    reason:
      "closed bead carries no explicit decline and the fort still lacks this file",
  }));
  // THE CENSUS THE PARITY GATE READS.  Every not-yet-propagated finding
  // appears here whatever the filing decision was, because the question
  // "which files does this fort still not have" must not be answerable only
  // by whoever happens to read the filing plan (fortkit-6b8y).
  report.propagationGaps = decisions
    .filter((decision) => decision.finding.suggestion === "not-yet-propagated")
    .map((decision) => ({
      fort: decision.finding.fort,
      path: decision.finding.path,
      action: decision.action,
      bead: decision.bead ?? null,
    }))
    .sort(
      (left, right) =>
        compare(left.fort, right.fort) || compare(left.path, right.path),
    );
  report.identityMatches =
    chosen("suppress").length +
    toComment.length +
    chosen("adjudicated").length +
    chosen("declined").length +
    chosen("re-observed").length;
  report.plan = {
    file: toFile.length,
    comment: toComment.length,
    suppress:
      chosen("suppress").length +
      chosen("adjudicated").length +
      chosen("declined").length,
    defer: report.deferred.length,
    reobserved: report.reobserved.length,
    propagationGaps: report.propagationGaps.length,
  };
  report.dryRun = Boolean(options.dryRun);
  if (options.dryRun) {
    report.filed = 0;
    report.commented = 0;
    return report;
  }
  for (const finding of toFile) await commands.file(finding);
  for (const decision of toComment)
    await commands.comment(decision.bead, commentOf(decision.finding));
  report.filed = toFile.length;
  report.commented = toComment.length;
  await commands.emit(report);
  return report;
}

function cliOptions(arguments_) {
  const options = { dryRun: false };
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "--dry-run") options.dryRun = true;
    else if (argument === "--registry")
      options.registryPath = arguments_[++index];
    else if (argument === "--root") options.root = arguments_[++index];
    else if (argument === "--lock-held") options.lockHeld = true;
    else throw new Error(`unknown argument: ${argument}`);
  }
  return options;
}

function failure(message, exitCode) {
  const error = new Error(message);
  error.exitCode = exitCode;
  return error;
}

async function main() {
  const options = cliOptions(process.argv.slice(2));
  if (!options.lockHeld) {
    const lock = join(tmpdir(), "fortkit-drift-watch.lock");
    const args = [
      "-n",
      "-E",
      String(lockConflictExit),
      lock,
      process.execPath,
      scriptPath,
      ...process.argv.slice(2),
      "--lock-held",
    ];
    let result;
    try {
      result = await execFileAsync("flock", args, { maxBuffer });
    } catch (error) {
      // fortkit-bpuv: flock exits non-zero both when the lock is held and
      // when the child fails for any reason, so the old blanket message
      // asserted a cause it had not established and read as benign
      // contention in a journal nobody watches.
      if (error.code === lockConflictExit)
        throw failure(
          `drift watcher is already running: ${lock} is held`,
          lockConflictExit,
        );
      if (error.stdout) process.stdout.write(error.stdout);
      if (error.stderr) process.stderr.write(error.stderr);
      if (typeof error.code !== "number")
        throw failure(`drift watcher could not run flock: ${error.message}`, 1);
      throw failure(
        `drift watcher child failed (exit ${error.code}${error.signal ? `, signal ${error.signal}` : ""}): ${(error.stderr || error.message).trim().split("\n").pop()}`,
        error.code,
      );
    }
    process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    return;
  }
  const report = await run(options);
  for (const entry of report.lapsed)
    process.stderr.write(
      `allowlist entry for ${entry.fort} ${entry.path} lapsed: content-hash no longer matches (approved ${entry.approved.slice(0, 12)}, observed ${entry.observed.slice(0, 12)}, bead ${entry.bead})\n`,
    );
  // Absence is announced on stderr as well as in the report, because the whole
  // defect this replaced was a gap that existed only in a field nobody read.
  if (report.propagationGaps.length > 0)
    process.stderr.write(
      `propagation gaps: ${report.propagationGaps.length} template file(s) absent from a fort — ${report.propagationGaps
        .map(
          (gap) =>
            `${gap.fort} ${gap.path} [${gap.action}${gap.bead ? ` ${gap.bead}` : ""}]`,
        )
        .join("; ")}\n`,
    );
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

if (process.argv[1] === scriptPath)
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = typeof error.exitCode === "number" ? error.exitCode : 1;
  });

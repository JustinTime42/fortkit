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

function normalizer(fort, roster) {
  const substitutions = new Map();
  for (const [from, to] of [
    [fort.path, "{{REPO_PATH}}"],
    [fort.name, "{{FORT_NAME}}"],
    ...roster.map((actor) => [actor, "{{ACTOR}}"]),
  ]) {
    if (from) substitutions.set(from, to);
  }
  return (value) =>
    [...substitutions.entries()]
      .sort(
        ([left], [right]) => right.length - left.length || compare(left, right),
      )
      .reduce((result, [from, to]) => result.split(from).join(to), value);
}

function rosterFromCharter(charter) {
  const occupants = /^\*\*Held by:\*\*\s*([^\n(]+)/gmu;
  return [...charter.matchAll(occupants)].map(
    (match) => match[1].trim().split(/\s+/u)[0],
  );
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
) {
  const fortHash = sha256(fortContent);
  const templateHash = sha256(templateContent);
  return {
    fort: fort.name,
    path,
    suggestion,
    reason,
    fortHash,
    templateHash,
    identity: identityOf(fort.name, path),
    fingerprint: sha256(`${fort.name}\0${path}\0${fortHash}\0${templateHash}`),
    diff: `--- ${path} (template)\n+++ ${path} (${fort.name})\n-${templateContent.slice(0, 600)}\n+${fortContent.slice(0, 600)}`,
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
    const name =
      typeof candidate.fort_name === "string"
        ? candidate.fort_name
        : typeof candidate.project === "string"
          ? candidate.project
          : null;
    if (name === null || typeof candidate.repo !== "string") {
      gaps.push({
        source: `${path} entry ${number}`,
        reason: "registry entry lacks a fort_name/project or repo",
      });
      continue;
    }
    forts.push({
      name,
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
      const normalize = normalizer(fort, rosterFromCharter(charter));
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
              `${direction}-newer byte divergence`,
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
      for (const key of ["allow", "deny"])
        for (const rule of templatePermissions[key] ?? []) {
          compared += 1;
          if (!(fortPermissions[key] ?? []).includes(rule))
            findings.push(
              makeFinding(
                fort,
                ".claude/settings.json",
                JSON.stringify(fortPermissions),
                JSON.stringify(templatePermissions),
                "regression",
                `template permission ${rule} is absent`,
              ),
            );
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
            ),
          );
          continue;
        }
        const [templateContent, fortContent] = await Promise.all([
          text(templateSeat),
          text(fortSeat),
        ]);
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
 * The three-way decision, plus the two cases that are neither.
 *
 *   open bead, same fingerprint       -> suppress (unchanged drift)
 *   open bead, different fingerprint  -> comment on it (drift changed)
 *   no open bead                      -> file
 *   ...but a CLOSED bead carrying this exact fingerprint suppresses once
 *      (the spec's one-shot suppression: this content state was adjudicated),
 *   ...and a never-propagated file with no open bead is DEFERRED, not filed
 *      (fortkit-or2.8) — its propagation is tracked by fortkit-vhk.7 and, for
 *      the capital, it is a permanent structural state.
 */
export async function decide(findings, beads, readComments) {
  const { open, closed } = byIdentity(beads);
  const decisions = [];
  for (const finding of findings) {
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
      decisions.push({ finding, action: "adjudicated", bead: adjudicated.id });
      continue;
    }
    decisions.push({
      finding,
      action: finding.suggestion === "not-yet-propagated" ? "defer" : "file",
    });
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
        allowlistLapsed: report.lapsed.length,
        sourcesUnreadable: report.gaps.length,
      });
      await execFileAsync(join(root, "fort", "scripts", "emit.sh"), [
        "drift.scan",
        `drift scan: ${report.filed} filed, ${report.commented} commented, ${report.suppressed.length} suppressed, ${report.deferred.length} deferred, ${report.gaps.length} gaps`,
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
  report.deferred = chosen("defer").map((decision) => decision.finding);
  report.identityMatches =
    chosen("suppress").length + toComment.length + chosen("adjudicated").length;
  report.plan = {
    file: toFile.length,
    comment: toComment.length,
    suppress: chosen("suppress").length + chosen("adjudicated").length,
    defer: report.deferred.length,
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
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

if (process.argv[1] === scriptPath)
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = typeof error.exitCode === "number" ? error.exitCode : 1;
  });

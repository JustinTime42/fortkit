#!/usr/bin/env node
import { execFile } from "node:child_process";
/**
 * Detect template drift without ever changing a registered fort.  The command
 * seams below deliberately keep tests (and --dry-run) away from bd and emit.sh.
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
            findings.push(
              makeFinding(
                fort,
                path,
                "",
                await text(templateFile),
                "regression",
                "template file is absent from fort",
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
          findings.push(
            makeFinding(
              fort,
              path,
              "",
              await text(templateSeat),
              "regression",
              "template seat file is absent from fort",
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
  const distinct = new Map();
  for (const finding of findings) {
    const existing = distinct.get(finding.fingerprint);
    if (existing) existing.reason = `${existing.reason}; ${finding.reason}`;
    else distinct.set(finding.fingerprint, finding);
  }
  const suppressed = [];
  const active = [...distinct.values()].filter((finding) => {
    const entry = allowlist.find(
      (item) =>
        item.fort === finding.fort &&
        item.path === finding.path &&
        item["content-hash"] === finding.fortHash,
    );
    if (entry) {
      suppressed.push({ finding, by: "allowlist", bead: entry.bead });
      return false;
    }
    return true;
  });
  return {
    fortsScanned: forts.length,
    filesCompared: compared,
    findings: active,
    suppressed,
    gaps,
  };
}

function existingFingerprints(beads) {
  return new Set(
    beads.flatMap((bead) =>
      typeof bead?.description === "string"
        ? [
            ...bead.description.matchAll(
              /Drift fingerprint:\s*([a-f0-9]{64})/giu,
            ),
          ].map((match) => match[1])
        : [],
    ),
  );
}

async function defaultCommands(root) {
  return {
    async existing() {
      const { stdout } = await execFileAsync("bd", [
        "list",
        "--all",
        "--limit",
        "0",
        "--json",
      ]);
      return existingFingerprints(JSON.parse(stdout));
    },
    async file(finding) {
      await execFileAsync("bd", [
        "create",
        `Drift: ${finding.fort} ${finding.path}`,
        "--type=task",
        "--priority=2",
        "--description",
        `${finding.reason}\nSuggested classification: ${finding.suggestion}\nDrift fingerprint: ${finding.fingerprint}\n\n${finding.diff}`,
      ]);
    },
    async emit(report) {
      const payload = JSON.stringify({
        fortsScanned: report.fortsScanned,
        filesCompared: report.filesCompared,
        findingsFiled: report.filed,
        findingsSuppressed: report.suppressed.length,
        sourcesUnreadable: report.gaps.length,
      });
      await execFileAsync(join(root, "fort", "scripts", "emit.sh"), [
        "drift.scan",
        `drift scan: ${report.filed} filed, ${report.suppressed.length} suppressed, ${report.gaps.length} gaps`,
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
  if (options.dryRun) return { ...report, filed: 0 };
  const commands =
    options.commands ?? (await defaultCommands(options.root ?? defaultRoot));
  const known = await commands.existing();
  const toFile = report.findings.filter((finding) => {
    if (known.has(finding.fingerprint)) {
      report.suppressed.push({ finding, by: "fingerprint" });
      return false;
    }
    return true;
  });
  for (const finding of toFile) await commands.file(finding);
  report.filed = toFile.length;
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

async function main() {
  const options = cliOptions(process.argv.slice(2));
  if (!options.lockHeld) {
    const lock = join(tmpdir(), "fortkit-drift-watch.lock");
    const args = [
      "-n",
      lock,
      process.execPath,
      scriptPath,
      ...process.argv.slice(2),
      "--lock-held",
    ];
    const result = await execFileAsync("flock", args).catch((error) => {
      throw new Error(
        `drift watcher already running or flock failed: ${error.message}`,
      );
    });
    process.stdout.write(result.stdout);
    return;
  }
  const report = await run(options);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

if (process.argv[1] === scriptPath)
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });

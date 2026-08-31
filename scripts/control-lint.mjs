#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { isAbsolute, join, relative, resolve } from "node:path";

const root = resolve(process.argv[2] ?? process.cwd());
const controlsDirectory = join(root, "fort", "controls");
const fingerprintsPath = join(root, "scripts", "control-fingerprints.json");
const kinds = new Set([
  "wall",
  "fence",
  "prose-gate",
  "ratchet",
  "governor",
  "tripwire",
  "falsifier",
  "latch",
]);
const failures = [];
const missingFalsifiers = [];

function parseFrontmatter(text) {
  const match = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/u.exec(text);
  if (match === null) return null;
  return Object.fromEntries(
    [...match[1].matchAll(/^([a-z-]+):\s*(.*)$/gmu)].map(([, key, value]) => [
      key,
      value === "null" ? null : value,
    ]),
  );
}

function fingerprint(line) {
  return createHash("sha256").update(line, "utf8").digest("hex");
}

function citationPath(rootDirectory, citation) {
  const match = /^(.*):(\d+)$/u.exec(citation ?? "");
  if (match === null) return null;
  const [, file, line] = match;
  const path = resolve(rootDirectory, file);
  const pathFromRoot = relative(rootDirectory, path);
  if (
    file === "" ||
    isAbsolute(file) ||
    pathFromRoot === ".." ||
    pathFromRoot.startsWith("../")
  )
    return null;
  return { path, line: Number(line) };
}

let files = [];
try {
  files = (await readdir(controlsDirectory))
    .filter((file) => file.endsWith(".md") && file !== "README.md")
    .sort();
} catch {
  failures.push(
    `${controlsDirectory}: unreadable — the control register cannot be linted`,
  );
}
if (failures.length === 0 && files.length === 0)
  failures.push(
    `${controlsDirectory}: contains zero control files, so this lint proved nothing`,
  );

let fingerprints = {};
try {
  fingerprints = JSON.parse(await readFile(fingerprintsPath, "utf8"));
} catch {
  failures.push(
    `${fingerprintsPath}: unreadable — citation fingerprints are unavailable`,
  );
}

for (const file of files) {
  const controlPath = join(controlsDirectory, file);
  const control = parseFrontmatter(await readFile(controlPath, "utf8"));
  if (control === null) {
    failures.push(`${controlPath}: missing YAML frontmatter`);
    continue;
  }
  const key = file.replace(/\.md$/u, "");
  if (control.kind === undefined)
    failures.push(`${controlPath}: kind is required`);
  else if (!kinds.has(control.kind))
    failures.push(
      `${controlPath}: unknown kind ${JSON.stringify(control.kind)}`,
    );
  if (!("falsified-by" in control))
    failures.push(`${controlPath}: falsified-by must be declared explicitly`);
  else if (control["falsified-by"] === null) missingFalsifiers.push(key);

  const citation = citationPath(root, control.implements);
  if (citation === null) {
    failures.push(
      `${controlPath}: implements must be a repository-relative file:line citation`,
    );
    continue;
  }
  let source;
  try {
    source = await readFile(citation.path, "utf8");
  } catch {
    failures.push(
      `${controlPath}: implements path ${control.implements} does not exist`,
    );
    continue;
  }
  const citedLine = source.split(/\r?\n/u)[citation.line - 1];
  if (citedLine === undefined) {
    failures.push(
      `${controlPath}: implements line ${control.implements} does not exist`,
    );
    continue;
  }
  const expectedFingerprint = fingerprints[key];
  if (typeof expectedFingerprint !== "string") {
    failures.push(
      `${controlPath}: no recorded fingerprint for ${control.implements}`,
    );
    continue;
  }
  if (fingerprint(citedLine) !== expectedFingerprint)
    failures.push(
      `${controlPath}: cited line ${control.implements} no longer matches its recorded fingerprint`,
    );
}

console.log(
  `control-lint: ${files.length} control file(s) checked; ${missingFalsifiers.length} explicitly declare no falsifier`,
);
for (const key of missingFalsifiers)
  console.log(
    `control-lint: ${key}: falsified-by is null (reported, not failed)`,
  );
for (const failure of failures) console.error(`control-lint: ${failure}`);
if (failures.length > 0) process.exitCode = 1;

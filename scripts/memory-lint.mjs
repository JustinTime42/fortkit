#!/usr/bin/env node
import { readdir, readFile } from "node:fs/promises";
import { basename, join } from "node:path";

const root = process.argv[2] ?? process.cwd();
const factsDirectory = join(root, "fort", "memory", "facts");
const required = ["source", "declared-by", "date", "origin"];
let failures = [];

function parseFact(text) {
  const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/u.exec(text);
  if (match === null) return null;
  const frontmatter = Object.fromEntries(
    [...match[1].matchAll(/^([a-z-]+):\s*(.*)$/gmu)].map(([, key, value]) => [
      key,
      value === "null" ? null : value.replace(/^"|"$/gu, ""),
    ]),
  );
  const provenance = /^provenance:\s*\r?\n((?:\s+.+\r?\n?)+)/mu.exec(match[1])?.[1] ?? "";
  for (const [, key, value] of provenance.matchAll(/^\s+([a-z-]+):\s*(.*)$/gmu)) frontmatter[key] = value.replace(/^"|"$/gu, "");
  const scope = /^scope:\s*\r?\n((?:\s+.+\r?\n?)+)/mu.exec(match[1])?.[1] ?? "";
  return { frontmatter, scope, body: match[2].trim() };
}

let files = [];
try {
  files = (await readdir(factsDirectory)).filter((file) => file.endsWith(".md")).sort();
} catch {
  failures.push("fort/memory/facts is unreadable");
}
let coreLines = 0;
for (const file of files) {
  const path = join(factsDirectory, file);
  const parsed = parseFact(await readFile(path, "utf8"));
  if (parsed === null) {
    failures.push(`${path}: missing YAML frontmatter`);
    continue;
  }
  const { frontmatter, scope, body } = parsed;
  const key = basename(file, ".md");
  if (frontmatter.key !== key) failures.push(`${path}: key must equal filename`);
  if (!["active", "superseded"].includes(frontmatter.status)) failures.push(`${path}: invalid status`);
  if (!["core", "on-demand"].includes(frontmatter.tier)) failures.push(`${path}: invalid tier`);
  if (scope.trim() === "") failures.push(`${path}: scope is required`);
  if (body === "") failures.push(`${path}: body is required`);
  for (const key of required) if (!frontmatter[key]) failures.push(`${path}: provenance.${key} is required`);
  if (!["trusted", "untrusted"].includes(frontmatter.origin)) failures.push(`${path}: invalid provenance.origin`);
  if (frontmatter.origin === "untrusted" && frontmatter.tier === "core") failures.push(`${path}: untrusted facts cannot be core`);
  if (frontmatter.status === "superseded" && !frontmatter["superseded-by"]) failures.push(`${path}: superseded facts need superseded-by`);
  if (frontmatter["superseded-by"] && !files.includes(`${frontmatter["superseded-by"]}.md`)) failures.push(`${path}: superseded-by does not resolve`);
  if (frontmatter.tier === "core") coreLines += body.split(/\r?\n/u).length + 12;
}
if (coreLines > 300) failures.push(`core tier exceeds 300 lines (${coreLines})`);
if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
}

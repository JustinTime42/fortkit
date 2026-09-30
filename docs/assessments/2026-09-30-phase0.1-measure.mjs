// Phase 0.1 measurement (fortkit-2y2t.40.1). Read-only: writes only to its own
// scratch temp dir. Reuses the drift watcher's normalizer so "identity" means
// what the civilization's instrument already means by it.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync, existsSync } from "node:fs";
import { join, relative } from "node:path";
import { homedir, tmpdir } from "node:os";
import { normalizer, rosterFromSeats } from "/home/justin/dev/fortkit/civ/scripts/drift-watch.mjs";

const TMP = mkdtempSync(join(process.env.SCRATCH ?? tmpdir(), "m401-"));
const sha = (s) => createHash("sha256").update(s).digest("hex").slice(0, 12);
const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });
const git = (cwd, args) => { try { return execFileSync("git", ["-C", cwd, ...args], { encoding: "utf8", maxBuffer: 1 << 28 }); } catch { return null; } };
let seq = 0;
function hunks(a, b) {
  const fa = join(TMP, `a${++seq}`), fb = join(TMP, `b${seq}`);
  writeFileSync(fa, a); writeFileSync(fb, b);
  let out = "";
  try { execFileSync("git", ["diff", "--no-index", "-U0", fa, fb], { encoding: "utf8", maxBuffer: 1 << 28 }); }
  catch (e) { out = e.stdout ?? ""; }
  const res = [];
  for (const m of out.matchAll(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/gm)) {
    const a0 = +m[1], an = m[2] === undefined ? 1 : +m[2], b0 = +m[3], bn = m[4] === undefined ? 1 : +m[4];
    res.push({ a0, an, b0, bn, lines: an + bn });
  }
  return res;
}
const changed = (h) => h.reduce((s, x) => s + x.lines, 0);

const registry = JSON.parse(readFileSync(join(homedir(), ".claude", "civilization.json"), "utf8"));
const forts = registry.forts.map((f) => ({ name: f.fort_name, project: f.project, path: f.repo }));
for (const fort of forts) {
  const sd = join(fort.path, "fort", "seats");
  const texts = existsSync(sd) ? readdirSync(sd).filter((n) => n.endsWith(".md")).map((n) => readFileSync(join(sd, n), "utf8")) : [];
  fort.roster = rosterFromSeats(texts);
  fort.norm = normalizer(fort, fort.roster);
}

// ---- Part 1: the capital template's files present in all four forts ----
const TPL = "/home/justin/dev/fortkit/templates";
const tplFiles = walk(TPL).map((p) => relative(TPL, p)).sort();
const inAll = tplFiles.filter((r) => forts.every((f) => existsSync(join(f.path, r))));
let controlChanged = 0, controlTotal = 0;
const p1 = [];
for (const r of inAll) {
  const t = readFileSync(join(TPL, r), "utf8");
  const raw = [t], nrm = [t];
  const perFort = {};
  for (const f of forts) {
    const s = readFileSync(join(f.path, r), "utf8"), n = f.norm(s);
    controlTotal++; if (n !== s) controlChanged++;
    raw.push(s); nrm.push(n);
    const tn = f.norm(t); perFort[f.name] = { rawLines: changed(hunks(t, s)), oneSided: changed(hunks(t, n)), archLines: changed(hunks(tn, n)), archHunks: hunks(tn, n).length, identical: tn === n };
  }
  p1.push({ file: r, rawVersions: new Set(raw.map(sha)).size, normVersions: new Set(nrm.map(sha)).size, perFort });
}

// ---- Part 2: Proofdelve vs Greenlab's factory since the 2026-09-22 copy ----
const GL = "/home/justin/dev/greenlab", PD = forts.find((f) => f.name === "Proofdelve");
const BASE = "80766b4", STRIP = "812dbe1";
const glFiles = (git(GL, ["show", "--name-only", "--format=", BASE]) ?? "").split("\n").filter(Boolean);
// map a line number in STRIP coords to BASE coords, from diff(base, strip)
function mapper(hs) {
  return (n) => { let off = 0; for (const h of hs) { const bEnd = h.b0 + h.bn - 1; if (h.bn > 0 && n >= h.b0 && n <= bEnd) return h.a0; if (n > (h.bn ? bEnd : h.b0)) off = (h.a0 + h.an) - (h.b0 + h.bn); } return n + off; };
}
const p2 = [];
let pdControl = 0;
for (const p of glFiles) {
  const rest = p.replace(/^templates\//, "");
  const base = git(GL, ["show", `${BASE}:${p}`]);
  if (base === null || base.includes("\u0000")) continue;
  const strip = git(GL, ["show", `${STRIP}:${p}`]), head = git(GL, ["show", `HEAD:${p}`]);
  const pdHead = git(PD.path, ["show", `HEAD:${rest}`]);
  const bN = PD.norm(base); if (bN !== base) pdControl++;
  const pdH = pdHead === null ? null : hunks(bN, PD.norm(pdHead));
  let glH = null;
  if (head !== null && strip !== null) {
    const map = mapper(hunks(base, strip));
    glH = hunks(strip, head).map((h) => ({ ...h, a0: map(h.a0), aEnd: map(h.a0 + Math.max(h.an, 1) - 1) }));
  }
  const pdR = (pdH ?? []).map((h) => [h.a0, h.a0 + Math.max(h.an, 1) - 1]);
  const glR = (glH ?? []).map((h) => [h.a0, h.aEnd]);
  const overlap = (x, y) => x[0] <= y[1] + 1 && y[0] <= x[1] + 1;
  const conflictPd = pdR.filter((x) => glR.some((y) => overlap(x, y))).length;
  const conflictGl = glR.filter((y) => pdR.some((x) => overlap(x, y))).length;
  p2.push({ file: rest, pdStatus: pdHead === null ? "absent-in-Proofdelve" : "present", glStatus: head === null ? "deleted-in-Greenlab" : strip === null ? "absent-after-strip" : "present",
    pdHunks: pdR.length, pdLines: changed(pdH ?? []), glHunks: glR.length, glLines: changed(glH ?? []),
    pdOnly: pdR.length - conflictPd, glOnly: glR.length - conflictGl, conflictingPd: conflictPd, conflictingGl: conflictGl });
}
console.log(JSON.stringify({ forts: forts.map((f) => ({ name: f.name, rosterSize: f.roster?.size ?? f.roster?.length ?? Object.keys(f.roster ?? {}).length })),
  part1: { templateFiles: tplFiles.length, inAllFour: inAll.length, control: { normalizationChangedText: controlChanged, of: controlTotal }, files: p1 },
  part2: { base: BASE, strip: STRIP, filesInCopy: glFiles.length, textFilesCompared: p2.length, control: { baseTextsChangedByProofdelveNormalizer: pdControl }, files: p2 } }, null, 1));

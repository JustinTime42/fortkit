// Readers and the signing-command allowlist for the Civ Keep.
//
// Derived from Proofdelve's tools/keep/lib/readers.mjs (ForgeOs dae80d8e). The
// reading half is narrowed to the one command that carries everything the graph
// and the drawer need (`bd export`: labels, dependencies, comments), run once per
// fort per refresh and SEQUENTIALLY across forts, so this server adds one embedded
// Dolt open per fort per minute and never several at once in one tree.
//
// The writing half is the Proofdelve allowlist made per-fort: every argument is
// checked against the fort the request names (its bead prefix, its emit.sh, its
// waiting labels), so a signature for one fort can never be applied to another.
import { execFile, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import path from "node:path";
import { createInterface } from "node:readline";
import { validRequestId } from "./airlock.mjs";
import { escapeRegExp, idPattern } from "./id-pattern.js";

export { escapeRegExp, idPattern };

export function command(file, args, options = {}) {
  return new Promise((resolve, reject) => {
    execFile(
      file,
      args,
      { timeout: 30_000, maxBuffer: 16 * 1024 * 1024, ...options },
      (error, stdout) => {
        if (error) reject(error);
        else resolve(stdout);
      },
    );
  });
}

export const KEEP_CLOSED_FULL_DAYS = 14;
const STDERR_TAIL_BYTES = 4 * 1024;

function boundedBead(bead, cutoff) {
  const closedAt = Date.parse(bead.closed_at);
  if (
    bead.status !== "closed" ||
    typeof bead.closed_at !== "string" ||
    !Number.isFinite(closedAt) ||
    closedAt >= cutoff
  )
    return bead;
  return {
    id: bead.id,
    status: "closed",
    closed_at: bead.closed_at,
    title: bead.title,
    issue_type: bead.issue_type,
    dependencies: bead.dependencies,
    trimmed: true,
  };
}

function addExportLine(byId, line, cutoff) {
  if (!line) return false;
  try {
    const bead = JSON.parse(line);
    if (!bead.id) throw new Error("export record has no id");
    byId.set(bead.id, boundedBead(bead, cutoff));
    return false;
  } catch {
    return true;
  }
}

export function parseExport(text, { now = Date.now() } = {}) {
  const byId = new Map();
  let skipped = 0;
  const cutoff = now - KEEP_CLOSED_FULL_DAYS * 24 * 60 * 60 * 1000;
  for (const line of text.split("\n")) {
    if (addExportLine(byId, line, cutoff)) skipped += 1;
  }
  return { byId, skipped };
}

// Read the export without buffering its full history. The hash deliberately sees
// raw chunks, rather than lines, so it remains identical to sha256(stdout).
export function readExport(fort, options = {}) {
  const spawnImpl = options.spawn ?? spawn;
  const timeoutMs = options.timeout ?? 60_000;
  const now = options.now ?? Date.now();
  const cutoff = now - KEEP_CLOSED_FULL_DAYS * 24 * 60 * 60 * 1000;
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawnImpl("bd", ["export"], {
        cwd: fort.repo,
        env: options.env,
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (error) {
      reject(error);
      return;
    }
    const byId = new Map();
    let skipped = 0;
    let stderr = Buffer.alloc(0);
    const hash = createHash("sha256");
    let settled = false;
    let killTimer;
    const settle = (error, result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (killTimer) clearTimeout(killTimer);
      if (error) reject(error);
      else resolve(result);
    };
    const stderrTail = () => stderr.toString("utf8").trim();
    const reader = createInterface({
      input: child.stdout,
      crlfDelay: Infinity,
    });
    reader.on("line", (line) => {
      if (addExportLine(byId, line, cutoff)) skipped += 1;
    });
    child.stdout.on("data", (chunk) => hash.update(chunk));
    child.stderr.on("data", (chunk) => {
      const data = Buffer.concat([stderr, Buffer.from(chunk)]);
      stderr = data.subarray(Math.max(0, data.length - STDERR_TAIL_BYTES));
    });
    const fail = (error) => {
      reader.close();
      settle(error);
    };
    child.on("error", fail);
    child.stdout.on("error", fail);
    child.stderr.on("error", fail);
    child.on("close", (code, signal) => {
      if (code !== 0) {
        const detail = stderrTail();
        fail(
          new Error(
            signal
              ? `bd export exited with signal ${signal}${detail ? `: ${detail}` : ""}`
              : `bd export exited with code ${code}${detail ? `: ${detail}` : ""}`,
          ),
        );
        return;
      }
      settle(null, { byId, skipped, digest: hash.digest("hex") });
    });
    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
      fail(new Error(`bd export timed out after ${timeoutMs / 1000} s`));
      killTimer = setTimeout(() => child.kill("SIGKILL"), 5_000);
      killTimer.unref?.();
    }, timeoutMs);
    timeout.unref?.();
  });
}

export const signEvents = Object.freeze({
  approve: "gate.approved",
  decline: "gate.declined",
  decide: "decision.recorded",
});

// The only payload a sign event may carry: the approval pin (ForgeOs-ubgx).
function approvalPayload(text) {
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    return false;
  }
  if (!payload || typeof payload !== "object" || Array.isArray(payload))
    return false;
  if (Object.keys(payload).sort().join(",") !== "approvedSha,branch")
    return false;
  return (
    (payload.approvedSha === null ||
      /^[0-9a-f]{40}$/.test(payload.approvedSha)) &&
    typeof payload.branch === "string" &&
    /^bead\/[\w.-]+$/.test(payload.branch)
  );
}

// Every write the desk can make, checked against the fort it is made in.
// Anything else throws before a process is started.
export function signCommand(fort, file, args, options = {}, run = command) {
  const { auditDirectory, ...runOptions } = options;
  const validId = (value) =>
    typeof value === "string" &&
    Boolean(fort.prefix) &&
    idPattern(fort.prefix).test(value);
  const id = args[1];
  const commentPath = typeof args[3] === "string" ? path.resolve(args[3]) : "";
  const comment =
    file === "bd" &&
    validId(id) &&
    args.length === 4 &&
    args[0] === "comment" &&
    args[2] === "--file" &&
    typeof auditDirectory === "string" &&
    path.dirname(commentPath) === path.resolve(auditDirectory) &&
    path.basename(commentPath).startsWith(`comment-${id}-`) &&
    path.basename(commentPath).endsWith(".md");
  const removeWaiting =
    file === "bd" &&
    validId(id) &&
    args.length === 4 &&
    args[0] === "update" &&
    args[2] === "--remove-label" &&
    fort.waitingLabels.includes(args[3]);
  // ForgeOs-29j3g: in a fort whose board is the assignee, an answer moves the
  // bead on -- cleared (the fleet takes it) or to that fort's Mayor. Never to
  // anyone else, never to the Overseer, and in no other fort at all.
  const moveAssignee =
    file === "bd" &&
    validId(id) &&
    Boolean(fort.whoseMove) &&
    args.length === 4 &&
    args[0] === "update" &&
    args[2] === "--assignee" &&
    (args[3] === "" || args[3] === fort.whoseMove.mayor);
  const restoreFleetSafe =
    file === "bd" &&
    validId(id) &&
    fort.mode === "fleet" &&
    args.length === 4 &&
    args[0] === "update" &&
    args[2] === "--add-label" &&
    args[3] === "fleet-safe";
  const routeMayorReview =
    file === "bd" &&
    validId(id) &&
    args.length === 4 &&
    args[0] === "update" &&
    args[2] === "--add-label" &&
    args[3] === "mayor-review";
  const revParse =
    file === "git" &&
    fort.mode === "fleet" &&
    args.length === 4 &&
    args[0] === "rev-parse" &&
    args[1] === "--verify" &&
    args[2] === "--quiet" &&
    typeof args[3] === "string" &&
    /^bead\/[\w.-]+$/.test(args[3]);
  const emit =
    file === path.join(fort.repo, "fort/scripts/emit.sh") &&
    Object.values(signEvents).includes(args[0]) &&
    (args.length === 8 ||
      (args.length === 10 &&
        args[0] === "gate.approved" &&
        args[8] === "-p" &&
        approvalPayload(args[9]))) &&
    typeof args[1] === "string" &&
    args[2] === "-a" &&
    args[3] === "justin" &&
    args[4] === "-s" &&
    args[5] === "overseer" &&
    args[6] === "-t" &&
    validId(args[7]) &&
    args[1].startsWith(`${args[7]}: `);
  // ForgeOs-72ot.1: announcing an airlock approval the desk has just written
  // into the Overseer store. The target is a request id, never a bead.
  const airlockEmit =
    file === path.join(fort.repo, "fort/scripts/emit.sh") &&
    args.length === 8 &&
    args[0] === "airlock.approved" &&
    typeof args[1] === "string" &&
    args[2] === "-a" &&
    args[3] === "justin" &&
    args[4] === "-s" &&
    args[5] === "overseer" &&
    args[6] === "-t" &&
    validRequestId(args[7]) &&
    args[1].startsWith(`${args[7]}: `);
  const sameTree =
    path.resolve(runOptions.cwd ?? "") === path.resolve(fort.repo);
  if (
    !sameTree ||
    !(
      comment ||
      removeWaiting ||
      moveAssignee ||
      restoreFleetSafe ||
      routeMayorReview ||
      emit ||
      airlockEmit ||
      revParse
    )
  ) {
    throw new Error(
      `signing command rejected for ${fort.key}: ${file} ${args[0] ?? ""}`,
    );
  }
  return run(file, args, runOptions);
}

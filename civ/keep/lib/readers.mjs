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
import { execFile } from "node:child_process";
import path from "node:path";

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

export function parseExport(text) {
  const byId = new Map();
  let skipped = 0;
  for (const line of text.split("\n")) {
    if (!line) continue;
    try {
      const bead = JSON.parse(line);
      if (!bead.id) throw new Error("export record has no id");
      byId.set(bead.id, bead);
    } catch {
      skipped += 1;
    }
  }
  return { byId, skipped };
}

export const signEvents = Object.freeze({
  approve: "gate.approved",
  decline: "gate.declined",
  decide: "decision.recorded",
});

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function idPattern(prefix) {
  return new RegExp(`^${escapeRegExp(prefix)}-[\\w.-]+$`);
}

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
  const sameTree =
    path.resolve(runOptions.cwd ?? "") === path.resolve(fort.repo);
  if (
    !sameTree ||
    !(
      comment ||
      removeWaiting ||
      restoreFleetSafe ||
      routeMayorReview ||
      emit ||
      revParse
    )
  ) {
    throw new Error(
      `signing command rejected for ${fort.key}: ${file} ${args[0] ?? ""}`,
    );
  }
  return run(file, args, runOptions);
}

// CIV KEEP: the airlock half of the Overseer store (ForgeOs-72ot.1, Regent edict
// 2026-10-06, the Overseer's ruling of 2026-10-05 with the store placed at
// civilization level).
//
// A fort that has fort/airlock/ lets its seats REQUEST privileged operations
// declared in fort/airlock/operations.json. Until this module the Overseer's
// approval was a `.status` field inside the request file, and requests/ is
// seat-writable because a seat has to be able to request. Approval now lives in
// ~/.local/state/civ-keep/airlock-approvals.jsonl, which every fort's
// lib/seat-sandbox.sh binds read-only in every seat mask; this Keep runs on the
// host as a user unit and is one of its two writers (the other is that fort's
// own `airlock.sh approve`, run on the host).
//
// THE LINE FORMAT IS SHARED WITH airlock.sh, which is the reader that decides
// whether anything runs, so it is stated once here and matched there:
//   {ts, fort, repo, id, operation, requestSha256, actor:"justin", via:"civ-keep"}
// repo is the fort's checkout (airlock.sh matches on its own root); the hash is
// sha256 over the request file's bytes as they stood at approval, so an edit
// after approval voids it. airlock.sh appends {repo, id, consumed:true} before a
// run, which makes every approval single-use.

import { createHash } from "node:crypto";
import path from "node:path";

const REQUEST_ID = /^\d{8}T\d{6}-[a-z0-9][a-z0-9-]*-\d+$/;

export function validRequestId(id) {
  return typeof id === "string" && REQUEST_ID.test(id);
}

function readLines(fileSystem, file) {
  let text;
  try {
    text = fileSystem.readFileSync(file, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
  const out = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line));
    } catch {
      // A malformed line is skipped, never fatal (airlock.sh does the same).
    }
  }
  return out;
}

function operations(fileSystem, fort) {
  try {
    const table = JSON.parse(
      fileSystem.readFileSync(
        path.join(fort.repo, "fort/airlock/operations.json"),
        "utf8",
      ),
    );
    return Array.isArray(table.operations) ? table.operations : [];
  } catch {
    return [];
  }
}

// Requests that are waiting on the Overseer: pending in the file, declared as
// requiring approval, with no result, not yet approved in the store, never
// consumed. A request whose operation needs no approval is not listed: there is
// nothing for him to do.
export function pendingRequests(fort, { fileSystem, approvalsPath }) {
  const dir = path.join(fort.repo, "fort/airlock/requests");
  let names;
  try {
    names = fileSystem.readdirSync(dir);
  } catch {
    return [];
  }
  const ops = operations(fileSystem, fort);
  const store = readLines(fileSystem, approvalsPath).filter(
    (line) => line.repo === fort.repo,
  );
  const out = [];
  for (const name of names.sort()) {
    if (!name.endsWith(".json")) continue;
    const id = name.slice(0, -5);
    if (!validRequestId(id)) continue;
    let request;
    try {
      request = JSON.parse(
        fileSystem.readFileSync(path.join(dir, name), "utf8"),
      );
    } catch {
      continue;
    }
    if (request.status !== "pending" || request.id !== id) continue;
    const op = ops.find((item) => item.name === request.operation);
    if (!op || op.requires_approval !== true) continue;
    try {
      fileSystem.statSync(path.join(fort.repo, "fort/airlock/results", name));
      continue;
    } catch {
      // no result: still waiting
    }
    if (store.some((line) => line.id === id)) continue;
    out.push({
      fort: fort.key,
      fortName: fort.name,
      id,
      operation: request.operation,
      reason: request.reason ?? "",
      requestedBy: request.requested_by ?? "",
      seat: request.seat ?? "",
      requestedAt: request.requested_at ?? "",
      params: request.params ?? {},
      description: op.description ?? "",
    });
  }
  return out;
}

// The store line for an approval of `id` as its file stands right now, or an
// error naming why it cannot be approved. Pure apart from reads.
export function approvalLine(fort, id, { fileSystem, approvalsPath, now }) {
  if (!validRequestId(id)) return { error: "Invalid request id", status: 400 };
  const pending = pendingRequests(fort, { fileSystem, approvalsPath });
  const found = pending.find((item) => item.id === id);
  if (!found)
    return {
      error:
        "Not a pending airlock request that needs approval (already approved, ran, or not declared requires_approval)",
      status: 409,
    };
  const bytes = fileSystem.readFileSync(
    path.join(fort.repo, "fort/airlock/requests", `${id}.json`),
  );
  return {
    request: found,
    line: {
      ts: new Date(now()).toISOString(),
      fort: fort.key,
      repo: fort.repo,
      id,
      operation: found.operation,
      requestSha256: createHash("sha256").update(bytes).digest("hex"),
      actor: "justin",
      via: "civ-keep",
    },
  };
}

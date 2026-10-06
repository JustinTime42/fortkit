// The Civ Keep: one loopback dashboard over every fort of every civilization,
// with the Overseer's signing desk.
//
// Built 2026-10-03 by the Regent at the Overseer's request. It reuses Proofdelve's
// Keep (tools/keep at ForgeOs dae80d8e): lib/graph.mjs, drawer.js, markdown.mjs,
// live.mjs, events.mjs, fleet.mjs and keep.css are copies, changed only where a
// comment marked CIV KEEP says so. The copies are deliberate rather than imports
// from Proofdelve's tree: this server runs unmasked with write access to every
// fort's tracker, and it must not execute code that another fort's fleet can
// change under it.
//
// WHAT IT CAN WRITE, and nothing else (lib/readers.mjs signCommand enforces it per
// fort): a bd comment, removing that fort's waiting label, adding mayor-review,
// adding fleet-safe in a fleet fort on an unnoted Approve of a bead whose branch
// exists, and one gate.approved / gate.declined / decision.recorded event through
// that fort's own emit.sh as actor justin, seat overseer. It cannot merge, close,
// dispatch, create or edit a bead. A plain Comment writes a bd comment only.

import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { approvalLine, pendingRequests } from "./lib/airlock.mjs";
import { EventTail } from "./lib/events.mjs";
import { readFleet } from "./lib/fleet.mjs";
import { loadForts, prefixOf } from "./lib/forts.mjs";
import {
  dependencyGroups,
  graph,
  graphContext,
  needsYou,
  stage,
} from "./lib/graph.mjs";
import {
  command,
  parseExport,
  signCommand,
  signEvents,
} from "./lib/readers.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));

function json(response, body, status = 200) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
  });
  response.end(JSON.stringify(body));
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let body = "";
    request.setEncoding("utf8");
    request.on("data", (chunk) => {
      body += chunk;
      if (body.length > 65_536)
        reject(
          Object.assign(new Error("Request is too large"), { status: 413 }),
        );
    });
    request.on("end", () => {
      try {
        resolve(JSON.parse(body));
      } catch {
        reject(Object.assign(new Error("Invalid JSON"), { status: 400 }));
      }
    });
    request.on("error", reject);
  });
}

function digest(value) {
  return createHash("sha256").update(value).digest();
}

function bearerMatches(header, token) {
  if (!header?.startsWith("Bearer ") || !token) return false;
  return timingSafeEqual(digest(header.slice(7)), digest(token));
}

export function decisionOptions(bead) {
  const source = `${bead.description ?? ""}\n${bead.acceptance_criteria ?? ""}`;
  return [...source.matchAll(/^OPTION ([A-Z]):\s*(.+)$/gm)].map((match) => ({
    id: match[1],
    text: match[2],
  }));
}

const actions = new Set([...Object.keys(signEvents), "comment"]);

export function createCivKeep(options = {}) {
  const env = options.env ?? process.env;
  const fileSystem = options.fileSystem ?? fs;
  const now = options.now ?? (() => Date.now());
  const run = options.run ?? command;
  const exit = options.exit ?? process.exit;
  const log = options.log ?? console.error;
  const configHome =
    env.XDG_CONFIG_HOME || path.join(env.HOME ?? "", ".config");
  const stateHome =
    env.XDG_STATE_HOME || path.join(env.HOME ?? "", ".local/state");
  const tokenPath =
    options.tokenPath ?? path.join(configHome, "civ-keep/signing-token");
  const auditPath =
    options.auditPath ?? path.join(stateHome, "civ-keep/signatures.jsonl");
  const auditDirectory = path.dirname(auditPath);
  // The airlock approvals sit beside the signature audit in the Overseer store
  // (ForgeOs-72ot.1): read-only to every seat mask, written only from the host.
  const approvalsPath =
    options.approvalsPath ??
    path.join(auditDirectory, "airlock-approvals.jsonl");
  const signRun =
    options.signRun ??
    ((fort, file, args, runOptions) =>
      signCommand(
        fort,
        file,
        args,
        {
          ...runOptions,
          auditDirectory,
        },
        run,
      ));
  const loadFortList =
    options.loadForts ?? (() => loadForts({ env, fileSystem }));
  const clients = new Set();
  const inFlight = new Set();
  // key -> { fort, byId, skipped, events, fleet, stale, error, refreshedAt }
  const states = new Map();
  let bootModuleMtimes;

  function stateFor(fort) {
    let entry = states.get(fort.key);
    if (!entry) {
      entry = {
        fort,
        byId: new Map(),
        skipped: 0,
        fleet: { workers: [], halted: false },
        stale: true,
        error: "not yet read",
        events:
          options.eventTail?.(fort) ??
          new EventTail({
            directory: path.join(fort.repo, "fort/events"),
            fileSystem,
          }),
      };
      try {
        entry.events.load();
      } catch {
        /* the next refresh retries */
      }
      states.set(fort.key, entry);
    }
    entry.fort = { ...entry.fort, ...fort, prefix: entry.fort.prefix ?? null };
    return entry;
  }

  async function refreshFort(entry) {
    const { fort } = entry;
    try {
      entry.events.scan();
    } catch {
      /* keep the last snapshot */
    }
    if (fort.fleetState) {
      try {
        entry.fleet = readFleet(fort.fleetState, fileSystem, {
          keepRoot: fort.repo,
        });
      } catch {
        entry.fleet = { workers: [], halted: false };
      }
    }
    try {
      const text = await run("bd", ["export"], {
        cwd: fort.repo,
        maxBuffer: 64 * 1024 * 1024,
      });
      const parsed = parseExport(String(text));
      const prefix = prefixOf(parsed.byId.values());
      const clash = [...states.values()].find(
        (other) =>
          other !== entry && other.fort.prefix && other.fort.prefix === prefix,
      );
      if (clash)
        throw new Error(
          `bead prefix ${prefix} is also ${clash.fort.name}'s; refusing to merge two forts' ids`,
        );
      entry.byId = parsed.byId;
      entry.skipped = parsed.skipped;
      entry.fort = { ...entry.fort, prefix };
      entry.stale = false;
      entry.error = null;
      entry.refreshedAt = new Date(now()).toISOString();
    } catch (error) {
      entry.stale = true;
      entry.error = String(error.message ?? error).split("\n")[0];
    }
  }

  async function refresh() {
    checkModuleStaleness();
    const forts = loadFortList();
    for (const key of [...states.keys()])
      if (!forts.some((fort) => fort.key === key)) states.delete(key);
    // Sequential on purpose: one embedded Dolt open at a time across the host.
    for (const fort of forts) await refreshFort(stateFor(fort));
    for (const client of clients) client.write("event: tick\ndata: {}\n\n");
  }

  function checkModuleStaleness() {
    let sources;
    try {
      sources = [
        path.join(here, "server.mjs"),
        ...fileSystem
          .readdirSync(path.join(here, "lib"), { withFileTypes: true })
          .filter((entry) => entry.isFile())
          .map((entry) => path.join(here, "lib", entry.name)),
      ];
    } catch {
      return;
    }
    const observed = new Map();
    for (const source of sources) {
      try {
        observed.set(source, fileSystem.statSync(source).mtimeMs);
      } catch {
        return;
      }
    }
    if (!bootModuleMtimes) {
      bootModuleMtimes = observed;
      return;
    }
    for (const [source, mtime] of observed) {
      if (bootModuleMtimes.get(source) !== mtime) {
        log(
          `Civ Keep source changed since boot: ${source}; exiting for restart`,
        );
        exit(1);
        return;
      }
    }
  }

  function contextFor(entry) {
    return graphContext(
      [...entry.byId.values()],
      entry.events.events,
      entry.fleet.workers ?? [],
      now(),
      entry.fort.waitingLabels,
    );
  }

  function fortFor(id) {
    for (const entry of states.values()) if (entry.byId.has(id)) return entry;
    return null;
  }

  function selected(filter) {
    return [...states.values()].filter(
      (entry) => !filter || filter === "all" || entry.fort.key === filter,
    );
  }

  function fortSummary(entry) {
    const beads = [...entry.byId.values()];
    const context = contextFor(entry);
    const open = beads.filter((bead) => bead.status !== "closed");
    return {
      key: entry.fort.key,
      name: entry.fort.name,
      civilization: entry.fort.civilization,
      project: entry.fort.project,
      mode: entry.fort.mode,
      prefix: entry.fort.prefix,
      waitingLabels: entry.fort.waitingLabels,
      open: open.length,
      needsYou: open.filter((bead) => needsYou(bead, context)).length,
      halted: Boolean(entry.fleet?.halted),
      workers: (entry.fleet?.workers ?? []).length,
      stale: entry.stale,
      error: entry.error,
      refreshedAt: entry.refreshedAt ?? null,
    };
  }

  function renderGraph(response, url) {
    const closedHours = url.searchParams.get("closed") === "7d" ? 168 : 24;
    const scope = url.searchParams.get("scope") ?? "frontier";
    const result = {
      nodes: [],
      edges: [],
      epics: [],
      skipped: 0,
      stale: false,
      staleForts: [],
    };
    for (const entry of selected(url.searchParams.get("fort"))) {
      const tag = {
        fort: entry.fort.key,
        fortName: entry.fort.name,
        civilization: entry.fort.civilization,
      };
      const part = graph(
        [...entry.byId.values()],
        entry.events.events,
        entry.fleet.workers ?? [],
        now(),
        scope,
        closedHours,
        entry.fort.waitingLabels,
      );
      result.nodes.push(...part.nodes.map((node) => ({ ...node, ...tag })));
      result.edges.push(...part.edges);
      result.epics.push(...part.epics.map((epic) => ({ ...epic, ...tag })));
      result.skipped += entry.skipped;
      if (entry.stale) {
        result.stale = true;
        result.staleForts.push(entry.fort.name);
      }
    }
    return json(response, {
      ...result,
      generatedAt: new Date(now()).toISOString(),
    });
  }

  function renderApiBead(response, encodedId) {
    const id = decodeURIComponent(encodedId);
    const entry = fortFor(id);
    if (!entry) return json(response, { error: "Not found" }, 404);
    const bead = entry.byId.get(id);
    const context = contextFor(entry);
    return json(response, {
      ...bead,
      fort: entry.fort.key,
      fortName: entry.fort.name,
      civilization: entry.fort.civilization,
      fortMode: entry.fort.mode,
      stage: stage(bead, context),
      needsYou: needsYou(bead, context),
      dependencyGroups: dependencyGroups(bead, context.byId),
    });
  }

  function readToken(response) {
    try {
      const token = fileSystem.readFileSync(tokenPath, "utf8").trim();
      if (token) return token;
    } catch {
      /* fall through */
    }
    json(
      response,
      { error: "signing is not configured; run civ/keep/install.sh" },
      503,
    );
    return null;
  }

  function renderSignatures(response, url) {
    const limit = Math.max(
      0,
      Math.min(200, Number(url.searchParams.get("limit") ?? 50) || 50),
    );
    try {
      const lines = fileSystem
        .readFileSync(auditPath, "utf8")
        .trim()
        .split("\n")
        .filter(Boolean);
      return json(
        response,
        lines
          .slice(-limit)
          .reverse()
          .map((line) => JSON.parse(line)),
      );
    } catch (error) {
      if (error.code === "ENOENT") return json(response, []);
      throw error;
    }
  }

  async function renderSign(request, response) {
    const token = readToken(response);
    if (!token) return;
    if (!bearerMatches(request.headers.authorization, token))
      return json(response, { error: "Unauthorized" }, 401);
    const body = await readJson(request);
    const id = typeof body.id === "string" ? body.id : "";
    const action = typeof body.action === "string" ? body.action : "";
    const text = typeof body.text === "string" ? body.text.trim() : "";
    const option = typeof body.option === "string" ? body.option : null;
    if (!id || !actions.has(action))
      return json(response, { error: "Invalid signature request" }, 400);
    const entry = fortFor(id);
    if (!entry) return json(response, { error: "Not found" }, 404);
    if (body.fort && body.fort !== entry.fort.key)
      return json(response, { error: "Bead is not in that fort" }, 409);
    const { fort } = entry;
    const bead = entry.byId.get(id);
    if (
      (action === "decline" || action === "decide" || action === "comment") &&
      !text
    ) {
      return json(
        response,
        { error: "A note is required for Decline, Decide and Comment" },
        400,
      );
    }
    const need = needsYou(bead, contextFor(entry));
    if (action !== "comment" && !need)
      return json(response, { error: "Bead is not in needs-you" }, 409);
    if (
      action === "decide" &&
      !decisionOptions(bead).some((item) => item.id === option)
    ) {
      return json(response, { error: "Choose an option from the bead" }, 400);
    }
    if (inFlight.has(id))
      return json(
        response,
        { error: "A signature for this bead is already in flight" },
        409,
      );

    inFlight.add(id);
    try {
      const timestamp = new Date(now()).toISOString();
      const displayAction = action === "decide" ? `decide ${option}` : action;
      const summary = text || (action === "approve" ? "approved" : "");
      const fleet = fort.mode === "fleet";
      const branch = `bead/${id.slice(fort.prefix.length + 1)}`;
      let approvedSha = null;
      const pinned = () =>
        action !== "approve" || !fleet
          ? ""
          : approvedSha
            ? ` [approvedSha ${approvedSha} on ${branch}]`
            : ` [approvedSha null; no ${branch}]`;
      const toMayor = () =>
        action === "decline" ||
        action === "decide" ||
        (action === "approve" && (!fleet || text || !approvedSha));
      const routeNote = () => {
        if (action === "comment") return "";
        if (!toMayor()) return " [fleet-safe restored]";
        if (action !== "approve") return " [routed to the Mayor]";
        if (!fleet) return " [routed to the Mayor: this fort has no fleet]";
        return text
          ? " [routed to the Mayor: approval notes]"
          : " [routed to the Mayor: no branch]";
      };
      const commentText = () =>
        `OVERSEER via the Civ Keep ${timestamp}: ${displayAction.toUpperCase()} — ${summary}${pinned()}${routeNote()}`;
      const commentPath = path.join(
        auditDirectory,
        `comment-${id}-${randomUUID()}.md`,
      );
      const cwd = fort.repo;
      const completed = [];
      const appendOutcome = (outcome, step) =>
        fileSystem.appendFileSync(
          auditPath,
          `${JSON.stringify({
            ts: timestamp,
            fort: fort.key,
            bead: id,
            outcome,
            step,
          })}\n`,
          { mode: 0o600 },
        );
      const steps = [
        [
          "audit",
          async () => {
            fileSystem.mkdirSync(auditDirectory, {
              recursive: true,
              mode: 0o700,
            });
            fileSystem.appendFileSync(
              auditPath,
              `${JSON.stringify({
                ts: timestamp,
                fort: fort.key,
                bead: id,
                action,
                option,
                text,
                tokenFingerprint: digest(token).toString("hex").slice(0, 12),
                remoteAddress: request.socket.remoteAddress ?? null,
              })}\n`,
              { mode: 0o600 },
            );
          },
        ],
        [
          "resolve-sha",
          async () => {
            if (action !== "approve" || !fleet) return;
            try {
              const output = String(
                await signRun(
                  fort,
                  "git",
                  ["rev-parse", "--verify", "--quiet", branch],
                  { cwd },
                ),
              ).trim();
              if (!/^[0-9a-f]{40}$/.test(output))
                throw new Error(
                  `git rev-parse returned no commit for ${branch}`,
                );
              approvedSha = output;
            } catch (error) {
              // Exit 1 is git's "no such ref"; any other failure stops the signature
              // before any bd write (ForgeOs-ubgx).
              if (error?.code !== 1) throw error;
            }
          },
        ],
        [
          // THE PIN (ForgeOs-ubgx.4). approvedSha may be null (an Approve of a
          // bead with no branch); that pin corroborates nothing, since the
          // fleet needs a 40-hex sha equal to the stream's. The approvedSha goes into this audit, in
          // the Overseer store, as well as into the gate.approved payload: the
          // fleet lands a signed branch only when both name the same sha, so a
          // seat that can write the event stream cannot sign for him. Written
          // before any bd write, beside the audit line it belongs to.
          "pin",
          async () => {
            if (action !== "approve" || !fleet) return;
            fileSystem.appendFileSync(
              auditPath,
              `${JSON.stringify({
                ts: timestamp,
                fort: fort.key,
                bead: id,
                step: "pin",
                approvedSha,
                branch,
              })}\n`,
              { mode: 0o600 },
            );
          },
        ],
        [
          "comment",
          async () => {
            fileSystem.writeFileSync(commentPath, commentText(), {
              encoding: "utf8",
              mode: 0o600,
              flag: "wx",
            });
            try {
              await signRun(
                fort,
                "bd",
                ["comment", id, "--file", commentPath],
                { cwd },
              );
            } finally {
              fileSystem.unlinkSync(commentPath);
            }
          },
        ],
        [
          "remove-waiting",
          async () => {
            if (action === "comment") return;
            for (const label of fort.waitingLabels) {
              if (bead.labels?.includes(label))
                await signRun(
                  fort,
                  "bd",
                  ["update", id, "--remove-label", label],
                  { cwd },
                );
            }
          },
        ],
        [
          "restore-fleet-safe",
          async () => {
            if (
              action === "approve" &&
              !toMayor() &&
              !bead.labels?.includes("fleet-safe")
            ) {
              await signRun(
                fort,
                "bd",
                ["update", id, "--add-label", "fleet-safe"],
                { cwd },
              );
            }
          },
        ],
        [
          "route-mayor-review",
          async () => {
            if (
              action !== "comment" &&
              toMayor() &&
              !bead.labels?.includes("mayor-review")
            ) {
              await signRun(
                fort,
                "bd",
                ["update", id, "--add-label", "mayor-review"],
                { cwd },
              );
            }
          },
        ],
        [
          "emit",
          async () => {
            if (action === "comment") return;
            await signRun(
              fort,
              path.join(fort.repo, "fort/scripts/emit.sh"),
              [
                signEvents[action],
                `${id}: ${displayAction} — ${summary.slice(0, 100)}`,
                "-a",
                "justin",
                "-s",
                "overseer",
                "-t",
                id,
                ...(action === "approve" && fleet
                  ? ["-p", JSON.stringify({ approvedSha, branch })]
                  : []),
              ],
              { cwd },
            );
          },
        ],
        ["refresh", async () => refreshFort(entry)],
      ];
      for (const [name, effect] of steps) {
        try {
          await effect();
          completed.push(name);
        } catch (error) {
          if (completed.includes("audit")) {
            try {
              appendOutcome("failed", name);
            } catch (auditError) {
              log(`Civ Keep outcome audit failed for ${id}:`, auditError);
            }
          }
          log(`Civ Keep signing failed for ${id} at ${name}:`, error);
          return json(
            response,
            { error: error.message, failed: name, completed },
            500,
          );
        }
      }
      try {
        appendOutcome("completed", completed.at(-1));
      } catch (error) {
        return json(
          response,
          { error: error.message, failed: "outcome-audit", completed },
          500,
        );
      }
      const result = {
        ok: true,
        completed,
        fort: fort.key,
        bead: entry.byId.get(id) ?? bead,
      };
      for (const client of clients)
        client.write(
          `event: sign\ndata: ${JSON.stringify({ ok: true, id })}\n\n`,
        );
      return json(response, result);
    } finally {
      inFlight.delete(id);
    }
  }

  function renderAirlock(response) {
    const items = [];
    for (const fort of loadFortList()) {
      try {
        items.push(...pendingRequests(fort, { fileSystem, approvalsPath }));
      } catch (error) {
        log(`Civ Keep airlock read failed for ${fort.key}:`, error);
      }
    }
    return json(response, items);
  }

  // APPROVE AN AIRLOCK REQUEST (ForgeOs-72ot.1). Writes one line into the
  // Overseer store and announces it through that fort's emit.sh. It runs
  // nothing: `airlock.sh run` on the host does that, after checking this line
  // against the request's bytes.
  async function renderAirlockApprove(request, response) {
    const token = readToken(response);
    if (!token) return;
    if (!bearerMatches(request.headers.authorization, token))
      return json(response, { error: "Unauthorized" }, 401);
    const body = await readJson(request);
    const fort = loadFortList().find((item) => item.key === body.fort);
    if (!fort) return json(response, { error: "Unknown fort" }, 404);
    const id = typeof body.id === "string" ? body.id : "";
    const key = `airlock:${fort.key}:${id}`;
    if (inFlight.has(key))
      return json(response, { error: "Already in flight" }, 409);
    inFlight.add(key);
    try {
      const made = approvalLine(fort, id, {
        fileSystem,
        approvalsPath,
        now,
        expectedSha: body.requestSha256,
      });
      if (made.error) return json(response, { error: made.error }, made.status);
      fileSystem.mkdirSync(path.dirname(approvalsPath), {
        recursive: true,
        mode: 0o700,
      });
      fileSystem.appendFileSync(
        approvalsPath,
        `${JSON.stringify({
          ...made.line,
          tokenFingerprint: digest(token).toString("hex").slice(0, 12),
        })}\n`,
        { mode: 0o600 },
      );
      try {
        await signRun(
          fort,
          path.join(fort.repo, "fort/scripts/emit.sh"),
          [
            "airlock.approved",
            `${id}: Overseer approves ${made.request.operation} via the Civ Keep`,
            "-a",
            "justin",
            "-s",
            "overseer",
            "-t",
            id,
          ],
          { cwd: fort.repo },
        );
      } catch (error) {
        // The approval is in the store, which is what airlock.sh reads; the
        // announcement failing is reported, not rolled back.
        log(`Civ Keep airlock announcement failed for ${id}:`, error);
        return json(response, { ok: true, announced: false, line: made.line });
      }
      return json(response, { ok: true, announced: true, line: made.line });
    } finally {
      inFlight.delete(key);
    }
  }

  function renderPage(response, name) {
    response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    response.end(fileSystem.readFileSync(path.join(here, name), "utf8"));
  }

  function renderStatic(response, name) {
    if (!name || name.includes("/") || name.includes("..")) {
      response.writeHead(404);
      response.end("Not found");
      return;
    }
    const candidates = [
      path.join(here, "lib", name),
      name === "keep.css" ? path.join(here, "keep.css") : null,
    ].filter(Boolean);
    const file = candidates.find((candidate) => {
      try {
        return fileSystem.statSync(candidate).isFile();
      } catch {
        return false;
      }
    });
    if (!file) {
      response.writeHead(404);
      response.end("Not found");
      return;
    }
    const types = {
      ".js": "application/javascript",
      ".mjs": "application/javascript",
      ".css": "text/css",
    };
    response.writeHead(200, {
      "content-type": `${types[path.extname(name)] ?? "application/octet-stream"}; charset=utf-8`,
    });
    response.end(fileSystem.readFileSync(file));
  }

  function openEvents(request, response) {
    response.writeHead(200, {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive",
    });
    response.flushHeaders();
    clients.add(response);
    request.on("close", () => clients.delete(response));
  }

  async function route(request, response) {
    const url = new URL(request.url, "http://civ-keep.local");
    const p = url.pathname;
    if (p.startsWith("/static/"))
      return renderStatic(response, p.slice("/static/".length));
    if (p === "/" || p === "/board") return renderPage(response, "board.html");
    if (p === "/airlock") return renderPage(response, "airlock.html");
    if (p === "/graph" || p === "/beads")
      return renderPage(response, "graph.html");
    if (p === "/api/forts")
      return json(response, [...states.values()].map(fortSummary));
    if (p === "/api/graph") return renderGraph(response, url);
    if (p.startsWith("/api/bead/"))
      return renderApiBead(response, p.slice("/api/bead/".length));
    if (p === "/api/sign" && request.method === "POST")
      return renderSign(request, response);
    if (p === "/api/signatures") return renderSignatures(response, url);
    if (p === "/api/airlock" && request.method === "GET")
      return renderAirlock(response);
    if (p === "/api/airlock/approve" && request.method === "POST")
      return renderAirlockApprove(request, response);
    if (p === "/events") return openEvents(request, response);
    response.writeHead(404);
    response.end("Not found");
  }

  const server = http.createServer((request, response) => {
    Promise.resolve(route(request, response)).catch((error) => {
      if (!response.headersSent)
        json(response, { error: error.message }, error.status ?? 500);
      else response.end();
    });
  });

  return {
    server,
    states,
    refresh,
    close() {
      for (const entry of states.values()) entry.events.close?.();
      server.close();
    },
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const keep = createCivKeep();
  await keep.refresh();
  let running = false;
  setInterval(() => {
    if (running) return;
    running = true;
    keep
      .refresh()
      .catch(() => {})
      .finally(() => {
        running = false;
      });
  }, 60_000).unref();
  keep.server.listen(Number(process.env.KEEP_PORT ?? 7780), "127.0.0.1");
}

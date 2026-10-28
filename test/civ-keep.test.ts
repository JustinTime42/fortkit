// The Civ Keep's signing desk (civ/keep): what each action writes, in which fort,
// and what it refuses. Every process the desk starts goes through the real
// per-fort allowlist (civ/keep/lib/readers.mjs signCommand); only the final
// execFile is stubbed, so a write the allowlist would reject fails these tests.
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
// @ts-expect-error JavaScript library module.
import { prefixOf } from "../civ/keep/lib/forts.mjs";
// @ts-expect-error JavaScript library module.
import * as mayorSummary from "../civ/keep/lib/mayor-summary-extract.mjs";
// @ts-expect-error JavaScript library module.
import { signCommand } from "../civ/keep/lib/readers.mjs";
// @ts-expect-error JavaScript server module exercised through its HTTP seam.
import { createCivKeep } from "../civ/keep/server.mjs";

const {
  extractHighlights,
  findLiveMayor,
  mayorTranscriptPath,
  resolveBeadFacts,
  windowCounts,
} = mayorSummary;

type Call = { file: string; args: string[]; cwd: string };
type Bead = {
  id: string;
  title: string;
  status: string;
  labels: string[];
  description?: string;
  assignee?: string;
  comments?: { text: string }[];
};

const scratch = mkdtempSync(join(tmpdir(), "civ-keep-test-"));
const tokenPath = join(scratch, "token");
writeFileSync(tokenPath, "secret-token\n");

const forts = [
  {
    key: "proof",
    name: "Proof",
    project: "proof",
    civilization: "Justin",
    repo: "/srv/proof",
    mode: "fleet",
    fleetState: null,
    waitingLabels: ["human"],
  },
  {
    key: "halls",
    name: "Halls",
    project: "halls",
    civilization: "Justin",
    repo: "/srv/halls",
    mode: "plain",
    fleetState: null,
    waitingLabels: ["gate-1", "gate-2", "gate-3", "human"],
  },
  // ForgeOs-29j3g: a fort whose board is the ASSIGNEE, not a label set.
  {
    key: "whose",
    name: "Whose",
    project: "whose",
    civilization: "Justin",
    repo: "/srv/whose",
    mode: "fleet",
    fleetState: null,
    waitingLabels: ["human"],
    whoseMove: { assignee: "justin", mayor: "marrek" },
  },
];

const beads: Record<string, Bead[]> = {
  "/srv/proof": [
    { id: "proof-a1", title: "built", status: "open", labels: ["human"] },
    { id: "proof-b2", title: "no branch", status: "open", labels: ["human"] },
    { id: "proof-c3", title: "not waiting", status: "open", labels: [] },
    {
      id: "proof-d4",
      title: "decide",
      status: "open",
      labels: ["human"],
      description: "OPTION A: keep\nOPTION B: drop",
    },
  ],
  "/srv/halls": [
    { id: "halls-x1", title: "gated", status: "open", labels: ["gate-1"] },
  ],
  "/srv/whose": [
    {
      id: "whose-a1",
      title: "held for signature",
      status: "open",
      labels: ["human", "sign-to-land"],
      assignee: "justin",
      comments: [
        { text: "older note" },
        { text: "ASK: sign -- the Warden returned APPROVE" },
      ],
    },
    {
      id: "whose-b2",
      title: "parked by the Mayor",
      status: "open",
      labels: ["human"],
    },
    {
      id: "whose-c3",
      title: "fleet-escalated",
      status: "open",
      labels: ["fleet-escalated"],
      assignee: "marrek",
    },
    {
      id: "whose-d4",
      title: "grant, no branch",
      status: "open",
      labels: [],
      assignee: "justin",
      comments: [{ text: "ASK: grant -- push after the next green merge" }],
    },
  ],
};

let keep: ReturnType<typeof createCivKeep> | null = null;
afterEach(() => {
  keep?.close();
  keep = null;
});

async function start() {
  const calls: Call[] = [];
  const run = async (
    file: string,
    args: string[],
    options: { cwd: string },
  ) => {
    if (file === "bd" && args[0] === "export") {
      return `${(beads[options.cwd] ?? []).map((bead) => JSON.stringify(bead)).join("\n")}\n`;
    }
    calls.push({ file, args, cwd: options.cwd });
    if (file === "git") {
      if (args[3] === "bead/a1") return `${"a".repeat(40)}\n`;
      throw Object.assign(new Error("no such ref"), { code: 1 });
    }
    return "";
  };
  keep = createCivKeep({
    env: { HOME: scratch },
    run,
    tokenPath,
    auditPath: join(scratch, `audit-${Math.random()}`, "signatures.jsonl"),
    loadForts: () => forts,
    eventTail: () => ({ events: [], load() {}, scan() {}, close() {} }),
    exit: () => {},
    log: () => {},
  });
  await keep.refresh();
  await new Promise<void>((resolve) =>
    keep.server.listen(0, "127.0.0.1", resolve),
  );
  const port = (keep.server.address() as AddressInfo).port;
  const sign = async (body: object, token = "secret-token") => {
    const response = await fetch(`http://127.0.0.1:${port}/api/sign`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(body),
    });
    return {
      status: response.status,
      body: (await response.json()) as Record<string, unknown>,
    };
  };
  const writes = () =>
    calls
      .filter((call) => call.file !== "git")
      .map(
        (call) =>
          `${call.cwd} ${call.file.split("/").pop()} ${call.args.join(" ")}`,
      );
  return { port, sign, calls, writes };
}

describe("civ keep signing desk", () => {
  test("fleet fort, unnoted Approve with a branch: fleet-safe restored, sha pinned", async () => {
    const { sign, writes } = await start();
    const result = await sign({ id: "proof-a1", action: "approve", text: "" });
    expect(result.status).toBe(200);
    const done = writes();
    expect(done).toContain(
      "/srv/proof bd update proof-a1 --remove-label human",
    );
    expect(done).toContain(
      "/srv/proof bd update proof-a1 --add-label fleet-safe",
    );
    expect(done.some((line) => line.includes("mayor-review"))).toBe(false);
    expect(done.find((line) => line.includes("emit.sh"))).toContain(
      `"approvedSha":"${"a".repeat(40)}"`,
    );
  });

  test("fleet fort, unnoted Approve with no branch: routed to mayor-review", async () => {
    const { sign, writes } = await start();
    expect((await sign({ id: "proof-b2", action: "approve" })).status).toBe(
      200,
    );
    expect(writes()).toContain(
      "/srv/proof bd update proof-b2 --add-label mayor-review",
    );
    expect(writes().some((line) => line.includes("fleet-safe"))).toBe(false);
  });

  test("plain fort: Approve never adds fleet-safe and removes the fort's own gate label", async () => {
    const { sign, writes, calls } = await start();
    expect((await sign({ id: "halls-x1", action: "approve" })).status).toBe(
      200,
    );
    expect(writes()).toContain(
      "/srv/halls bd update halls-x1 --remove-label gate-1",
    );
    expect(writes()).toContain(
      "/srv/halls bd update halls-x1 --add-label mayor-review",
    );
    expect(writes().some((line) => line.includes("fleet-safe"))).toBe(false);
    expect(calls.some((call) => call.file === "git")).toBe(false);
    expect(calls.every((call) => call.cwd === "/srv/halls")).toBe(true);
  });

  test("Comment writes one bd comment and nothing else, on a bead that is not waiting", async () => {
    const { sign, writes } = await start();
    expect(
      (await sign({ id: "proof-c3", action: "comment", text: "look at this" }))
        .status,
    ).toBe(200);
    expect(writes()).toHaveLength(1);
    expect(writes()[0]).toMatch(/^\/srv\/proof bd comment proof-c3 --file /);
  });

  test("refusals: bad token, not waiting, missing note, unknown option, wrong fort", async () => {
    const { sign, writes } = await start();
    expect(
      (await sign({ id: "proof-a1", action: "approve" }, "wrong")).status,
    ).toBe(401);
    expect((await sign({ id: "proof-c3", action: "approve" })).status).toBe(
      409,
    );
    expect((await sign({ id: "proof-a1", action: "decline" })).status).toBe(
      400,
    );
    expect((await sign({ id: "proof-a1", action: "comment" })).status).toBe(
      400,
    );
    expect(
      (await sign({ id: "proof-d4", action: "decide", option: "Z", text: "x" }))
        .status,
    ).toBe(400);
    expect(
      (await sign({ id: "proof-a1", fort: "halls", action: "approve" })).status,
    ).toBe(409);
    expect((await sign({ id: "nowhere-1", action: "approve" })).status).toBe(
      404,
    );
    expect(writes()).toHaveLength(0);
  });

  test("Decide records the option and routes to the Mayor", async () => {
    const { sign, writes } = await start();
    expect(
      (
        await sign({
          id: "proof-d4",
          action: "decide",
          option: "B",
          text: "drop it",
        })
      ).status,
    ).toBe(200);
    expect(writes()).toContain(
      "/srv/proof bd update proof-d4 --add-label mayor-review",
    );
    expect(writes().find((line) => line.includes("emit.sh"))).toContain(
      "decision.recorded proof-d4: decide B",
    );
  });
});

describe("Mayor summary extraction", () => {
  test("selects only a live Mayor, never opening adjacent key files", () => {
    const root = mkdtempSync(join(tmpdir(), "mayor-sessions-"));
    const sessions = join(root, "sessions");
    mkdirSync(sessions);
    writeFileSync(
      join(sessions, "12.json"),
      JSON.stringify({
        pid: 12,
        startedAt: 1793095200000,
        sessionId: "mayor",
        cwd: "/srv/halls",
      }),
    );
    writeFileSync(
      join(sessions, "13.json"),
      JSON.stringify({
        pid: 13,
        startedAt: "2026-10-27T11:00:00Z",
        sessionId: "regent",
        cwd: "/srv/halls",
      }),
    );
    writeFileSync(
      join(sessions, "14.json"),
      JSON.stringify({
        pid: 14,
        startedAt: 1793200000000,
        sessionId: "dead",
        cwd: "/srv/halls",
      }),
    );
    writeFileSync(
      join(sessions, "15.json"),
      JSON.stringify({
        pid: 15,
        startedAt: 1793098800000,
        sessionId: "newer-mayor",
        cwd: "/srv/halls",
      }),
    );
    writeFileSync(join(sessions, "12.key"), "must not be opened");
    const reads: string[] = [];
    const fileSystem = {
      readdirSync: () => ["12.json", "12.key", "13.json", "14.json", "15.json"],
      readFileSync: (file: string) => {
        reads.push(file);
        if (file.endsWith("12.key")) throw new Error("secret read");
        if (file.endsWith("12.json"))
          return readFileSync(join(sessions, "12.json"), "utf8");
        if (file.endsWith("13.json"))
          return readFileSync(join(sessions, "13.json"), "utf8");
        if (file.endsWith("14.json"))
          return readFileSync(join(sessions, "14.json"), "utf8");
        if (file.endsWith("15.json"))
          return readFileSync(join(sessions, "15.json"), "utf8");
        if (file.endsWith("12/environ"))
          return "PATH=/x\0FORT_MASKED=mayor\0TOKEN=nope";
        if (file.endsWith("13/environ")) return "FORT_MASKED=regent";
        if (file.endsWith("14/environ")) return "FORT_MASKED=mayor";
        if (file.endsWith("15/environ")) return "NOISE=x\0FORT_MASKED=mayor";
        throw new Error("unexpected read");
      },
      existsSync: (file: string) =>
        file.endsWith("/12") || file.endsWith("/13") || file.endsWith("/15"),
      readlinkSync: (file: string) =>
        file.endsWith("/12/cwd") ||
        file.endsWith("/13/cwd") ||
        file.endsWith("/14/cwd") ||
        file.endsWith("/15/cwd")
          ? "/srv/halls"
          : "",
    };
    const mayor = findLiveMayor(
      { repo: "/srv/halls" },
      { fileSystem, sessionsDirectory: sessions, procRoot: "/proc" },
    );
    expect(mayor?.sessionId).toBe("newer-mayor");
    expect(mayor?.candidateCount).toBe(2);
    expect(reads.some((file) => file.endsWith(".key"))).toBe(false);
  });

  test("derives the Claude transcript path and reports a missing transcript", async () => {
    const transcript = mayorTranscriptPath(
      { cwd: "/srv/halls.with_name", sessionId: "mayor" },
      { home: "/home/tester" },
    );
    expect(transcript).toBe(
      "/home/tester/.claude/projects/-srv-halls-with-name/mayor.jsonl",
    );
    if (!transcript) throw new Error("transcript path was not derived");
    await expect(
      extractHighlights(transcript, "2026-10-27T10:00:00Z"),
    ).resolves.toEqual({
      highlights: [],
      malformedLines: 0,
      reason: "no live Mayor transcript",
    });
  });

  test("keeps only main-chain assistant text after the mark and computes facts", async () => {
    const root = mkdtempSync(join(tmpdir(), "mayor-transcript-"));
    const transcript = join(root, "mayor.jsonl");
    writeFileSync(
      transcript,
      [
        JSON.stringify({
          type: "assistant",
          timestamp: "2026-10-27T09:59:59Z",
          message: { content: [{ type: "text", text: "before halls-x1" }] },
        }),
        JSON.stringify({
          type: "assistant",
          timestamp: "2026-10-27T10:01:00Z",
          message: {
            content: [
              { type: "thinking", thinking: "no" },
              {
                type: "text",
                text: "Ship halls-x1 and proof-a1, inspect halls-missing and halls-worktrees.",
              },
              { type: "tool_use", name: "bd" },
            ],
          },
        }),
        JSON.stringify({
          type: "user",
          timestamp: "2026-10-27T10:02:00Z",
          message: {
            content: [{ type: "text", text: "tool result halls-secret" }],
          },
        }),
        JSON.stringify({
          type: "system",
          timestamp: "2026-10-27T10:03:00Z",
          message: { content: [{ type: "text", text: "system" }] },
        }),
        JSON.stringify({
          type: "attachment",
          timestamp: "2026-10-27T10:03:30Z",
        }),
        JSON.stringify({
          type: "file-history-snapshot",
          timestamp: "2026-10-27T10:03:40Z",
        }),
        JSON.stringify({
          type: "assistant",
          isSidechain: true,
          timestamp: "2026-10-27T10:04:00Z",
          message: { content: [{ type: "text", text: "sidechain" }] },
        }),
        "not json",
      ].join("\n"),
    );
    const extracted = await extractHighlights(
      transcript,
      "2026-10-27T10:00:00Z",
    );
    expect(extracted).toEqual({
      highlights: [
        {
          timestamp: "2026-10-27T10:01:00Z",
          text: "Ship halls-x1 and proof-a1, inspect halls-missing and halls-worktrees.",
        },
      ],
      malformedLines: 1,
    });
    const states = [
      {
        fort: { key: "halls", prefix: "halls" },
        byId: new Map([
          [
            "halls-x1",
            {
              id: "halls-x1",
              title: "Gated work",
              status: "open",
              labels: ["gate-1"],
            },
          ],
        ]),
      },
      {
        fort: { key: "proof", prefix: "proof" },
        byId: new Map([
          [
            "proof-a1",
            { id: "proof-a1", title: "Built", status: "closed", labels: [] },
          ],
        ]),
      },
    ];
    expect(resolveBeadFacts(extracted.highlights, states)).toEqual([
      {
        id: "halls-x1",
        fort: "halls",
        title: "Gated work",
        status: "open",
        assignee: null,
        labels: ["gate-1"],
      },
      {
        id: "proof-a1",
        fort: "proof",
        title: "Built",
        status: "closed",
        assignee: null,
        labels: [],
      },
      { id: "halls-missing", status: "unknown" },
    ]);
  });

  test("computes counts from the export, full event window, and existing waiting rule", () => {
    const root = mkdtempSync(join(tmpdir(), "mayor-counts-"));
    const events = join(root, "fort/events");
    mkdirSync(events, { recursive: true });
    writeFileSync(
      join(events, "events-2026-10-26.jsonl"),
      [
        JSON.stringify({ ts: "2026-10-27T10:01:00Z", category: "merge" }),
        JSON.stringify({
          ts: "2026-10-27T10:02:00Z",
          category: "halt",
          target: "halls-x2",
          detail: "disk full",
        }),
        JSON.stringify({
          ts: "2026-10-27T10:03:00Z",
          category: "review.verdict",
          target: "halls-x1",
          payload: { verdict: "APPROVE" },
        }),
        JSON.stringify({
          ts: "2026-10-27T10:03:15Z",
          category: "review.verdict",
          target: "halls-x2",
          detail: "free-form review note, not a verdict",
        }),
        JSON.stringify({
          ts: "2026-10-27T10:04:00Z",
          category: "gate.approved",
          target: "halls-x1",
        }),
      ].join("\n"),
    );
    const beads = new Map([
      [
        "halls-x1",
        {
          id: "halls-x1",
          status: "open",
          labels: ["gate-1"],
          created_at: "2026-10-27T10:01:00Z",
        },
      ],
      [
        "halls-x2",
        {
          id: "halls-x2",
          status: "closed",
          labels: [],
          closed_at: "2026-10-27T10:02:00Z",
        },
      ],
      ["halls-x3", { id: "halls-x3", status: "open", labels: [] }],
    ]);
    const entry = {
      fort: { repo: root, waitingLabels: ["gate-1"] },
      byId: beads,
      events: {
        events: [
          {
            ts: "2026-10-27T10:03:30Z",
            category: "review.verdict",
            target: "halls-x3",
            payload: { verdict: "ESCALATE" },
          },
        ],
      },
      fleet: { workers: [] },
    };
    expect(
      windowCounts(entry, "2026-10-27T10:00:00Z", "2026-10-27T10:05:00Z"),
    ).toEqual({
      closed: 1,
      filed: 1,
      merged: 1,
      halts: [{ target: "halls-x2", reason: "disk full" }],
      wardenVerdicts: [
        { id: "halls-x1", verdict: "APPROVE" },
        { id: "halls-x2", verdict: null },
      ],
      gateDecisions: [{ category: "gate.approved", id: "halls-x1" }],
      waitingOnOverseer: ["halls-x1", "halls-x3"],
    });
  });
});

describe("civ keep allowlist", () => {
  const fort = { ...forts[1], prefix: "halls" };
  const ok = async () => "ran";
  test("rejects another fort's id, another fort's tree, and labels the fort does not use", () => {
    expect(() =>
      signCommand(
        fort,
        "bd",
        ["update", "proof-a1", "--remove-label", "human"],
        { cwd: "/srv/halls" },
        ok,
      ),
    ).toThrow(/rejected/);
    expect(() =>
      signCommand(
        fort,
        "bd",
        ["update", "halls-x1", "--remove-label", "gate-1"],
        { cwd: "/srv/proof" },
        ok,
      ),
    ).toThrow(/rejected/);
    expect(() =>
      signCommand(
        fort,
        "bd",
        ["update", "halls-x1", "--add-label", "fleet-safe"],
        { cwd: "/srv/halls" },
        ok,
      ),
    ).toThrow(/rejected/);
    expect(() =>
      signCommand(fort, "bd", ["close", "halls-x1"], { cwd: "/srv/halls" }, ok),
    ).toThrow(/rejected/);
    expect(
      signCommand(
        fort,
        "bd",
        ["update", "halls-x1", "--remove-label", "gate-1"],
        { cwd: "/srv/halls" },
        ok,
      ),
    ).resolves.toBe("ran");
  });

  test("the prefix is the segment before the FIRST dash", () => {
    expect(
      prefixOf([
        { id: "plot-merge-slot" },
        { id: "plot-a1" },
        { id: "plot-b2.1" },
      ]),
    ).toBe("plot");
  });
});

// The Overseer store (ForgeOs-72ot.1, ForgeOs-ubgx.4): airlock approvals and the
// signing pin are written into the store beside the audit, and nowhere else.
describe("civ keep overseer store", () => {
  async function storeKeep() {
    const repo = mkdtempSync(join(tmpdir(), "civ-keep-airlock-"));
    mkdirSync(join(repo, "fort/airlock/requests"), { recursive: true });
    mkdirSync(join(repo, "fort/airlock/results"), { recursive: true });
    writeFileSync(
      join(repo, "fort/airlock/operations.json"),
      JSON.stringify({
        operations: [
          {
            name: "deploy-staging",
            requires_approval: true,
            runs_from: "pinned-commit",
            description: "d",
          },
          { name: "feedback-scan", requires_approval: false, description: "f" },
        ],
      }),
    );
    const request = (id: string, operation: string, status = "pending") =>
      writeFileSync(
        join(repo, "fort/airlock/requests", `${id}.json`),
        `${JSON.stringify({ id, operation, reason: "why", requested_by: "marrek", seat: "mayor", commit: "c".repeat(40), status, params: {} }, null, 2)}\n`,
      );
    request("20261006T090000-deploy-staging-1", "deploy-staging");
    request("20261006T090001-feedback-scan-2", "feedback-scan");
    request("20261006T090002-deploy-staging-3", "deploy-staging", "completed");
    const store = mkdtempSync(join(tmpdir(), "civ-keep-store-"));
    const auditPath = join(store, "signatures.jsonl");
    const fort = {
      key: "proof",
      name: "Proof",
      project: "proof",
      civilization: "Justin",
      repo,
      mode: "fleet",
      fleetState: null,
      waitingLabels: ["human"],
    };
    const calls: Call[] = [];
    let pinAtFirstBd: boolean | null = null;
    const run = async (
      file: string,
      args: string[],
      options: { cwd: string },
    ) => {
      if (file === "bd" && args[0] === "export")
        return `${JSON.stringify({ id: "proof-a1", title: "t", status: "open", labels: ["human"] })}\n`;
      calls.push({ file, args, cwd: options.cwd });
      if (file === "bd" && pinAtFirstBd === null) {
        let audit = "";
        try {
          audit = readFileSync(auditPath, "utf8");
        } catch {}
        pinAtFirstBd = audit.includes('"step":"pin"');
      }
      if (file === "git") return `${"a".repeat(40)}\n`;
      return "";
    };
    keep = createCivKeep({
      env: { HOME: scratch },
      run,
      tokenPath,
      auditPath,
      loadForts: () => [fort],
      eventTail: () => ({ events: [], load() {}, scan() {}, close() {} }),
      exit: () => {},
      log: () => {},
    });
    await keep.refresh();
    await new Promise<void>((resolve) =>
      keep.server.listen(0, "127.0.0.1", resolve),
    );
    const port = (keep.server.address() as AddressInfo).port;
    const base = `http://127.0.0.1:${port}`;
    const approve = async (body: object, token = "secret-token") => {
      const response = await fetch(`${base}/api/airlock/approve`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(body),
      });
      return { status: response.status, body: await response.json() };
    };
    const listed = async () =>
      (await (await fetch(`${base}/api/airlock`)).json()) as {
        id: string;
        requestSha256: string;
      }[];
    return {
      repo,
      store,
      auditPath,
      calls,
      base,
      approve,
      listed,
      pinAtFirstBd: () => pinAtFirstBd,
    };
  }
  const lines = (file: string) =>
    readFileSync(file, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((line) => JSON.parse(line));

  // ForgeOs-emshb: the Airlock page links the newest preview URLs, and only
  // local http ones from a successful preview result (results/ is seat-writable).
  test("lists recent preview URLs and refuses any that are not a local preview", async () => {
    const { base, repo } = await storeKeep();
    const result = (id: string, body: object) =>
      writeFileSync(
        join(repo, "fort/airlock/results", `${id}.json`),
        JSON.stringify({ id, ...body }),
      );
    result("20261023T100000-preview-1", {
      operation: "preview",
      exit_code: 0,
      url: "http://localhost:5173",
      commit: "d".repeat(40),
      ended_at: "2026-10-23T10:00:05-08:00",
    });
    result("20261023T110000-preview-2", {
      operation: "preview",
      exit_code: 0,
      url: "http://127.0.0.1:5173/",
      ended_at: "2026-10-23T11:00:05-08:00",
    });
    result("20261023T100100-preview-3", {
      operation: "preview",
      exit_code: 0,
      url: "http://evil.example:80/",
      ended_at: "2026-10-23T12:00:00-08:00",
    });
    result("20261023T100200-preview-4", {
      operation: "preview",
      exit_code: 0,
      url: "javascript:alert(1)//localhost:5173",
    });
    result("20261023T100300-preview-5", {
      operation: "preview",
      exit_code: 1,
      url: "http://localhost:5173",
    });
    result("20261023T100400-host-test-6", {
      operation: "host-test",
      exit_code: 0,
      url: "http://localhost:5173",
    });
    const items = (await (
      await fetch(`${base}/api/airlock/previews`)
    ).json()) as { id: string; url: string }[];
    expect(items.map((item) => [item.id, item.url])).toEqual([
      ["20261023T110000-preview-2", "http://127.0.0.1:5173/"],
      ["20261023T100000-preview-1", "http://localhost:5173"],
    ]);
  });

  test("lists only pending requests whose operation requires approval", async () => {
    const { base } = await storeKeep();
    const items = (await (await fetch(`${base}/api/airlock`)).json()) as {
      id: string;
      commit: string;
      runsFrom: string;
    }[];
    expect(items.map((item) => item.id)).toEqual([
      "20261006T090000-deploy-staging-1",
    ]);
    // ForgeOs-mbv54: the approve view carries the commit the run will build.
    expect(items[0]).toMatchObject({
      commit: "c".repeat(40),
      runsFrom: "pinned-commit",
    });
  });

  test("Approve writes one store line pinning the request's bytes, announces it, and cannot repeat", async () => {
    const { repo, store, calls, approve, base, listed } = await storeKeep();
    const id = "20261006T090000-deploy-staging-1";
    const shown = (await listed())[0]?.requestSha256 ?? "";
    expect(
      (await approve({ fort: "proof", id, requestSha256: shown }, "wrong"))
        .status,
    ).toBe(401);
    expect((await approve({ fort: "proof", id })).status).toBe(400);
    const result = await approve({ fort: "proof", id, requestSha256: shown });
    expect(result.status).toBe(200);
    const [line] = lines(join(store, "airlock-approvals.jsonl"));
    const bytes = readFileSync(
      join(repo, "fort/airlock/requests", `${id}.json`),
    );
    expect(line).toMatchObject({
      fort: "proof",
      repo,
      id,
      operation: "deploy-staging",
      actor: "justin",
      via: "civ-keep",
      requestSha256: createHash("sha256").update(bytes).digest("hex"),
    });
    expect(
      calls.map(
        (call) =>
          `${call.file.split("/").pop()} ${call.args.slice(0, 2).join(" ")}`,
      ),
    ).toEqual([
      `emit.sh airlock.approved ${id}: Overseer approves deploy-staging via the Civ Keep`,
    ]);
    expect(
      (await approve({ fort: "proof", id, requestSha256: shown })).status,
    ).toBe(409);
    expect(await (await fetch(`${base}/api/airlock`)).json()).toEqual([]);
    expect(
      (
        await approve({
          fort: "proof",
          id: "20261006T090001-feedback-scan-2",
          requestSha256: "f".repeat(64),
        })
      ).status,
    ).toBe(409);
    expect((await approve({ fort: "proof", id: "../../etc" })).status).toBe(
      400,
    );
  });

  test("Approve refuses a request edited after it was displayed (Ilva, the blocking finding)", async () => {
    const { repo, store, approve, listed } = await storeKeep();
    const id = "20261006T090000-deploy-staging-1";
    const shown = (await listed())[0]?.requestSha256 ?? "";
    const file = join(repo, "fort/airlock/requests", `${id}.json`);
    const edited = JSON.parse(readFileSync(file, "utf8"));
    edited.params = { image: "something-else" };
    writeFileSync(file, `${JSON.stringify(edited, null, 2)}\n`);
    const result = await approve({ fort: "proof", id, requestSha256: shown });
    expect(result.status).toBe(409);
    expect(() =>
      readFileSync(join(store, "airlock-approvals.jsonl")),
    ).toThrow();
    const fresh = (await listed())[0]?.requestSha256 ?? "";
    expect(fresh).not.toBe(shown);
    expect(
      (await approve({ fort: "proof", id, requestSha256: fresh })).status,
    ).toBe(200);
  });

  test("a signing Approve pins the approvedSha in the audit, before any bd write", async () => {
    const { auditPath, calls, base, pinAtFirstBd } = await storeKeep();
    const response = await fetch(`${base}/api/sign`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: "Bearer secret-token",
      },
      body: JSON.stringify({ id: "proof-a1", action: "approve", text: "" }),
    });
    expect(response.status).toBe(200);
    const pin = lines(auditPath).find((line) => line.step === "pin");
    expect(pin).toMatchObject({
      fort: "proof",
      bead: "proof-a1",
      approvedSha: "a".repeat(40),
      branch: "bead/a1",
    });
    expect(calls.findIndex((call) => call.file === "bd")).toBeGreaterThan(
      calls.findIndex((call) => call.file === "git"),
    );
    // The property itself (Ilva, finding 2): the pin line was already in the
    // audit at the moment of the first bd call.
    expect(pinAtFirstBd()).toBe(true);
  });
});

// ForgeOs-29j3g: in a fort that sets whoseMove, the board is exactly the open
// beads assigned to the Overseer, and every answer moves the assignee on.
describe("civ keep whose-move fort", () => {
  test("the board is the assignee: two beads assigned to him, the parked and the Mayor's are not", async () => {
    const { port, sign } = await start();
    const summary = (await (
      await fetch(`http://127.0.0.1:${port}/api/forts`)
    ).json()) as {
      key: string;
      needsYou: number;
    }[];
    expect(summary.find((fort) => fort.key === "whose")?.needsYou).toBe(2);
    const bead = (await (
      await fetch(`http://127.0.0.1:${port}/api/bead/whose-a1`)
    ).json()) as {
      needsYou: { why: string; ask: string; detail: string };
    };
    expect(bead.needsYou).toMatchObject({
      why: "assigned to you",
      ask: "ASK: sign -- the Warden returned APPROVE",
      detail: "ASK: sign -- the Warden returned APPROVE",
    });
    expect((await sign({ id: "whose-b2", action: "approve" })).status).toBe(
      409,
    );
    expect((await sign({ id: "whose-c3", action: "approve" })).status).toBe(
      409,
    );
  });

  test("an unnoted Approve with a branch clears the assignee BEFORE fleet-safe returns", async () => {
    const { sign, writes } = await start();
    expect(
      (await sign({ id: "whose-a1", action: "approve", text: "" })).status,
    ).toBe(200);
    const done = writes();
    const move = done.indexOf("/srv/whose bd update whose-a1 --assignee ");
    const safe = done.indexOf(
      "/srv/whose bd update whose-a1 --add-label fleet-safe",
    );
    expect(move).toBeGreaterThanOrEqual(0);
    expect(safe).toBeGreaterThan(move);
    expect(done.some((line) => line.includes("--assignee marrek"))).toBe(false);
  });

  test("a Decline, and an Approve with no branch, assign the bead to the Mayor", async () => {
    const declined = await start();
    expect(
      (
        await declined.sign({
          id: "whose-a1",
          action: "decline",
          text: "not this",
        })
      ).status,
    ).toBe(200);
    expect(declined.writes()).toContain(
      "/srv/whose bd update whose-a1 --assignee marrek",
    );
    keep?.close();
    keep = null;
    const nobranch = await start();
    expect(
      (await nobranch.sign({ id: "whose-d4", action: "approve" })).status,
    ).toBe(200);
    expect(nobranch.writes()).toContain(
      "/srv/whose bd update whose-d4 --assignee marrek",
    );
    expect(nobranch.writes()).toContain(
      "/srv/whose bd update whose-d4 --add-label mayor-review",
    );
  });

  test("a label-set fort never moves an assignee, and the allowlist admits only '' or that fort's Mayor", async () => {
    const { sign, writes } = await start();
    expect(
      (await sign({ id: "proof-a1", action: "approve", text: "" })).status,
    ).toBe(200);
    expect(writes().some((line) => line.includes("--assignee"))).toBe(false);
    const ok = async () => "ran";
    const whose = { ...forts[2], prefix: "whose" };
    const proof = { ...forts[0], prefix: "proof" };
    for (const who of ["justin", "veyra"]) {
      expect(() =>
        signCommand(
          whose,
          "bd",
          ["update", "whose-a1", "--assignee", who],
          { cwd: "/srv/whose" },
          ok,
        ),
      ).toThrow(/rejected/);
    }
    expect(() =>
      signCommand(
        proof,
        "bd",
        ["update", "proof-a1", "--assignee", ""],
        { cwd: "/srv/proof" },
        ok,
      ),
    ).toThrow(/rejected/);
    await expect(
      signCommand(
        whose,
        "bd",
        ["update", "whose-a1", "--assignee", "marrek"],
        { cwd: "/srv/whose" },
        ok,
      ),
    ).resolves.toBe("ran");
  });
});

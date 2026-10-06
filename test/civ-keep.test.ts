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
import { signCommand } from "../civ/keep/lib/readers.mjs";
// @ts-expect-error JavaScript server module exercised through its HTTP seam.
import { createCivKeep } from "../civ/keep/server.mjs";

type Call = { file: string; args: string[]; cwd: string };
type Bead = {
  id: string;
  title: string;
  status: string;
  labels: string[];
  description?: string;
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
          { name: "deploy-staging", requires_approval: true, description: "d" },
          { name: "feedback-scan", requires_approval: false, description: "f" },
        ],
      }),
    );
    const request = (id: string, operation: string, status = "pending") =>
      writeFileSync(
        join(repo, "fort/airlock/requests", `${id}.json`),
        `${JSON.stringify({ id, operation, reason: "why", requested_by: "marrek", seat: "mayor", status, params: {} }, null, 2)}\n`,
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
    const run = async (
      file: string,
      args: string[],
      options: { cwd: string },
    ) => {
      if (file === "bd" && args[0] === "export")
        return `${JSON.stringify({ id: "proof-a1", title: "t", status: "open", labels: ["human"] })}\n`;
      calls.push({ file, args, cwd: options.cwd });
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
    return { repo, store, auditPath, calls, base, approve };
  }
  const lines = (file: string) =>
    readFileSync(file, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((line) => JSON.parse(line));

  test("lists only pending requests whose operation requires approval", async () => {
    const { base } = await storeKeep();
    const items = (await (await fetch(`${base}/api/airlock`)).json()) as {
      id: string;
    }[];
    expect(items.map((item) => item.id)).toEqual([
      "20261006T090000-deploy-staging-1",
    ]);
  });

  test("Approve writes one store line pinning the request's bytes, announces it, and cannot repeat", async () => {
    const { repo, store, calls, approve, base } = await storeKeep();
    const id = "20261006T090000-deploy-staging-1";
    expect((await approve({ fort: "proof", id }, "wrong")).status).toBe(401);
    const result = await approve({ fort: "proof", id });
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
    expect((await approve({ fort: "proof", id })).status).toBe(409);
    expect(await (await fetch(`${base}/api/airlock`)).json()).toEqual([]);
    expect(
      (await approve({ fort: "proof", id: "20261006T090001-feedback-scan-2" }))
        .status,
    ).toBe(409);
    expect((await approve({ fort: "proof", id: "../../etc" })).status).toBe(
      400,
    );
  });

  test("a signing Approve pins the approvedSha in the audit, before any bd write", async () => {
    const { auditPath, calls, base } = await storeKeep();
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
  });
});

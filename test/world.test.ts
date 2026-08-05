import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, test, vi } from "vitest";

import {
  createWorldHandler,
  createWorldServer,
  worldPage,
} from "../src/server.js";
import { readWorld } from "../src/world.js";

const fixtureRoot = fileURLToPath(new URL("./fixtures", import.meta.url));
const registryPath = join(fixtureRoot, "world-civilization.json");

describe("world view", () => {
  test("projects available, absent, and malformed fort sources without inventing health", async () => {
    const forts = await readWorld(registryPath);
    expect(forts).toHaveLength(3);
    expect(forts[0]).toMatchObject({
      name: "Alpha",
      beads: { ready: 1, malformed: 1 },
      inProgress: [
        {
          id: "b",
          title: "Build a bridge",
          seat: "forge",
          model: "gpt-5.6-terra",
        },
      ],
      announcements: [
        "Watch the gate",
        "Build a bridge",
        "UTC next day",
        "Earlier instant",
      ],
      watcherAlerts: [
        { detail: "Watch the gate", ts: "2026-08-04T08:26:00.000Z" },
      ],
    });
    expect(forts[0]?.gaps).toContain("1 malformed Beads record(s)");
    expect(forts[1]).toMatchObject({
      name: "No Beads",
      beads: null,
      inProgress: [],
      gaps: ["Beads export ABSENT", "event stream ABSENT"],
    });
    expect(forts[2]).toMatchObject({
      name: "Missing",
      present: false,
      gaps: ["fort directory is absent"],
    });
  });

  test("has a self-contained polling page", () => {
    expect(worldPage).toContain("fetch('/world')");
    expect(worldPage).toContain("setInterval(load,5000)");
  });

  test("caps watcher alerts and timestamps each entry", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-world-"));
    const fort = join(root, "fort");
    const events = join(fort, "fort", "events");
    try {
      await mkdir(events, { recursive: true });
      await writeFile(
        join(events, "events-2026-08-04.jsonl"),
        Array.from({ length: 6 }, (_, index) =>
          JSON.stringify({
            ts: `2026-08-04T08:2${index}:00Z`,
            actor: "watcher:test",
            seat: null,
            category: "watcher.alert",
            target: null,
            detail: `Alert ${index}`,
            payload: null,
          }),
        ).join("\n"),
      );
      const temporaryRegistry = join(root, "civilization.json");
      await writeFile(
        temporaryRegistry,
        JSON.stringify({ forts: [{ fort_name: "Temporary", repo: fort }] }),
      );
      const [temporary] = await readWorld(temporaryRegistry);
      expect(temporary?.watcherAlerts).toEqual([
        { detail: "Alert 5", ts: "2026-08-04T08:25:00.000Z" },
        { detail: "Alert 4", ts: "2026-08-04T08:24:00.000Z" },
        { detail: "Alert 3", ts: "2026-08-04T08:23:00.000Z" },
        { detail: "Alert 2", ts: "2026-08-04T08:22:00.000Z" },
        { detail: "Alert 1", ts: "2026-08-04T08:21:00.000Z" },
      ]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("rejects foreign Hosts and serves loopback Hosts", async () => {
    const handler = createWorldHandler(registryPath);
    const response = () => {
      let status = 0;
      let body = "";
      return {
        writeHead: (code: number) => {
          status = code;
        },
        end: (value: string) => {
          body = value;
        },
        result: () => ({ status, body }),
      };
    };
    const foreign = response();
    await handler(
      { url: "/world", headers: { host: "example.test" } } as never,
      foreign as never,
    );
    expect(foreign.result()).toMatchObject({
      status: 403,
      body: '{"error":"Forbidden host"}',
    });
    for (const host of ["localhost:4877", "127.0.0.1:4877"]) {
      const loopback = response();
      await handler(
        { url: "/world", headers: { host } } as never,
        loopback as never,
      );
      expect(loopback.result().status).toBe(200);
    }
  });

  test("returns JSON 500 when projection fails", async () => {
    const handler = createWorldHandler(registryPath, async () => {
      throw new Error("fixture failure");
    });
    let status = 0;
    let body = "";
    await handler(
      { url: "/world", headers: { host: "localhost" } } as never,
      {
        writeHead: (code: number) => {
          status = code;
        },
        end: (value: string) => {
          body = value;
        },
      } as never,
    );
    expect(status).toBe(500);
    expect(body).toBe('{"error":"World data unavailable"}');
  });

  test("handles server errors without an unhandled error event", () => {
    const error = vi
      .spyOn(console, "error")
      .mockImplementation(() => undefined);
    const server = createWorldServer(registryPath);
    expect(() =>
      server.emit("error", new Error("address in use")),
    ).not.toThrow();
    expect(error).toHaveBeenCalledWith(
      "fortkit world server error: address in use",
    );
    error.mockRestore();
  });
});

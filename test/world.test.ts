import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, Script } from "node:vm";

import { describe, expect, test, vi } from "vitest";

import { readLatestHandoffs } from "../src/readers/handoffs.js";
import {
  colonyPage,
  composeColonyPage,
  composeWorldPage,
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
      beads: { open: 4, malformed: 1 },
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
    });
    expect(forts[1]?.gaps).toEqual(
      expect.arrayContaining(["Beads export ABSENT", "event stream ABSENT"]),
    );
    expect(forts[2]).toMatchObject({
      name: "Missing",
      present: false,
      gaps: ["fort directory is absent"],
    });
  });

  test("has a self-contained polling page", () => {
    expect(worldPage).not.toContain("<!-- world-page-script -->");
    expect(worldPage).toContain("<title>Bartizan — world</title>");
    expect(worldPage).toContain("Bartizan — Manyhalls world view");
    expect(worldPage).toContain('fetch("/world")');
    expect(worldPage).toContain("setInterval(load, 5000)");
    expect(worldPage).toContain(`open \${fort.beads.open}`);
    expect(worldPage).not.toContain("ready");
    expect(worldPage).toContain("/colony-view?fort=");
  });

  test("has a checked canvas colony page with distinct actor styles", () => {
    expect(colonyPage).not.toContain("<!-- colony-page-script -->");
    expect(colonyPage).toContain("<title>Bartizan — colony</title>");
    expect(colonyPage).toContain('id="colony-title"');
    expect(colonyPage).not.toContain('id="ticker" aria-live');
    expect(colonyPage).toContain('<canvas id="colony"');
    expect(colonyPage).toContain("fetch(`/colony?fort=");
    const script = colonyPage.match(/<script>([\s\S]*?)<\/script>/)?.[1];
    expect(script).toBeDefined();
    if (script === undefined) throw new Error("colony page script is missing");
    const context = createContext({
      fetch: () => new Promise(() => undefined),
      setInterval: () => undefined,
      location: { search: "" },
      document: { querySelector: () => null },
      URLSearchParams,
    });
    new Script(script).runInContext(context);
    const styles = (
      context.actorStyles as (projection: unknown) => Map<string, unknown>
    )({
      citizens: [
        { name: "Emrith Cairnwright", pronouns: "she/her", seat: "Mayor" },
        { name: "Kethra Anvilmark", pronouns: "she/her", seat: "Forge" },
        { name: "Ilva Trueglass", pronouns: "she/her", seat: "Warden" },
      ],
      benches: [],
    });
    const rendered = [...styles.values()].map((style) => JSON.stringify(style));
    expect(new Set(rendered).size).toBe(rendered.length);
  });

  test("names the colony tab and header after its selected fort", async () => {
    const script = colonyPage.match(/<script>([\s\S]*?)<\/script>/)?.[1];
    expect(script).toBeDefined();
    if (script === undefined) throw new Error("colony page script is missing");
    const title = { textContent: "Bartizan — colony" };
    const document = {
      title: "Bartizan — colony",
      querySelector: (selector: string) =>
        selector === "#colony-title" ? title : null,
    };
    const context = createContext({
      fetch: () => new Promise(() => undefined),
      setInterval: () => undefined,
      location: { search: "?fort=Alpha%20Fort" },
      document,
      URLSearchParams,
    });
    new Script(script).runInContext(context);

    expect(document.title).toBe("Bartizan — Alpha Fort colony");
    expect(title.textContent).toBe("Bartizan — Alpha Fort colony");
  });

  test("labels truncated building rows and wraps citizens after six columns", () => {
    const script = colonyPage.match(/<script>([\s\S]*?)<\/script>/)?.[1];
    expect(script).toBeDefined();
    if (script === undefined) throw new Error("colony page script is missing");
    const fillText = vi.fn();
    const canvas = {
      width: 1100,
      height: 620,
      getContext: () => ({
        fillStyle: "",
        strokeStyle: "",
        font: "",
        fillRect: vi.fn(),
        strokeRect: vi.fn(),
        fillText,
      }),
    };
    const context = createContext({
      fetch: () => new Promise(() => undefined),
      setInterval: () => undefined,
      location: { search: "" },
      document: {
        querySelector: (selector: string) =>
          selector === "#colony" ? canvas : { textContent: "", innerHTML: "" },
      },
      URLSearchParams,
    });
    new Script(script).runInContext(context);
    (
      context.building as (
        context: unknown,
        x: number,
        y: number,
        name: string,
        details: string[],
        color: string,
      ) => void
    )(
      canvas.getContext(),
      0,
      0,
      "TEST",
      Array.from(
        { length: 7 },
        (_, index) => `detail-${index}-${"x".repeat(30)}`,
      ),
      "#000",
    );
    expect(fillText.mock.calls.map(([value]) => value)).toEqual(
      expect.arrayContaining([`detail-0-${"x".repeat(17)}…`, "… +3 more"]),
    );

    (context.render as (projection: unknown) => void)({
      workshops: [],
      benches: [],
      dungeon: [],
      citizens: Array.from({ length: 7 }, (_, index) => ({
        name: `Citizen ${index + 1}`,
        pronouns: "they/them",
        seat: "forge",
        personality: null,
        currentBead: null,
        lastHandoff: null,
      })),
      unassigned: [],
      announcements: [],
      gaps: [],
    });
    expect(canvas.height).toBe(646);
    expect(fillText).toHaveBeenCalledWith("Citizen 7 (they/them)", 48, 598);
  });

  test("renders colony projection fixtures as named fort buildings and a ticker", () => {
    const script = colonyPage.match(/<script>([\s\S]*?)<\/script>/)?.[1];
    expect(script).toBeDefined();
    if (script === undefined) throw new Error("colony page script is missing");
    const fillText = vi.fn();
    const canvas = {
      width: 1100,
      height: 620,
      getContext: () => ({
        fillStyle: "",
        strokeStyle: "",
        font: "",
        fillRect: vi.fn(),
        strokeRect: vi.fn(),
        fillText,
      }),
    };
    const ticker = { textContent: "" };
    const gaps = { textContent: "" };
    const detailPanel = { textContent: "", innerHTML: "" };
    const context = createContext({
      fetch: () => new Promise(() => undefined),
      setInterval: () => undefined,
      location: { search: "" },
      document: {
        querySelector: (selector: string) =>
          selector === "#colony"
            ? canvas
            : selector === "#ticker"
              ? ticker
              : selector === "#gaps"
                ? gaps
                : selector === "#detail-panel"
                  ? detailPanel
                  : null,
      },
      URLSearchParams,
    });
    new Script(script).runInContext(context);
    (context.render as (projection: unknown) => void)({
      workshops: [
        { type: "implementation", beads: [{ id: "a", title: "Build" }] },
      ],
      benches: [],
      dungeon: [{ id: "bug", title: "Repair" }],
      citizens: [
        {
          name: "Kethra",
          pronouns: "she/her",
          seat: "forge",
          personality: null,
          currentBead: null,
          lastHandoff: null,
        },
      ],
      unassigned: [{ id: "intake", title: null }],
      announcements: ["The gate is watched"],
      gaps: ["event stream ABSENT"],
    });
    expect(fillText.mock.calls.map(([value]) => value)).toEqual(
      expect.arrayContaining([
        "GATE",
        "TRADE DEPOT",
        "ARCHIVE",
        "DUNGEON",
        "IMPLEMENTATION WORKSHOP",
        "Kethra (she/her)",
      ]),
    );
    expect(ticker.textContent).toBe("The gate is watched");
    expect(gaps.textContent).toContain("event stream ABSENT");
  });

  test("composes literal dollar sequences without replacement expansion", () => {
    const script = 'const token = "$& $` $\' $$";';
    const page = composeWorldPage(
      "<body><!-- world-page-script --></body>",
      script,
    );

    expect(page).toContain(script);
  });

  test("rejects a page template without a script marker", () => {
    expect(() => composeWorldPage("<body></body>", "load();")).toThrow(
      "World page template is missing its script marker",
    );
  });

  test("rejects a colony template without a script marker", () => {
    expect(() => composeColonyPage("<body></body>", "load();")).toThrow(
      "Colony page template is missing its script marker",
    );
  });

  test("escapes hostile bead titles rendered by card", () => {
    const script = worldPage.match(/<script>([\s\S]*?)<\/script>/)?.[1];
    expect(script).toBeDefined();
    if (script === undefined) {
      throw new Error("world page script is missing");
    }
    const context = createContext({
      fetch: () => new Promise(() => undefined),
      setInterval: () => undefined,
    });
    new Script(script).runInContext(context);
    const renderCard = context.card as (fort: unknown) => string;
    const hostileTitle = '</li><img src=x onerror="alert(1)">';

    const markup = renderCard({
      name: "Alpha",
      present: true,
      git: { branch: "main", ahead: 0, behind: 0, dirty: false },
      beads: { open: 1 },
      inProgress: [{ id: "fortkit-hostile", title: hostileTitle }],
      announcements: [],
      watcherAlerts: [],
      gaps: [],
    });

    expect(markup).toContain(
      "&lt;/li&gt;&lt;img src=x onerror=&quot;alert(1)&quot;&gt;",
    );
    expect(markup).not.toContain(hostileTitle);
    expect(markup).not.toContain("<img");
  });

  test("renders escaped seat and bead detail panels from fixtures", () => {
    const script = colonyPage.match(/<script>([\s\S]*?)<\/script>/)?.[1];
    expect(script).toBeDefined();
    if (script === undefined) throw new Error("colony page script is missing");
    const context = createContext({
      fetch: () => new Promise(() => undefined),
      setInterval: () => undefined,
      location: { search: "" },
      document: { querySelector: () => null },
      URLSearchParams,
    });
    new Script(script).runInContext(context);
    const hostile = '<img src=x onerror="alert(1)">';
    const renderSeatPanel = context.seatPanel as (citizen: unknown) => string;
    const renderBeadPanel = context.beadPanel as (bead: unknown) => string;

    const seatMarkup = renderSeatPanel({
      name: hostile,
      pronouns: hostile,
      seat: hostile,
      personality: hostile,
      currentBead: hostile,
      lastHandoff: hostile,
    });
    const beadMarkup = renderBeadPanel({
      id: hostile,
      title: hostile,
      description: hostile,
      design: hostile,
      notes: hostile,
      acceptanceCriteria: hostile,
      status: hostile,
      priority: 1,
      issueType: hostile,
      assignee: hostile,
      owner: hostile,
      labels: [hostile],
      createdAt: hostile,
      createdBy: hostile,
      updatedAt: hostile,
      startedAt: hostile,
      closedAt: hostile,
      closeReason: hostile,
      dependencies: [
        {
          issueId: hostile,
          dependsOnId: hostile,
          type: hostile,
          createdAt: hostile,
          createdBy: hostile,
          metadata: hostile,
        },
      ],
    });

    for (const markup of [seatMarkup, beadMarkup]) {
      expect(markup).toContain(
        "&lt;img src=x onerror=&quot;alert(1)&quot;&gt;",
      );
      expect(markup).not.toContain(hostile);
      expect(markup).not.toContain("<img");
    }
    expect(beadMarkup).toContain("Provenance edges");
  });

  test("opens the bead drawn at each detail-row baseline, not a neighbour", () => {
    const script = colonyPage.match(/<script>([\s\S]*?)<\/script>/)?.[1];
    expect(script).toBeDefined();
    if (script === undefined) throw new Error("colony page script is missing");
    const canvas = {
      width: 1100,
      height: 620,
      onclick: undefined as
        | undefined
        | ((event: { clientX: number; clientY: number }) => void),
      getBoundingClientRect: () => ({
        left: 0,
        top: 0,
        width: 1100,
        height: 620,
      }),
      getContext: () => ({
        fillStyle: "",
        strokeStyle: "",
        font: "",
        fillRect: vi.fn(),
        strokeRect: vi.fn(),
        fillText: vi.fn(),
      }),
    };
    const detailPanel = { textContent: "", innerHTML: "" };
    const context = createContext({
      fetch: () => new Promise(() => undefined),
      setInterval: () => undefined,
      location: { search: "" },
      document: {
        querySelector: (selector: string) =>
          selector === "#colony"
            ? canvas
            : selector === "#detail-panel"
              ? detailPanel
              : { textContent: "" },
      },
      URLSearchParams,
    });
    new Script(script).runInContext(context);
    const beads = Array.from({ length: 5 }, (_, index) => ({
      id: `bead-${index}`,
      title: `Bead ${index}`,
    }));
    (context.render as (projection: unknown) => void)({
      workshops: [{ type: "implementation", beads }],
      benches: [],
      dungeon: beads,
      citizens: [],
      unassigned: beads,
      announcements: [],
      gaps: [],
    });
    if (canvas.onclick === undefined)
      throw new Error("click handler is missing");

    const buildings: Array<[number, number]> = [
      [30, 35],
      [765, 35],
      [30, 230],
    ];
    for (const [left, top] of buildings) {
      for (const [index, bead] of beads.entries()) {
        canvas.onclick({ clientX: left + 10, clientY: top + 46 + index * 13 });
        expect(detailPanel.innerHTML).toContain(`Bead: ${bead.id}`);
      }
    }

    canvas.onclick({ clientX: 241, clientY: 276 });
    expect(detailPanel.innerHTML).toBe("");
    canvas.onclick({ clientX: 40, clientY: 146 });
    expect(detailPanel.innerHTML).toBe("");
  });

  test("uses the handoff heading timestamp to break same-day filename ties", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-handoffs-"));
    try {
      await Promise.all([
        writeFile(
          join(root, "forge-2026-08-07.md"),
          "# Handoff: Forge 2026-08-07T13:59:13-08:00\n",
        ),
        writeFile(
          join(root, "forge-2026-08-07-bzx.4.md"),
          "# Handoff: Forge 2026-08-07T14:28:00-08:00\n",
        ),
      ]);

      const handoffs = await readLatestHandoffs(root);
      expect(handoffs?.get("forge")).toBe(
        "Handoff: Forge 2026-08-07T14:28:00-08:00",
      );
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("reads Mayor handoff headings without seconds or with an uncertain time", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-handoffs-"));
    try {
      await Promise.all([
        writeFile(
          join(root, "mayor-2026-08-04.md"),
          "# Handoff: Mayor 2026-08-04T11:35-08:00\n",
        ),
        writeFile(
          join(root, "mayor-2026-08-04-d.md"),
          "# Handoff: Mayor 2026-08-04T20:30-08:00\n",
        ),
        writeFile(
          join(root, "mayor-2026-08-06.md"),
          "# Handoff: Mayor 2026-08-06T10:00-08:00\n",
        ),
        writeFile(
          join(root, "mayor-2026-08-06-d.md"),
          "# Handoff: Mayor 2026-08-06T~~11:45-08:00\n",
        ),
      ]);

      const handoffs = await readLatestHandoffs(root);
      expect(handoffs?.get("mayor")).toBe(
        "Handoff: Mayor 2026-08-06T~~11:45-08:00",
      );

      await Promise.all([
        rm(join(root, "mayor-2026-08-06.md"), { force: true }),
        rm(join(root, "mayor-2026-08-06-d.md"), { force: true }),
      ]);
      const sameDayHandoffs = await readLatestHandoffs(root);
      expect(sameDayHandoffs?.get("mayor")).toBe(
        "Handoff: Mayor 2026-08-04T20:30-08:00",
      );
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("prefers a suffixed filename when same-day handoff timestamps are absent", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-handoffs-"));
    try {
      await Promise.all([
        writeFile(join(root, "mayor-2026-08-04.md"), "not a handoff\n"),
        writeFile(join(root, "mayor-2026-08-04-d.md"), "still not a handoff\n"),
      ]);

      const handoffs = await readLatestHandoffs(root);
      expect(handoffs?.get("mayor")).toBeNull();
    } finally {
      await rm(root, { recursive: true, force: true });
    }
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

  test("serves a selected colony page and rejects an unknown colony", async () => {
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
    const page = response();
    await handler(
      {
        url: "/colony-view?fort=Alpha",
        headers: { host: "localhost" },
      } as never,
      page as never,
    );
    expect(page.result()).toMatchObject({
      status: 200,
      body: expect.stringContaining('id="colony"'),
    });
    const missing = response();
    await handler(
      { url: "/colony?fort=Unknown", headers: { host: "localhost" } } as never,
      missing as never,
    );
    expect(missing.result()).toEqual({
      status: 404,
      body: '{"error":"Colony not found"}',
    });
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

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
    expect(worldPage).toContain("previousFortsMarkup");
  });

  test("has a checked canvas colony page with distinct actor styles", () => {
    expect(colonyPage).not.toContain("<!-- colony-page-script -->");
    expect(colonyPage).toContain("<title>Bartizan — colony</title>");
    expect(colonyPage).toContain('id="colony-title"');
    const tickerTag = colonyPage.match(/<[^>]*\bid="ticker"[^>]*>/)?.[0];
    const statusTag = colonyPage.match(/<[^>]*\bid="status"[^>]*>/)?.[0];
    expect(tickerTag).toBeDefined();
    expect(tickerTag).not.toMatch(/\baria-live=/);
    expect(statusTag).toBeDefined();
    expect(statusTag).toMatch(/\brole="status"/);
    expect(statusTag).not.toMatch(/\bclass="muted"/);
    expect(colonyPage).toContain(
      "#status:empty { margin: 0; padding: 0; border-width: 0; }",
    );
    expect(colonyPage).not.toContain("#status:empty { display: none; }");
    expect(colonyPage).toContain(
      "#detail-panel:empty { margin: 0; padding: 0; border-width: 0; }",
    );
    expect(colonyPage).not.toContain('id="gaps" class="muted"');
    expect(colonyPage).toContain("#gaps { color: #ffcf8b; font-weight: 600; }");
    const canvasTag = colonyPage.match(/<canvas\b[^>]*>/)?.[0];
    expect(canvasTag).toBeDefined();
    expect(canvasTag).toMatch(/\bid="colony"/);
    expect(colonyPage).toContain("fetch(`/colony?fort=");
    const script = colonyPage.match(/<script>([\s\S]*?)<\/script>/)?.[1];
    expect(script).toBeDefined();
    if (script === undefined) throw new Error("colony page script is missing");
    const context = createContext({
      fetch: () => new Promise(() => undefined),
      setInterval: () => undefined,
      location: { search: "?fort=Alpha" },
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

  test("places every roster citizen once, with live sessions overriding ambient life", () => {
    const script = colonyPage.match(/<script>([\s\S]*?)<\/script>/)?.[1];
    expect(script).toBeDefined();
    if (script === undefined) throw new Error("colony page script is missing");
    const context = createContext({
      fetch: () => new Promise(() => undefined),
      setInterval: () => undefined,
      location: { search: "?fort=Manyhalls" },
      document: { querySelector: () => null },
      URLSearchParams,
    });
    new Script(script).runInContext(context);
    const placements = (
      context.citizenPlacements as (
        projection: unknown,
        timestamp: number,
        seed: number,
      ) => Array<{
        citizen: { name: string };
        x: number;
        y: number;
        activity: string;
        idle: boolean;
      }>
    )(
      {
        citizens: [
          {
            name: "Emrith",
            pronouns: "she/her",
            seat: "mayor",
            currentBead: "fortkit-live",
            session: { beadId: "fortkit-live" },
          },
          {
            name: "Kethra",
            pronouns: "she/her",
            seat: "forge",
            currentBead: null,
            session: null,
          },
        ],
      },
      Date.parse("2026-08-07T12:30:00Z"),
      123,
    );
    expect(placements).toHaveLength(2);
    expect(new Set(placements.map(({ citizen }) => citizen.name)).size).toBe(2);
    expect(placements[0]).toMatchObject({
      activity: "working on fortkit-live",
      idle: false,
      x: 52,
      y: 130,
    });
    expect(placements[1]).toMatchObject({
      activity: "lunching",
      idle: true,
      x: 86,
      y: 470,
    });
  });

  test("names the colony tab and header after its selected fort", () => {
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

  test("does not rewrite identical apostrophe-bearing panels or status on polls", async () => {
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
        height: canvas.height,
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
    const context = createContext({
      fetch: () => new Promise(() => undefined),
      setInterval: () => undefined,
      location: { search: "?fort=Alpha" },
      URLSearchParams,
    });
    const panelSetter = vi.fn();
    const statusSetter = vi.fn();
    const panel = {
      set innerHTML(value: string) {
        panelSetter(value);
      },
    };
    const status = {
      set textContent(value: string) {
        statusSetter(value);
      },
    };
    context.document = {
      querySelector: (selector: string) =>
        selector === "#colony"
          ? canvas
          : selector === "#detail-panel"
            ? panel
            : selector === "#status"
              ? status
              : { textContent: "" },
    };
    new Script(script).runInContext(context);
    const projection = {
      beads: [{ id: "apostrophe", title: "Kethra's panel" }],
      intake: [{ id: "apostrophe", title: "Kethra's panel" }],
      jobBoard: [{ id: "apostrophe", title: "Kethra's panel" }],
      depot: [],
      workshops: [],
      benches: [],
      dungeon: [],
      citizens: [],
      announcements: [],
      gaps: [],
      unassigned: [{ id: "apostrophe", title: "Kethra's panel" }],
    };
    (context.render as (value: unknown) => void)(projection);
    if (canvas.onclick === undefined)
      throw new Error("click handler is missing");
    canvas.onclick({ clientX: 775, clientY: 81 });
    expect(panelSetter).toHaveBeenLastCalledWith(
      expect.stringContaining("Kethra&#39;s panel"),
    );
    panelSetter.mockClear();
    (context.render as (value: unknown) => void)(projection);

    const load = context.load as () => Promise<void>;
    context.fetch = () => Promise.reject(new Error("network outage"));
    await load();
    await load();

    expect(panelSetter).not.toHaveBeenCalled();
    expect(statusSetter).toHaveBeenCalledTimes(1);
    expect(statusSetter).toHaveBeenCalledWith(
      "Colony data unavailable: Error: network outage",
    );
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
    const details = Array.from(
      { length: 7 },
      (_, index) => `detail-${index}-${"x".repeat(30)}`,
    );
    expect(
      (
        context.visibleDetails as (
          values: string[],
        ) => Array<{ text: string; index: number | undefined }>
      )(details),
    ).toEqual([
      ...details.slice(0, 4).map((text, index) => ({ text, index })),
      { text: "… +3 more", index: undefined },
    ]);
    expect(
      (context.truncateDetail as (value: string) => string)(details[0] ?? ""),
    ).toBe(`detail-0-${"x".repeat(17)}…`);
    const canvasContext = canvas.getContext();
    if (canvasContext === null) throw new Error("canvas context is missing");
    (context.building as (context: unknown, building: unknown) => void)(
      canvasContext,
      {
        x: 0,
        y: 0,
        name: "DETAILS",
        color: "#000",
        details,
        targetAt: () => undefined,
      },
    );
    expect(fillText).toHaveBeenCalledWith(
      `detail-0-${"x".repeat(17)}…`,
      10,
      46,
    );
    expect(fillText).toHaveBeenCalledWith("… +3 more", 10, 98);

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
        session: null,
        lastHandoff: null,
      })),
      unassigned: [],
      announcements: [],
      gaps: [],
    });
    expect(canvas.height).toBe(545 + Math.ceil(7 / 4) * 145 + 20);
    expect(fillText).toHaveBeenCalledWith("Citizen 7'S HOME", 530, 714);
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
          session: null,
          lastHandoff: null,
        },
      ],
      unassigned: [{ id: "intake", title: null }],
      announcements: ["The gate is watched"],
      gaps: ["event stream ABSENT"],
    });
    expect(fillText.mock.calls.map(([value]) => value)).toEqual(
      expect.arrayContaining([
        "MAYOR'S OFFICE",
        "THE FORGE",
        "WARDEN'S TOWER",
        "THE GATE",
        "THE JOB BOARD",
        "TRADE DEPOT",
        "THE ARCHIVE",
        "THE DUNGEON",
        "THE TAVERN",
        "Kethra'S HOME",
        "Kethra",
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

  test("clears a failed world poll on an identical successful response", async () => {
    const script = worldPage.match(/<script>([\s\S]*?)<\/script>/)?.[1];
    expect(script).toBeDefined();
    if (script === undefined) throw new Error("world page script is missing");
    let fortsContent = "";
    const forts = {
      get innerHTML() {
        return fortsContent;
      },
      set innerHTML(value: string) {
        fortsContent = value;
      },
      get textContent() {
        return fortsContent;
      },
      set textContent(value: string) {
        fortsContent = value;
      },
    };
    const updated = { textContent: "" };
    const response = [
      { json: async () => [] },
      new Error("network outage"),
      { json: async () => [] },
    ];
    const context = createContext({
      fetch: vi.fn(() => {
        const next = response.shift();
        return next instanceof Error
          ? Promise.reject(next)
          : Promise.resolve(next);
      }),
      setInterval: () => undefined,
      document: {
        querySelector: (selector: string) =>
          selector === "#forts"
            ? forts
            : selector === "#updated"
              ? updated
              : null,
      },
    });
    new Script(script).runInContext(context);
    await vi.waitFor(() =>
      expect(forts.innerHTML).toBe("<p>No registered forts found.</p>"),
    );

    const load = context.load as () => Promise<void>;
    await load();
    expect(forts.textContent).toBe(
      "World data unavailable: Error: network outage",
    );
    await load();

    expect(forts.innerHTML).toBe("<p>No registered forts found.</p>");
    expect(forts.textContent).not.toContain("World data unavailable");
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

  test("opens distinct building, archive, and wrapped-citizen entities at their drawn rows", () => {
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
        height: canvas.height,
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
    const gateBeads = Array.from({ length: 7 }, (_, index) => ({
      id: `gate-${index}`,
      title: `Gate ${index}`,
    }));
    const dungeonBeads = Array.from({ length: 4 }, (_, index) => ({
      id: `dungeon-${index}`,
      title: `Dungeon ${index}`,
    }));
    const workshopBeads = Array.from({ length: 4 }, (_, index) => ({
      id: `workshop-${index}`,
      title: `Workshop ${index}`,
    }));
    const citizens = Array.from({ length: 7 }, (_, index) => ({
      name: `Citizen ${index}`,
      pronouns: "they/them",
      seat: `Seat ${index}`,
      personality: null,
      currentBead: null,
      session: {},
      lastHandoff: null,
    }));
    (context.render as (projection: unknown) => void)({
      beads: [...gateBeads, ...dungeonBeads, ...workshopBeads],
      intake: gateBeads,
      jobBoard: gateBeads,
      depot: [],
      workshops: [{ type: "implementation", beads: workshopBeads }],
      benches: [],
      dungeon: dungeonBeads,
      citizens,
      unassigned: gateBeads,
      announcements: [],
      gaps: [],
    });
    if (canvas.onclick === undefined)
      throw new Error("click handler is missing");

    const buildings: Array<[number, number, string]> = [
      [765, 35, "gate"],
      [520, 205, "dungeon"],
      [30, 205, "gate"],
    ];
    for (const [left, top, prefix] of buildings) {
      for (let index = 0; index < 4; index += 1) {
        canvas.onclick({
          clientX: left + 10,
          clientY: top + 46 + index * 13,
        });
        expect(detailPanel.innerHTML).toContain(`Bead: ${prefix}-${index}`);
      }
    }

    canvas.onclick({ clientX: 775, clientY: 81 + 4 * 13 });
    expect(detailPanel.innerHTML).toContain("THE GATE");
    canvas.onclick({ clientX: 576, clientY: 770 });
    expect(detailPanel.innerHTML).toContain("Seat: Seat 6");
    canvas.onclick({ clientX: 241, clientY: 276 });
    expect(detailPanel.innerHTML).toBe("");
  });

  test("refreshes a selected panel from current colony data", () => {
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
        height: canvas.height,
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
      URLSearchParams,
      document: {
        querySelector: (selector: string) =>
          selector === "#colony"
            ? canvas
            : selector === "#detail-panel"
              ? detailPanel
              : { textContent: "" },
      },
    });
    new Script(script).runInContext(context);
    const projection = {
      beads: [{ id: "live", title: "Live bead" }],
      intake: [{ id: "live", title: "Live bead" }],
      jobBoard: [{ id: "live", title: "Live bead" }],
      depot: [],
      workshops: [],
      benches: [],
      dungeon: [],
      citizens: [],
      announcements: [],
      gaps: [],
      unassigned: [{ id: "live", title: "Live bead" }],
    };
    (context.render as (value: unknown) => void)(projection);
    if (canvas.onclick === undefined)
      throw new Error("click handler is missing");
    canvas.onclick({ clientX: 775, clientY: 81 });
    expect(detailPanel.innerHTML).toContain("Bead: live");
    (context.render as (value: unknown) => void)({
      ...projection,
      beads: [],
      intake: [],
      jobBoard: [],
      unassigned: [],
    });
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

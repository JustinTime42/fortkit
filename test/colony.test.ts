import { describe, expect, test } from "vitest";

import { projectColony } from "../src/colony.js";
import type { Bead, EventDetail } from "../src/types.js";

function bead(overrides: Partial<Bead>): Bead {
  return {
    id: "fortkit-example",
    title: "Example work",
    description: null,
    design: null,
    notes: null,
    acceptanceCriteria: null,
    status: "open",
    priority: null,
    issueType: "task",
    assignee: null,
    owner: null,
    labels: [],
    dependencies: [],
    createdAt: null,
    createdBy: null,
    updatedAt: null,
    startedAt: null,
    closedAt: null,
    closeReason: null,
    ...overrides,
  };
}

function event(overrides: Partial<EventDetail> = {}): EventDetail {
  return {
    ts: "2026-08-07T20:00:00Z",
    actor: "kethra",
    seat: "forge",
    category: "session.start",
    target: "fortkit-bzx.2",
    detail: null,
    payload: { model: "gpt-5.6-terra" },
    ...overrides,
  };
}

describe("colony projection", () => {
  test("projects workshops, benches, dungeon, and citizens from source data", () => {
    const result = projectColony({
      beads: [
        bead({ id: "implementation", labels: ["implementation"] }),
        bead({
          id: "finished-implementation",
          labels: ["implementation"],
          status: "closed",
        }),
        bead({ id: "spec", labels: ["spec"] }),
        bead({ id: "test", labels: ["test"] }),
        bead({ id: "infra", labels: ["infra"] }),
        bead({ id: "bug", issueType: "bug" }),
        bead({ id: "fixed-bug", issueType: "bug", status: "closed" }),
        bead({ id: "no-job", labels: [] }),
      ],
      worktrees: ["/fortkit-worktrees/other", "/fortkit-worktrees/bzx.2"],
      events: [event()],
      citizens: [
        { name: "Kethra Anvilmark", pronouns: "she/her", seat: "forge" },
      ],
    });

    expect(result.workshops).toEqual([
      expect.objectContaining({
        type: "implementation",
        beads: [expect.objectContaining({ id: "implementation" })],
      }),
      expect.objectContaining({
        type: "spec",
        beads: [expect.objectContaining({ id: "spec" })],
      }),
      expect.objectContaining({
        type: "test",
        beads: [expect.objectContaining({ id: "test" })],
      }),
      expect.objectContaining({
        type: "infra",
        beads: [expect.objectContaining({ id: "infra" })],
      }),
    ]);
    expect(result.benches).toEqual([
      {
        worktree: "/fortkit-worktrees/bzx.2",
        session: expect.objectContaining({
          beadId: "fortkit-bzx.2",
          model: "gpt-5.6-terra",
        }),
      },
      { worktree: "/fortkit-worktrees/other", session: null },
    ]);
    expect(result.dungeon).toEqual([expect.objectContaining({ id: "bug" })]);
    expect(result.citizens).toEqual([
      { name: "Kethra Anvilmark", pronouns: "she/her", seat: "forge" },
    ]);
    expect(result.unassigned.map(({ id }) => id)).toEqual(["bug", "no-job"]);
  });

  test("keeps working bugs in rehabilitation and removes closed beads from the live colony", () => {
    const result = projectColony({
      beads: [
        bead({ id: "open-bug", issueType: "bug" }),
        bead({ id: "repairing-bug", issueType: "bug", status: "in_progress" }),
        bead({ id: "blocked-bug", issueType: "bug", status: "blocked" }),
        bead({ id: "released-bug", issueType: "bug", status: "closed" }),
        bead({
          id: "active-job",
          labels: ["implementation"],
          status: "in_progress",
        }),
        bead({
          id: "historic-job",
          labels: ["implementation"],
          status: "closed",
        }),
        bead({ id: "active-untyped", status: "blocked" }),
        bead({ id: "historic-untyped", status: "closed" }),
      ],
      worktrees: [],
      events: [],
      citizens: [],
    });

    expect(result.dungeon.map(({ id }) => id)).toEqual([
      "open-bug",
      "repairing-bug",
      "blocked-bug",
    ]);
    expect(result.workshops[0]?.beads.map(({ id }) => id)).toEqual([
      "active-job",
    ]);
    expect(result.unassigned.map(({ id }) => id)).toEqual([
      "open-bug",
      "repairing-bug",
      "blocked-bug",
      "active-untyped",
    ]);
  });

  test("keeps state intact when optional event history is missing", () => {
    const result = projectColony({
      beads: [bead({ id: "implementation", labels: ["implementation"] })],
      worktrees: ["/fortkit-worktrees/bzx.2"],
      events: null,
      citizens: [],
    });

    expect(result.workshops[0]?.beads).toEqual([
      expect.objectContaining({ id: "implementation" }),
    ]);
    expect(result.benches).toEqual([
      { worktree: "/fortkit-worktrees/bzx.2", session: null },
    ]);
    expect(result.gaps).toEqual(["event stream ABSENT"]);
  });

  test("represents absent sources as gaps without throwing", () => {
    expect(
      projectColony({
        beads: null,
        worktrees: null,
        events: null,
        citizens: null,
      }),
    ).toEqual({
      workshops: [
        { type: "implementation", beads: [] },
        { type: "spec", beads: [] },
        { type: "test", beads: [] },
        { type: "infra", beads: [] },
      ],
      benches: [],
      dungeon: [],
      citizens: [],
      unassigned: [],
      announcements: [],
      gaps: [
        "Beads export ABSENT",
        "git worktree list ABSENT",
        "event stream ABSENT",
        "seats roster ABSENT",
      ],
    });
  });

  test("keeps a Forge bench separate from overlapping Warden sessions", () => {
    const sources = {
      beads: [],
      worktrees: ["/fortkit-worktrees/bzx.2"],
      events: [
        event(),
        event({
          ts: "2026-08-07T20:05:00Z",
          actor: "ilva",
          seat: "warden",
        }),
        event({
          ts: "2026-08-07T20:10:00Z",
          actor: "ilva",
          seat: "warden",
          category: "session.end",
        }),
      ],
      citizens: [],
    };

    const whileForgeWorks = projectColony(sources);
    expect(whileForgeWorks.benches[0]?.session).toEqual(
      expect.objectContaining({ actor: "kethra", seat: "forge" }),
    );

    const afterForgeEnds = projectColony({
      ...sources,
      events: [
        ...sources.events,
        event({ ts: "2026-08-07T20:15:00Z", category: "session.end" }),
        event({
          ts: "2026-08-07T20:16:00Z",
          actor: "ilva",
          seat: "warden",
        }),
      ],
    });

    expect(afterForgeEnds.benches[0]?.session).toBeNull();
  });

  test("uses append order for tied or unparseable session timestamps", () => {
    const sources = {
      beads: [],
      worktrees: ["/fortkit-worktrees/bzx.2"],
      citizens: [],
    };

    expect(
      projectColony({
        ...sources,
        events: [event(), event({ category: "session.end" })],
      }).benches[0]?.session,
    ).toBeNull();

    expect(
      projectColony({
        ...sources,
        events: [
          event({ ts: "not-a-timestamp" }),
          event({ ts: "not-a-timestamp", category: "session.end" }),
        ],
      }).benches[0]?.session,
    ).toBeNull();
  });

  test("sorts worktree paths by code point rather than locale", () => {
    const result = projectColony({
      beads: [],
      worktrees: ["/fortkit-worktrees/a", "/fortkit-worktrees/B"],
      events: [],
      citizens: [],
    });

    expect(result.benches.map(({ worktree }) => worktree)).toEqual([
      "/fortkit-worktrees/B",
      "/fortkit-worktrees/a",
    ]);
  });
});

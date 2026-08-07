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
    expect(result.unassigned.map(({ id }) => id)).toEqual([
      "bug",
      "fixed-bug",
      "no-job",
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
      gaps: [
        "Beads export ABSENT",
        "git worktree list ABSENT",
        "event stream ABSENT",
        "seats roster ABSENT",
      ],
    });
  });

  test("ends a bench session only when a newer end event names the same bead", () => {
    const result = projectColony({
      beads: [],
      worktrees: ["/fortkit-worktrees/bzx.2"],
      events: [
        event(),
        event({ ts: "2026-08-07T21:00:00Z", category: "session.end" }),
      ],
      citizens: [],
    });

    expect(result.benches[0]?.session).toBeNull();
  });
});

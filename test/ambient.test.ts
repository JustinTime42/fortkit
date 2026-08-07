import { describe, expect, test } from "vitest";

import { activity, formatAmbientDay, fortSeedFor } from "../src/ambient.ts";

const seed = fortSeedFor("Manyhalls");

describe("ambient life", () => {
  test("is pure and follows a contiguous sleep window across midnight", () => {
    expect(activity("kethra", "2026-08-07T22:00:00Z", seed)).toEqual(
      activity("kethra", "2026-08-07T22:00:00Z", seed),
    );
    expect(activity("kethra", "2026-08-07T23:30:00Z", seed)).toEqual({
      activity: "sleeping",
      place: "home:kethra",
    });
    expect(activity("kethra", "2026-08-08T04:00:00Z", seed)).toEqual({
      activity: "sleeping",
      place: "home:kethra",
    });
  });

  test("uses UTC clockwork through a DST transition", () => {
    const before = activity("ilva", "2026-03-08T12:30:00-08:00", seed);
    const after = activity("ilva", "2026-03-08T12:30:00-07:00", seed);
    expect(before).toEqual(activity("ilva", "2026-03-08T20:30:00Z", seed));
    expect(after).toEqual(activity("ilva", "2026-03-08T19:30:00Z", seed));
  });

  test("puts every awake citizen together at Tavern meals and socializing", () => {
    for (const timestamp of [
      "2026-08-07T12:30:00Z",
      "2026-08-07T18:30:00Z",
      "2026-08-07T20:30:00Z",
    ]) {
      const states = ["emrith", "kethra", "ilva"].map((citizen) =>
        activity(citizen, timestamp, seed),
      );
      expect(states.every((state) => state.place === "tavern")).toBe(true);
    }
  });

  test("renders a deterministic day schedule", () => {
    const summary = formatAmbientDay("kethra", "2026-08-07T10:00:00Z", seed);
    expect(summary).toContain("Ambient schedule for kethra — 2026-08-07 UTC");
    expect(summary).toContain("lunching at tavern");
    expect(summary).toContain("socializing at tavern");
  });
});

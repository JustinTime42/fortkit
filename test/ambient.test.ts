import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

import {
  activity,
  formatAmbientDay,
  formatAmbientSince,
  fortSeedFor,
} from "../src/ambient.ts";

const seed = fortSeedFor("Manyhalls");
const execFileAsync = promisify(execFile);

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

  test("uses UTC clockwork under a non-UTC host timezone", async () => {
    const ambientPath = fileURLToPath(
      new URL("../src/ambient.ts", import.meta.url),
    );
    const { stdout } = await execFileAsync(
      process.execPath,
      [
        "--input-type=module",
        "--eval",
        `import { activity } from ${JSON.stringify(ambientPath)}; const result = activity("ilva", "2026-03-08T12:30:00Z", ${seed}); if (result.activity !== "lunching" || result.place !== "tavern") process.exit(1);`,
      ],
      { env: { ...process.env, TZ: "Pacific/Kiritimati" } },
    );
    expect(stdout).toBe("");
  });

  test("jitters Tavern arrivals and departures around a shared core", () => {
    const citizens = ["emrith", "kethra", "ilva"];
    for (const timestamp of [
      "2026-08-07T12:30:00Z", // lunch core
      "2026-08-07T18:30:00Z", // dinner core
      "2026-08-07T20:00:00Z", // social core
    ]) {
      const states = citizens.map((citizen) =>
        activity(citizen, timestamp, seed),
      );
      expect(states.every((state) => state.place === "tavern")).toBe(true);
    }
    const arrivals = citizens.map(
      (citizen) => activity(citizen, "2026-08-07T11:45:00Z", seed).activity,
    );
    expect(new Set(arrivals).size).toBeGreaterThan(1);
  });

  test("gives Kethra a deterministic fishing habit with retained variety", () => {
    const states = Array.from({ length: 24 }, (_, offset) =>
      [9, 15].map(
        (hour) =>
          activity(
            "kethra",
            `2026-08-${String(offset + 7).padStart(2, "0")}T${String(hour).padStart(2, "0")}:30:00Z`,
            seed,
          ).activity,
      ),
    ).flat();
    expect(
      states.filter((state) => state === "fishing").length,
    ).toBeGreaterThan(states.filter((state) => state === "reading").length);
    expect(new Set(states).size).toBeGreaterThan(1);
  });

  test("rejects malformed timestamps instead of inventing a 1970 schedule", () => {
    expect(() => activity("kethra", "not-a-time", seed)).toThrow(RangeError);
    expect(() => formatAmbientDay("kethra", Number.NaN, seed)).toThrow(
      RangeError,
    );
  });

  test("renders a deterministic day schedule", () => {
    const summary = formatAmbientDay("kethra", "2026-08-07T10:00:00Z", seed);
    expect(summary).toContain("Ambient schedule for kethra — 2026-08-07 UTC");
    expect(summary).toContain("lunching at tavern");
    expect(summary).toContain("socializing at tavern");
  });

  test("renders --since as its true interval, unlike the containing-day view", () => {
    const summary = formatAmbientSince(
      "kethra",
      "2026-08-07T12:20:00Z",
      seed,
      "2026-08-07T12:50:00Z",
    );
    expect(summary).toContain(
      "since 2026-08-07T12:20:00.000Z through 2026-08-07T12:50:00.000Z UTC",
    );
    expect(summary).not.toContain("00:00–");
    expect(() =>
      formatAmbientSince(
        "kethra",
        "2026-08-07T12:50:00Z",
        seed,
        "2026-08-07T12:20:00Z",
      ),
    ).toThrow(RangeError);
  });
});

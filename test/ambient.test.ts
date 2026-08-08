import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

import {
  activity,
  ambientIdFor,
  formatAmbientDay,
  formatAmbientSince,
  fortSeedFor,
} from "../src/ambient.ts";

const seed = fortSeedFor("Manyhalls");
describe("ambient life", () => {
  test("gives actor ids and display names one canonical citizen schedule", () => {
    expect(ambientIdFor("Kethra Anvilmark")).toBe(ambientIdFor("kethra"));
    expect(
      activity(ambientIdFor("Kethra Anvilmark"), "2026-08-07T09:30:00Z", seed),
    ).toEqual(activity(ambientIdFor("kethra"), "2026-08-07T09:30:00Z", seed));
  });

  test("trims a roster name before deriving its ambient identity", () => {
    expect(ambientIdFor(" kethra")).toBe("kethra");
  });

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
    const child = spawn(
      process.execPath,
      [
        "--input-type=module",
        "--eval",
        `import { activity } from ${JSON.stringify(ambientPath)}; const result = activity("ilva", "2026-03-08T12:30:00Z", ${seed}); console.log(JSON.stringify(result)); process.send?.(JSON.stringify(result));`,
      ],
      {
        env: { ...process.env, TZ: "Pacific/Kiritimati" },
        stdio: ["ignore", "pipe", "pipe", "ipc"],
      },
    );
    const [message] = await once(child, "message");
    const [code] = await once(child, "close");
    expect(code).toBe(0);
    expect(JSON.parse(String(message))).toEqual({
      activity: "lunching",
      place: "tavern",
    });
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

  test("samples independent hash bits for all Tavern jitter combinations", () => {
    const combinations = new Set(
      Array.from({ length: 256 }, (_, index) => `citizen-${index}`).map(
        (citizen) =>
          [
            activity(citizen, "2026-08-07T11:45:00Z", seed).place === "tavern",
            activity(citizen, "2026-08-07T13:00:00Z", seed).place === "tavern",
          ].join(","),
      ),
    );
    expect(combinations).toEqual(
      new Set(["false,false", "false,true", "true,false", "true,true"]),
    );
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

  test("maps idle pursuits to their dedicated layout destinations", () => {
    const states = Array.from({ length: 256 }, (_, index) =>
      activity(`citizen-${index}`, "2026-08-07T09:30:00Z", seed),
    );
    expect(states).toContainEqual({ activity: "fishing", place: "river" });
    expect(states).toContainEqual({
      activity: "tinkering",
      place: "tinker-bench",
    });
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

  test("caps long --since windows and dates multi-day schedule lines", () => {
    const summary = formatAmbientSince(
      "kethra",
      "2026-08-07T23:45:00Z",
      seed,
      "2026-08-08T00:15:00Z",
    );
    expect(summary).toContain("2026-08-07 23:45–2026-08-08 00:15");
    expect(() =>
      formatAmbientSince(
        "kethra",
        "0001-01-01T00:00:00Z",
        seed,
        "2026-08-07T00:00:00Z",
      ),
    ).toThrow("Ambient interval exceeds 31 days");
  });
});

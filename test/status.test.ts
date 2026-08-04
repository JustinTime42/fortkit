import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

import { readBeads } from "../src/readers/beads.js";
import { readCivilizationStatus, readFortStatus } from "../src/status.js";

const fixtureRoot = fileURLToPath(
  new URL("./fixtures/fort-alpha", import.meta.url),
);
const registryPath = fileURLToPath(
  new URL("./fixtures/civilization.json", import.meta.url),
);

describe("fort status", () => {
  test("reads a fixture fort without depending on the live civilization", async () => {
    const [fort] = await readCivilizationStatus(registryPath);
    expect(fort).toMatchObject({
      name: "Alpha",
      path: fixtureRoot,
      present: true,
      beads: { open: 1, inProgress: 1, blocked: 1, closed: 1, malformed: 1 },
      lastEvent: {
        ts: "2026-08-04T07:24:00.000Z",
        actor: "kethra",
        utcDay: "2026-08-04",
      },
      lastHandoff: {
        seat: "forge",
        date: "2026-08-04",
        title: "Handoff: forge 2026-08-04",
      },
    });
  });

  test("uses parsed UTC timestamps instead of event shard filenames", async () => {
    const [fort] = await readCivilizationStatus(registryPath);
    expect(fort?.lastEvent?.utcDay).toBe("2026-08-04");
    expect(fort?.lastEvent?.ts).toBe("2026-08-04T07:24:00.000Z");
  });

  test("counts malformed bead lines without throwing", async () => {
    await expect(
      readBeads(join(fixtureRoot, ".beads", "issues.jsonl")),
    ).resolves.toMatchObject({ malformed: 1 });
  });

  test("reports a registry fort whose directory is missing as absent", async () => {
    await expect(
      readFortStatus("Missing", join(fixtureRoot, "does-not-exist")),
    ).resolves.toMatchObject({
      name: "Missing",
      present: false,
      beads: null,
      lastEvent: null,
      lastHandoff: null,
    });
  });
});

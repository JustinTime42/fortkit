import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

import { formatDigest, readCivilizationDigest } from "../src/digest.js";

const registryPath = fileURLToPath(
  new URL("./fixtures/digest-civilization.json", import.meta.url),
);

describe("civilization digest", () => {
  test("uses an inclusive since and exclusive until window with a stable JSON shape", async () => {
    const digest = await readCivilizationDigest(
      registryPath,
      "2026-08-04T08:25:00Z",
      "2026-08-04T09:00:00Z",
    );

    expect(digest).toMatchObject({
      since: "2026-08-04T08:25:00.000Z",
      until: "2026-08-04T09:00:00.000Z",
      forts: [
        {
          name: "Alpha",
          present: true,
          events: [
            expect.objectContaining({
              ts: "2026-08-04T08:26:00.000Z",
              category: "watcher.alert",
            }),
            expect.objectContaining({
              ts: "2026-08-04T08:25:00.000Z",
              category: "bead.claimed",
            }),
          ],
          handoffSections: [
            expect.objectContaining({ heading: "State of work" }),
            expect.objectContaining({ heading: "Next actions" }),
          ],
          telemetry: { files: 1, records: 1, malformed: 1 },
        },
        {
          name: "Absent",
          present: false,
          events: null,
          closedBeads: null,
          telemetry: null,
        },
        {
          name: "[malformed registry entry 3]",
          path: null,
          present: false,
          events: null,
        },
      ],
    });
    expect(digest.forts[0]?.events).toHaveLength(2);
    expect(JSON.stringify(digest)).not.toContain(
      "this prompt must never appear in a digest",
    );
    expect(formatDigest(digest)).toContain("ABSENT");
  });

  test("rejects telemetry records outside the time window without exposing bodies", async () => {
    const digest = await readCivilizationDigest(
      registryPath,
      "2026-08-04T09:00:00Z",
      "2026-08-04T10:00:00Z",
    );
    expect(digest.forts[0]?.telemetry).toMatchObject({ records: 1 });
    expect(JSON.stringify(digest)).not.toContain("outside the selected window");
  });
});

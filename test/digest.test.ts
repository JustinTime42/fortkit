import { execFile } from "node:child_process";
import { mkdir, mkdtemp, rm, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

import { formatDigest, readCivilizationDigest } from "../src/digest.js";
import { readClosedBeads } from "../src/readers/beads.js";

const registryPath = fileURLToPath(
  new URL("./fixtures/digest-civilization.json", import.meta.url),
);
const execFileAsync = promisify(execFile);

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

  test("reads closed beads from each fort's passive export and discloses staleness", async () => {
    const directory = await mkdtemp(join(tmpdir(), "fortkit-digest-"));
    try {
      const fortPaths = await Promise.all(
        ["alpha", "beta", "gamma"].map(async (name) => {
          const fort = join(directory, name);
          const beads = join(fort, ".beads");
          await mkdir(beads, { recursive: true });
          await writeFile(
            join(beads, "issues.jsonl"),
            `${JSON.stringify({
              id: `${name}-closed`,
              title: `${name} fixture`,
              status: "closed",
              closed_at: "2026-08-04T12:00:00Z",
            })}\n`,
          );
          return fort;
        }),
      );
      const source = await readClosedBeads(
        fortPaths[0] as string,
        Date.parse("2026-08-04T00:00:00Z"),
        Date.parse("2026-08-05T00:00:00Z"),
      );
      expect(source).toMatchObject({
        status: "ok",
        beads: [{ id: "alpha-closed" }],
        exportStale: false,
      });
      await utimes(
        join(fortPaths[0] as string, ".beads", "issues.jsonl"),
        0,
        0,
      );
      await expect(
        readClosedBeads(
          fortPaths[0] as string,
          Date.parse("2026-08-04T00:00:00Z"),
          Date.parse("2026-08-05T00:00:00Z"),
        ),
      ).resolves.toMatchObject({ status: "ok", exportStale: true });

      const registry = join(directory, "civilization.json");
      await writeFile(
        registry,
        JSON.stringify({
          forts: fortPaths.map((path, index) => ({
            fort_name: ["Alpha", "Beta", "Gamma"][index],
            repo: path,
          })),
        }),
      );
      const digest = await readCivilizationDigest(
        registry,
        "2026-08-04T00:00:00Z",
        "2026-08-05T00:00:00Z",
      );
      expect(
        digest.forts.map((fort) =>
          fort.closedBeads?.status === "ok"
            ? fort.closedBeads.beads.length
            : -1,
        ),
      ).toEqual([1, 1, 1]);
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  test("reports a broken export as an error, preserves an empty export, and discloses caps", async () => {
    const directory = await mkdtemp(join(tmpdir(), "fortkit-digest-gaps-"));
    try {
      const empty = join(directory, "empty");
      const broken = join(directory, "broken");
      const crowded = join(directory, "crowded");
      await Promise.all(
        [empty, broken, crowded].map((fort) =>
          mkdir(join(fort, ".beads"), { recursive: true }),
        ),
      );
      await writeFile(join(empty, ".beads", "issues.jsonl"), "");
      await writeFile(join(broken, ".beads", "issues.jsonl"), "not json\n");
      await writeFile(join(crowded, ".beads", "issues.jsonl"), "");
      await mkdir(join(crowded, "fort", "events"), { recursive: true });
      await mkdir(join(crowded, "fort", "handoffs"), { recursive: true });
      await writeFile(
        join(crowded, "fort", "events", "events-2026-08-04.jsonl"),
        Array.from({ length: 51 }, (_, index) =>
          JSON.stringify({
            ts: `2026-08-04T00:${String(index).padStart(2, "0")}:00Z`,
            actor: "kethra",
          }),
        ).join("\n"),
      );
      await writeFile(
        join(crowded, "fort", "handoffs", "forge-2026-08-04.md"),
        Array.from({ length: 51 }, (_, index) => `## Section ${index}`).join(
          "\n\n",
        ),
      );
      const registry = join(directory, "civilization.json");
      await writeFile(
        registry,
        JSON.stringify({
          forts: [
            { fort_name: "Empty", repo: empty },
            { fort_name: "Broken", repo: broken },
            { fort_name: "Crowded", repo: crowded },
          ],
        }),
      );
      const digest = await readCivilizationDigest(
        registry,
        "2026-08-04T00:00:00Z",
        "2026-08-05T00:00:00Z",
      );
      expect(digest.forts[0]?.closedBeads).toMatchObject({
        status: "ok",
        beads: [],
      });
      expect(digest.forts[1]?.closedBeads).toMatchObject({ status: "error" });
      expect(digest.forts[2]).toMatchObject({
        eventsTruncated: 1,
        handoffSectionsTruncated: 1,
      });
      expect(formatDigest(digest)).toContain("closed beads: ERROR");
      expect(formatDigest(digest)).toContain("truncated 1");
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  test("correlates constitution diffs against the complete clean event window", async () => {
    const directory = await mkdtemp(
      join(tmpdir(), "fortkit-digest-constitution-"),
    );
    const addFort = async (
      name: string,
      subject: string,
      events: string[] | null,
    ) => {
      const fort = join(directory, name);
      await mkdir(join(fort, "fort"), { recursive: true });
      await writeFile(join(fort, "fort", "charter.md"), `${subject}\n`);
      await execFileAsync("git", ["init", "--quiet", fort]);
      for (const [key, value] of [
        ["user.email", "test@example.test"],
        ["user.name", "Test"],
      ] as const) {
        await execFileAsync("git", ["-C", fort, "config", key, value]);
      }
      await execFileAsync("git", ["-C", fort, "add", "fort/charter.md"]);
      await execFileAsync(
        "git",
        ["-C", fort, "commit", "--quiet", "-m", subject],
        {
          env: {
            ...process.env,
            GIT_AUTHOR_DATE: "2026-08-04T12:00:00Z",
            GIT_COMMITTER_DATE: "2026-08-04T12:00:00Z",
          },
        },
      );
      if (events !== null) {
        await mkdir(join(fort, "fort", "events"), { recursive: true });
        await writeFile(
          join(fort, "fort", "events", "events-2026-08-04.jsonl"),
          events.join("\n"),
        );
      }
      return fort;
    };
    try {
      const multiEvents = [
        JSON.stringify({
          ts: "2026-08-04T00:00:01Z",
          actor: "kethra",
          category: "work.ended",
          target: "multi-amendment",
        }),
        JSON.stringify({
          ts: "2026-08-04T00:00:00Z",
          actor: "kethra",
          category: "charter.amended",
          target: "multi-amendment",
        }),
        ...Array.from({ length: 49 }, (_, index) =>
          JSON.stringify({
            ts: `2026-08-04T01:${String(index).padStart(2, "0")}:00Z`,
            actor: "kethra",
            category: "work.progress",
          }),
        ),
      ];
      const forts = await Promise.all([
        addFort(
          "multi",
          "amend constitution (multi-first, multi-second, multi-amendment)",
          multiEvents,
        ),
        addFort("unannounced", "amend (unannounced-bead)", []),
        addFort("wrong-category", "amend (wrong-category-bead)", [
          JSON.stringify({
            ts: "2026-08-04T00:00:00Z",
            actor: "kethra",
            category: "work.ended",
            target: "wrong-category-bead",
          }),
        ]),
        addFort("no-ref", "amend without a bead", []),
        addFort("missing-events", "amend (missing-events-bead)", null),
        addFort("malformed-events", "amend (malformed-events-bead)", [
          "not json",
          JSON.stringify({
            ts: "2026-08-04T00:00:00Z",
            actor: "kethra",
            category: "charter.amended",
            target: "malformed-events-bead",
          }),
        ]),
        addFort("malformed-unannounced", "amend (malformed-unannounced-bead)", [
          "not json",
        ]),
        addFort("historical-malformed", "amend (historical-bead)", []),
      ]);
      const registry = join(directory, "civilization.json");
      await writeFile(
        registry,
        JSON.stringify({
          forts: forts.map((path, index) => ({
            fort_name: [
              "Multi",
              "Unannounced",
              "Wrong category",
              "No ref",
              "Missing events",
              "Malformed events",
              "Malformed unannounced",
              "Historical malformed",
            ][index],
            repo: path,
          })),
        }),
      );
      await mkdir(join(forts[7] as string, "fort", "events"), {
        recursive: true,
      });
      await writeFile(
        join(forts[7] as string, "fort", "events", "events-2026-07-01.jsonl"),
        "not json\n",
      );

      const digest = await readCivilizationDigest(
        registry,
        "2026-08-04T00:00:00Z",
        "2026-08-05T00:00:00Z",
      );
      const diffs = digest.forts.map((fort) => fort.constitutionDiffs?.[0]);
      expect(digest.forts[0]?.eventsTruncated).toBe(1);
      expect(digest.forts[0]?.events).toHaveLength(50);
      expect(digest.forts[0]?.events).not.toContainEqual(
        expect.objectContaining({ category: "charter.amended" }),
      );
      expect(diffs).toMatchObject([
        {
          beadRefs: ["multi-first", "multi-second", "multi-amendment"],
          announced: "announced",
          announcedBeadRef: "multi-amendment",
        },
        { announced: "unannounced", announcedBeadRef: null },
        { announced: "unannounced", announcedBeadRef: null },
        { beadRefs: [], announced: "unannounced", announcedBeadRef: null },
        { announced: "indeterminate", announcedBeadRef: null },
        {
          announced: "announced",
          announcedBeadRef: "malformed-events-bead",
        },
        { announced: "indeterminate", announcedBeadRef: null },
        { announced: "unannounced", announcedBeadRef: null },
      ]);
      expect(digest.forts[7]?.eventsMalformed).toBe(0);
      expect(formatDigest(digest)).toContain("announced: multi-amendment");
      expect(formatDigest(digest)).toContain("NO BEAD REF");
      expect(formatDigest(digest)).toContain("indeterminate");
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });
});

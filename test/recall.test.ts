import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, expect, test } from "vitest";

import { recall } from "../src/recall.ts";

async function fixtureRoot(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "fortkit-recall-"));
  await Promise.all([
    mkdir(join(root, "fort", "memory", "facts"), { recursive: true }),
    mkdir(join(root, "fort", "handoffs"), { recursive: true }),
    mkdir(join(root, "fort", "events"), { recursive: true }),
    mkdir(join(root, "fort", "annals"), { recursive: true }),
    mkdir(join(root, ".beads"), { recursive: true }),
  ]);
  await Promise.all([
    writeFile(
      join(root, "fort", "memory", "facts", "recall-fact.md"),
      `---
key: recall-fact
status: active
superseded-by: null
tier: on-demand
scope:
  seats: [forge]
  topics: [retrieval]
  beads: [fortkit-88u.7]
provenance:
  source: "fortkit-88u.7"
  declared-by: kethra
  date: 2026-08-10
  origin: trusted
---
The ledger-canary proves fact recall.
`,
    ),
    writeFile(
      join(root, "fort", "handoffs", "forge-2026-08-10.md"),
      "# Handoff: Forge 2026-08-10T12:00:00Z\n\n## State of work\n\nThe handoff-canary is ready.\n\n## Next actions\n\nUse recall.\n",
    ),
    writeFile(
      join(root, "fort", "events", "events-local-shard.jsonl"),
      '{"ts":"2026-08-10T23:24:00-08:00","actor":"kethra","seat":"forge","category":"work.begun","target":"fortkit-88u.7","detail":"The event-canary crosses the UTC seam"}\n',
    ),
    writeFile(
      join(root, "fort", "annals", "recall.md"),
      "# Recall annal\n\nThe annal-canary records the ruling.\n",
    ),
    writeFile(
      join(root, ".beads", "issues.jsonl"),
      '{"id":"fortkit-88u.7","status":"in_progress","title":"The bead-canary proves issue recall","updated_at":"2026-08-10T12:00:00Z"}\n',
    ),
  ]);
  return root;
}

describe("fortkit recall", () => {
  test("finds each indexed corpus surface with structured provenance", async () => {
    const root = await fixtureRoot();
    try {
      await expect(
        recall(root, "ledger-canary", {
          seat: "forge",
          topic: "retrieval",
          bead: "fortkit-88u.7",
        }),
      ).resolves.toMatchObject({
        hits: [
          {
            source: "fort/memory/facts/recall-fact.md",
            section: "fact",
            provenance: "fortkit-88u.7",
            actor: "kethra",
          },
        ],
      });
      await expect(recall(root, "handoff-canary", {})).resolves.toMatchObject({
        hits: [
          {
            source: "fort/handoffs/forge-2026-08-10.md",
            section: "State of work",
            seat: "forge",
          },
        ],
      });
      await expect(recall(root, "event-canary", {})).resolves.toMatchObject({
        hits: [
          {
            source: "fort/events/events-local-shard.jsonl",
            section: "work.begun",
            actor: "kethra",
            seat: "forge",
          },
        ],
      });
      await expect(recall(root, "annal-canary", {})).resolves.toMatchObject({
        hits: [{ source: "fort/annals/recall.md", section: "Recall annal" }],
      });
      await expect(recall(root, "bead-canary", {})).resolves.toMatchObject({
        hits: [
          {
            source: ".beads/issues.jsonl",
            section: "fortkit-88u.7",
            provenance: ".beads/issues.jsonl:1",
          },
        ],
      });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("windows parsed event instants across the local-to-UTC seam", async () => {
    const root = await fixtureRoot();
    try {
      const result = await recall(root, "event-canary", {
        since: "2026-08-11T07:00:00Z",
        until: "2026-08-11T08:00:00Z",
      });
      expect(result.hits).toMatchObject([
        {
          date: "2026-08-11T07:24:00.000Z",
          source: "fort/events/events-local-shard.jsonl",
        },
      ]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("discloses unreadable corpus files as gaps", async () => {
    const root = await fixtureRoot();
    const unreadable = join(root, "fort", "annals", "unreadable.md");
    try {
      await writeFile(
        unreadable,
        "# Unreadable\n\nThe gap-canary must not vanish.\n",
      );
      await chmod(unreadable, 0o000);
      const result = await recall(root, "annal-canary", {});
      expect(result.gaps).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ source: "fort/annals/unreadable.md" }),
        ]),
      );
    } finally {
      await chmod(unreadable, 0o600).catch(() => undefined);
      await rm(root, { recursive: true, force: true });
    }
  });
});

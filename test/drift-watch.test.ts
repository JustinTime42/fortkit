import {
  cp,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  utimes,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

import {
  beadIdentity,
  descriptionOf,
  identityOf,
  rows,
  run,
  scan,
  // @ts-expect-error JavaScript watcher exports are exercised as a public CLI seam.
} from "../civ/scripts/drift-watch.mjs";

type Finding = {
  fort: string;
  path: string;
  suggestion: string;
  reason: string;
  identity: string;
  fingerprint: string;
  fortHash: string;
};

type Bead = {
  id: string;
  title: string;
  description: string;
  status: string;
};

const project = fileURLToPath(new URL("..", import.meta.url));

/**
 * A fake tracker standing in for bd.  It writes bead descriptions with the
 * real `descriptionOf` builder, so what the watcher files is exactly what the
 * watcher reads back — the round trip the identity fix depends on.
 */
function tracker(seed: Bead[] = []) {
  const beads: Bead[] = [...seed];
  const comments = new Map<string, string[]>();
  const events: string[] = [];
  let next = 0;
  return {
    beads,
    comments,
    events,
    commands: {
      beads: async () => beads.map((bead) => ({ ...bead })),
      comments: async (id: string) => [...(comments.get(id) ?? [])],
      file: async (finding: Finding) => {
        next += 1;
        beads.push({
          id: `fake-${next}`,
          title: `Drift: ${finding.fort} ${finding.path}`,
          description: descriptionOf(finding),
          status: "open",
        });
      },
      comment: async (id: string, body: string) => {
        comments.set(id, [...(comments.get(id) ?? []), body]);
      },
      emit: async (report: { filed: number }) => {
        events.push(`filed=${report.filed}`);
      },
    },
  };
}

/** The fixture forts are plain directories, so history is injected. */
const noHistory = async () => false;

async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "fortkit-drift-"));
  const root = join(directory, "capital");
  const fort = join(directory, "alpha");
  const sibling = join(directory, "beta");
  await cp(join(project, "templates"), join(root, "templates"), {
    recursive: true,
  });
  await cp(join(root, "templates", "fort"), join(fort, "fort"), {
    recursive: true,
  });
  await mkdir(join(fort, ".claude"), { recursive: true });
  await cp(
    join(root, "templates", "config", "settings-permissions.json"),
    join(fort, ".claude", "settings.json"),
  );
  const charter = (
    await readFile(join(fort, "fort", "charter.md"), "utf8")
  ).replaceAll("{{FORT_NAME}}", "Alpha");
  await writeFile(join(fort, "fort", "charter.md"), charter);
  await cp(fort, sibling, { recursive: true });
  await mkdir(join(root, "civ"), { recursive: true });
  await writeFile(
    join(root, "civ", "drift-allowlist.json"),
    JSON.stringify({ entries: [] }),
  );
  await writeFile(
    join(directory, "registry.json"),
    JSON.stringify({
      forts: [
        { fort_name: "Alpha", repo: fort },
        { fort_name: "Beta", repo: sibling },
      ],
    }),
  );
  return {
    directory,
    root,
    fort,
    sibling,
    registryPath: join(directory, "registry.json"),
    allowlistPath: join(root, "civ", "drift-allowlist.json"),
    gitHistory: noHistory,
  };
}

const wardenProfile = (fort: string) =>
  join(fort, "fort", "profiles", "warden-settings.json");

async function appendTo(path: string, line: string) {
  await writeFile(path, `${await readFile(path, "utf8")}\n${line}\n`);
}

describe("drift watcher", () => {
  test("classifies fort-newer, template-newer, and template loss while normalizing registry values", async () => {
    const subject = await fixture();
    try {
      const templateProfile = join(
        subject.root,
        "templates",
        "fort",
        "profiles",
        "warden-settings.json",
      );
      const fortProfile = wardenProfile(subject.fort);
      await appendTo(fortProfile, "fort change");
      await utimes(fortProfile, new Date("2026-01-02"), new Date("2026-01-02"));
      await appendTo(templateProfile, "template change");
      await utimes(
        templateProfile,
        new Date("2026-01-03"),
        new Date("2026-01-03"),
      );
      // A separate profile isolates the fort-newer input from the template-newer one.
      await writeFile(
        join(subject.root, "templates", "fort", "profiles", "new.json"),
        "template\n",
      );
      await writeFile(
        join(subject.fort, "fort", "profiles", "new.json"),
        "fort\n",
      );
      await utimes(
        join(subject.root, "templates", "fort", "profiles", "new.json"),
        new Date("2025-01-01"),
        new Date("2025-01-01"),
      );
      await utimes(
        join(subject.fort, "fort", "profiles", "new.json"),
        new Date("2026-01-04"),
        new Date("2026-01-04"),
      );
      const charterPath = join(subject.fort, "fort", "charter.md");
      await writeFile(
        charterPath,
        (await readFile(charterPath, "utf8")).replace(
          "## Threat model",
          "## Missing model",
        ),
      );
      await writeFile(
        join(subject.root, "templates", "fort", "profiles", "normalized.txt"),
        "{{FORT_NAME}} {{REPO_PATH}}\n",
      );
      await writeFile(
        join(subject.fort, "fort", "profiles", "normalized.txt"),
        `Alpha ${subject.fort}\n`,
      );

      const report = await scan(subject);
      expect(
        report.findings.some(
          (finding: Finding) => finding.suggestion === "upgrade-offer",
        ),
      ).toBe(true);
      expect(
        report.findings.some(
          (finding: Finding) => finding.suggestion === "backport",
        ),
      ).toBe(true);
      expect(
        report.findings.some(
          (finding: Finding) =>
            finding.suggestion === "regression" &&
            finding.path.startsWith("fort/charter.md"),
        ),
      ).toBe(true);
      expect(
        report.findings.some(
          (finding: Finding) =>
            finding.fort === "Alpha" && finding.path.endsWith("normalized.txt"),
        ),
      ).toBe(false);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("zero-drift fixture produces no findings", async () => {
    const subject = await fixture();
    try {
      expect((await scan(subject)).findings).toEqual([]);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("accepts amended standing orders and rewritten gates by their structural fingerprints", async () => {
    const subject = await fixture();
    try {
      const charterPath = join(subject.fort, "fort", "charter.md");
      const amended = (await readFile(charterPath, "utf8"))
        .replace(
          /^1\. The fort's own constitution[^\n]*$/mu,
          "1. The fort's own constitution — `fort/` files, seat definitions, launchers, permission profiles → Warden + Overseer review. This fort's own amendment defines the remaining gate terms.",
        )
        .replace(
          'Best practices, never "hacky nonsense"; research current best practice before deciding when unsure.',
          'Best practices, never "hacky nonsense"; research current best practice before deciding when unsure. This fort records its local engineering standard here.',
        );
      await writeFile(charterPath, amended);

      expect((await scan(subject)).findings).toEqual([]);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("identifies a finding by fort and path, not by the content of either side", async () => {
    const subject = await fixture();
    try {
      const path = wardenProfile(subject.fort);
      await appendTo(path, "local change");
      const before = (await scan(subject)).findings.find((item: Finding) =>
        item.path.endsWith("warden-settings.json"),
      ) as Finding;
      await appendTo(path, "changed again");
      const after = (await scan(subject)).findings.find((item: Finding) =>
        item.path.endsWith("warden-settings.json"),
      ) as Finding;

      expect(before.identity).toBe(identityOf("Alpha", before.path));
      expect(after.identity).toBe(before.identity);
      expect(after.fingerprint).not.toBe(before.fingerprint);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  // NON-VACUITY: this is the assertion the pre-E7 watcher fails. Keyed on
  // content, the second run minted a new identity and filed a SECOND bead for
  // the same file (fortkit-zvz2: 16 such duplicates in one live run).
  test("drift that changes after filing appends a comment and never files a second bead", async () => {
    const subject = await fixture();
    try {
      const path = wardenProfile(subject.fort);
      await appendTo(path, "local change");
      const fake = tracker();

      const first = await run({ ...subject, commands: fake.commands });
      expect(first.filed).toBe(1);
      expect(first.commented).toBe(0);

      await appendTo(path, "changed again");
      const changed = (await scan(subject)).findings.find((item: Finding) =>
        item.path.endsWith("warden-settings.json"),
      ) as Finding;
      const second = await run({ ...subject, commands: fake.commands });

      expect(second.filed).toBe(0);
      expect(second.commented).toBe(1);
      expect(fake.beads).toHaveLength(1);
      expect(fake.comments.get("fake-1")).toHaveLength(1);
      expect(fake.comments.get("fake-1")?.[0]).toContain(changed.fingerprint);

      // A third run with nothing changed must read its own comment back and
      // stay silent, or the append becomes comment spam on every run.
      const third = await run({ ...subject, commands: fake.commands });
      expect(third.filed).toBe(0);
      expect(third.commented).toBe(0);
      expect(third.identityMatches).toBe(1);
      expect(fake.comments.get("fake-1")).toHaveLength(1);
      expect(fake.beads).toHaveLength(1);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("matches a pre-E7 bead that carries its identity only in its title", async () => {
    const subject = await fixture();
    try {
      const path = wardenProfile(subject.fort);
      await appendTo(path, "local change");
      const finding = (await scan(subject)).findings.find((item: Finding) =>
        item.path.endsWith("warden-settings.json"),
      ) as Finding;
      const legacy: Bead = {
        id: "fortkit-legacy",
        title: `Drift: Alpha ${finding.path}`,
        description: "template-newer byte divergence\nfiled before E7",
        status: "open",
      };
      expect(beadIdentity(legacy)).toBe(finding.identity);

      const fake = tracker([legacy]);
      const report = await run({ ...subject, commands: fake.commands });

      expect(report.filed).toBe(0);
      expect(report.commented).toBe(1);
      expect(fake.beads).toHaveLength(1);
      expect(fake.comments.get("fortkit-legacy")?.[0]).toContain(
        finding.fingerprint,
      );
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("a closed bead carrying the same fingerprint suppresses once, a changed one does not", async () => {
    const subject = await fixture();
    try {
      const path = wardenProfile(subject.fort);
      await appendTo(path, "local change");
      const finding = (await scan(subject)).findings.find((item: Finding) =>
        item.path.endsWith("warden-settings.json"),
      ) as Finding;
      const closed: Bead = {
        id: "fortkit-closed",
        title: `Drift: Alpha ${finding.path}`,
        description: descriptionOf(finding),
        status: "closed",
      };

      const quiet = tracker([closed]);
      const suppressedReport = await run({
        ...subject,
        commands: quiet.commands,
      });
      expect(suppressedReport.filed).toBe(0);
      expect(suppressedReport.commented).toBe(0);
      expect(
        suppressedReport.suppressed.some(
          (entry: { by: string }) => entry.by === "closed-bead",
        ),
      ).toBe(true);

      await appendTo(path, "changed after it was closed");
      const loud = tracker([closed]);
      const resurfaced = await run({ ...subject, commands: loud.commands });
      expect(resurfaced.filed).toBe(1);
      expect(loud.beads).toHaveLength(2);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("absence is a regression only where the fort's history carries the path", async () => {
    const subject = await fixture();
    try {
      await writeFile(
        join(subject.root, "templates", "fort", "scripts", "newcomer.sh"),
        "#!/usr/bin/env bash\necho newcomer\n",
      );

      const never = await scan({ ...subject, gitHistory: async () => false });
      const neverSeen = never.findings.find((item: Finding) =>
        item.path.endsWith("newcomer.sh"),
      ) as Finding;
      expect(neverSeen.suggestion).toBe("not-yet-propagated");

      const lost = await scan({ ...subject, gitHistory: async () => true });
      const regressed = lost.findings.find((item: Finding) =>
        item.path.endsWith("newcomer.sh"),
      ) as Finding;
      expect(regressed.suggestion).toBe("regression");
      expect(regressed.identity).toBe(neverSeen.identity);

      const unreadable = await scan({
        ...subject,
        gitHistory: async () => {
          throw new Error("not a git repository");
        },
      });
      const undecided = unreadable.findings.find((item: Finding) =>
        item.path.endsWith("newcomer.sh"),
      ) as Finding;
      expect(undecided.suggestion).toBe("regression");
      expect(
        unreadable.gaps.some((gap: { reason: string }) =>
          gap.reason.includes("git history unreadable"),
        ),
      ).toBe(true);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("a never-propagated file with no open bead is deferred rather than filed", async () => {
    const subject = await fixture();
    try {
      await writeFile(
        join(subject.root, "templates", "fort", "scripts", "newcomer.sh"),
        "#!/usr/bin/env bash\necho newcomer\n",
      );
      const fake = tracker();
      const report = await run({ ...subject, commands: fake.commands });

      expect(report.filed).toBe(0);
      expect(fake.beads).toHaveLength(0);
      expect(
        report.deferred.map((finding: Finding) => finding.path).sort(),
      ).toEqual(["fort/scripts/newcomer.sh", "fort/scripts/newcomer.sh"]);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("an allowlist entry suppresses one content state and discloses its lapse", async () => {
    const subject = await fixture();
    try {
      const path = wardenProfile(subject.fort);
      await appendTo(path, "local change");
      const finding = (await scan(subject)).findings.find((item: Finding) =>
        item.path.endsWith("warden-settings.json"),
      ) as Finding;
      await writeFile(
        subject.allowlistPath,
        JSON.stringify({
          entries: [
            {
              fort: "Alpha",
              path: finding.path,
              "content-hash": finding.fortHash,
              bead: "fortkit-example",
              date: "2026-08-10",
            },
          ],
        }),
      );

      const quiet = await scan(subject);
      expect(
        quiet.findings.some((item: Finding) => item.path === finding.path),
      ).toBe(false);
      expect(quiet.lapsed).toEqual([]);

      await appendTo(path, "changed again");
      const noisy = await scan(subject);
      expect(
        noisy.findings.some((item: Finding) => item.path === finding.path),
      ).toBe(true);
      expect(noisy.lapsed).toEqual([
        expect.objectContaining({
          fort: "Alpha",
          path: finding.path,
          bead: "fortkit-example",
          approved: finding.fortHash,
        }),
      ]);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("discloses unreadable forts and dry-run reads the tracker without writing to it", async () => {
    const subject = await fixture();
    try {
      await rm(subject.fort, { recursive: true, force: true });
      const gap = await scan(subject);
      expect(gap.gaps).toHaveLength(1);
      let reads = 0;
      let writes = 0;
      const result = await run({
        ...subject,
        dryRun: true,
        commands: {
          beads: async () => {
            reads += 1;
            return [];
          },
          comments: async () => {
            reads += 1;
            return [];
          },
          file: async () => {
            writes += 1;
          },
          comment: async () => {
            writes += 1;
          },
          emit: async () => {
            writes += 1;
          },
        },
      });
      expect(result.filed).toBe(0);
      expect(result.commented).toBe(0);
      expect(reads).toBe(1);
      expect(writes).toBe(0);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("continues scanning valid registry entries while disclosing malformed ones", async () => {
    const subject = await fixture();
    try {
      const relativeFort = "./alpha";
      await writeFile(
        subject.registryPath,
        JSON.stringify({
          forts: [
            { project: "Alpha", repo: relativeFort },
            { fort_name: null, repo: subject.sibling },
          ],
        }),
      );

      const report = await scan(subject);
      expect(report.fortsScanned).toBe(1);
      expect(report.findings).toEqual([]);
      expect(report.gaps).toEqual([
        expect.objectContaining({
          source: `${subject.registryPath} entry 2`,
          reason: expect.stringContaining("fort_name/project or repo"),
        }),
      ]);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("reads both the current bd --json array and the v2.0 envelope", () => {
    expect(rows([{ id: "one" }])).toEqual([{ id: "one" }]);
    expect(rows({ data: [{ id: "one" }], schema_version: 1 })).toEqual([
      { id: "one" },
    ]);
    expect(() => rows({ error: "nope" })).toThrow(/unrecognised bd --json/u);
  });
});

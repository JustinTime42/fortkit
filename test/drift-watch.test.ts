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

// @ts-expect-error JavaScript watcher exports are exercised as a public CLI seam.
import { run, scan } from "../civ/scripts/drift-watch.mjs";

type Finding = {
  fort: string;
  path: string;
  suggestion: string;
  fingerprint: string;
  fortHash: string;
};

const project = fileURLToPath(new URL("..", import.meta.url));

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
  };
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
      const fortProfile = join(
        subject.fort,
        "fort",
        "profiles",
        "warden-settings.json",
      );
      await writeFile(
        fortProfile,
        `${await readFile(fortProfile, "utf8")}\nfort change\n`,
      );
      await utimes(fortProfile, new Date("2026-01-02"), new Date("2026-01-02"));
      await writeFile(
        templateProfile,
        `${await readFile(templateProfile, "utf8")}\ntemplate change\n`,
      );
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

  test("suppresses stable fingerprints across runs and only allows an exact content state", async () => {
    const subject = await fixture();
    try {
      const path = join(
        subject.fort,
        "fort",
        "profiles",
        "warden-settings.json",
      );
      await writeFile(path, `${await readFile(path, "utf8")}\nlocal change\n`);
      const first = await scan(subject);
      const finding = first.findings.find((item: Finding) =>
        item.path.endsWith("warden-settings.json"),
      ) as Finding | undefined;
      expect(finding).toBeDefined();
      const known = new Set<string>();
      const filed: string[] = [];
      const events: number[] = [];
      const commands = {
        existing: async () => known,
        file: async (item: { fingerprint: string }) => {
          filed.push(item.fingerprint);
          known.add(item.fingerprint);
        },
        emit: async () => {
          events.push(1);
        },
      };
      await run({ ...subject, commands });
      await run({ ...subject, commands });
      expect(filed).toHaveLength(1);
      expect(events).toHaveLength(2);
      await writeFile(
        subject.allowlistPath,
        JSON.stringify({
          entries: [
            {
              fort: "Alpha",
              path: finding?.path,
              "content-hash": finding?.fortHash,
              bead: "fortkit-example",
              date: "2026-08-10",
            },
          ],
        }),
      );
      expect(
        (await scan(subject)).findings.some(
          (item: Finding) => item.path === finding?.path,
        ),
      ).toBe(false);
      await writeFile(path, `${await readFile(path, "utf8")}\nchanged again\n`);
      expect(
        (await scan(subject)).findings.some(
          (item: Finding) => item.path === finding?.path,
        ),
      ).toBe(true);
    } finally {
      await rm(subject.directory, { recursive: true, force: true });
    }
  });

  test("discloses unreadable forts and dry-run does not invoke write seams", async () => {
    const subject = await fixture();
    try {
      await rm(subject.fort, { recursive: true, force: true });
      const gap = await scan(subject);
      expect(gap.gaps).toHaveLength(1);
      let writes = 0;
      const result = await run({
        ...subject,
        dryRun: true,
        commands: {
          existing: async () => {
            writes += 1;
            return new Set();
          },
          file: async () => {
            writes += 1;
          },
          emit: async () => {
            writes += 1;
          },
        },
      });
      expect(result.filed).toBe(0);
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
});

import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

const run = promisify(execFile);
const lint = fileURLToPath(
  new URL("../scripts/seat-lint.mjs", import.meta.url),
);

const UNFILLED = "{{UNFILLED — set at the Founding Moot}}";

interface Occupant {
  name: string | null;
  personality?: string;
  body?: string;
}

function seatFile(seat: string, occupant: Occupant): string {
  const held =
    occupant.name === null
      ? `**Held by:** ${UNFILLED}`
      : `**Held by: ${occupant.name}** (she/her, declared 2026-08-03 at the Founding Moot)`;
  const personality =
    occupant.personality ??
    (occupant.name === null ? UNFILLED : `"I hold the ${seat} seat."`);
  return [
    `# Seat: ${seat}`,
    "",
    held,
    "",
    `**Personality (in their own words):** ${personality}`,
    "",
    `**Role:** ${seat} work.`,
    "",
    occupant.body ?? "",
  ].join("\n");
}

interface FortSpec {
  project: string;
  fortName: string | null;
  seats: Record<string, Occupant>;
}

/**
 * Builds a scratch civilization: one fort under test plus any siblings, and a
 * registry at a path FORT_REGISTRY can point the lint at. bin/fort-init:223 reads
 * the registry through that same variable, so the fixture exercises the real
 * lookup rather than a test-only one.
 */
async function buildCivilization(
  forts: [FortSpec, ...FortSpec[]],
): Promise<{ root: string; registry: string }> {
  const base = await mkdtemp(join(tmpdir(), "fortkit-seat-lint-"));
  const entries = [];
  for (const fort of forts) {
    const root = join(base, fort.project);
    await mkdir(join(root, "fort", "seats"), { recursive: true });
    const names = Object.values(fort.seats)
      .map((occupant) => occupant.name)
      .filter((name): name is string => name !== null);
    await writeFile(
      join(root, "fort", "charter.md"),
      `# Charter\n\nOccupants: ${names.join(", ")}.\n`,
    );
    await Promise.all(
      Object.entries(fort.seats).map(([seat, occupant]) =>
        writeFile(
          join(root, "fort", "seats", `${seat}.md`),
          seatFile(seat, occupant),
        ),
      ),
    );
    entries.push({
      project: fort.project,
      repo: root,
      founded: "2026-08-03",
      fort_name: fort.fortName,
    });
  }
  const registry = join(base, "civilization.json");
  await writeFile(
    registry,
    JSON.stringify({ civilization: "test", forts: entries }, null, 2),
  );
  // The fort under test is always the first; any others exist to populate the
  // foreign roster rule 2 reads.
  return { root: join(base, forts[0].project), registry };
}

async function lintFort(root: string, registry: string) {
  const outputDirectory = await mkdtemp(
    join(tmpdir(), "fortkit-seat-lint-output-"),
  );
  const stdoutPath = join(outputDirectory, "stdout");
  const stderrPath = join(outputDirectory, "stderr");
  const result = await run(
    "sh",
    [
      "-c",
      'stdout="$1"; stderr="$2"; shift 2; "$@" > "$stdout" 2> "$stderr"',
      "sh",
      stdoutPath,
      stderrPath,
      process.execPath,
      lint,
      root,
    ],
    { env: { ...process.env, FORT_REGISTRY: registry } },
  ).then(
    () => ({ code: 0 }),
    (error: { code?: number }) => ({ code: error.code }),
  );
  return {
    ...result,
    stdout: await readFile(stdoutPath, "utf8"),
    stderr: await readFile(stderrPath, "utf8"),
  };
}

describe("seat-file lint (fortkit-x508)", () => {
  test("refuses actor ids one keystroke apart, and only warns at distance two", async () => {
    // THE THRESHOLD IS THE OVERSEER'S RULING OF 2026-08-13 AS WRITTEN: distance 1
    // refuses, distance 2 warns. Recorded here because writing this fixture
    // measured something the ruling's own record does not say —
    // `kestra`/`kethra`, named in both fortkit-8rh and fortkit-x508 as the
    // collision the rule exists for, is at distance 2, exactly like the
    // `oswin`/`orin` pair the ruling cites as the reason NOT to refuse at 2. So a
    // synthetic distance-1 pair is used for the refuse case below, and the
    // motivating pair appears among the WARN cases where the ruling puts it.
    // Escalated to the Overseer on fortkit-8rh rather than resolved here.
    const collision = await buildCivilization([
      {
        project: "alpha",
        fortName: "Alpha",
        seats: {
          mayor: { name: "Kethra Anvilmark" },
          forge: { name: "Kelhra Ironvein" },
        },
      },
    ]);
    const refused = await lintFort(collision.root, collision.registry).catch(
      (error: { code?: number; stderr?: string }) => error,
    );
    expect(refused).toMatchObject({ code: 1 });
    expect((refused as { stderr: string }).stderr).toContain("edit distance 1");

    // Distance 2 must PASS, and both live pairs sit there. oswin (civ fifth seat)
    // and orin (Farlantern Forge) are in a roster the civilization already runs,
    // so refusing at 2 would go red today; kestra/kethra measures the same.
    for (const [project, mayor, forge] of [
      ["beta", "Oswin Fairholt", "Orin Deeplantern"],
      ["beta2", "Kethra Anvilmark", "Kestra Ironvein"],
    ] as const) {
      const near = await buildCivilization([
        {
          project,
          fortName: "Beta",
          seats: { mayor: { name: mayor }, forge: { name: forge } },
        },
      ]);
      const passed = await lintFort(near.root, near.registry);
      expect(passed.code).toBe(0);
      expect(passed.stderr).toContain("edit distance 2");
      expect(passed.stdout).toContain("2 occupied of 2 seat file(s)");
    }
  });

  test("exempts a pre-moot fort and refuses the same tree once the moot names it", async () => {
    // Acceptance 3 and 4 are the SAME TREE read against two registries. A correctly
    // founded fort is full of placeholders on day zero and must pass; the moot
    // setting fort_name is what turns those placeholders into a failure.
    const preMoot = await buildCivilization([
      {
        project: "gamma",
        fortName: null,
        seats: { mayor: { name: null }, forge: { name: null } },
      },
    ]);
    const exempt = await lintFort(preMoot.root, preMoot.registry);
    expect(exempt.code).toBe(0);
    expect(exempt.stdout).toContain("rule 3 EXEMPT");

    const postMoot = await buildCivilization([
      {
        project: "gamma",
        fortName: "Gamma",
        seats: { mayor: { name: null }, forge: { name: null } },
      },
    ]);
    const refused = await lintFort(postMoot.root, postMoot.registry).catch(
      (error: { code?: number; stderr?: string }) => error,
    );
    expect(refused).toMatchObject({ code: 1 });
    expect((refused as { stderr: string }).stderr).toContain("{{placeholder}}");

    // ...and filling them clears it, so the rule tracks the roster rather than the
    // registry alone.
    const filled = await buildCivilization([
      {
        project: "gamma",
        fortName: "Gamma",
        seats: {
          mayor: { name: "Yrsa Coldwater" },
          forge: { name: "Bren Tallowmark" },
        },
      },
    ]);
    const filledResult = await lintFort(filled.root, filled.registry);
    expect(filledResult.code).toBe(0);
  });

  test("refuses an inherited citizen while allowing an attribution", async () => {
    // Rule 2, both halves of the Overseer's ruling in one fixture: the Held-by and
    // Personality lines may not carry another settlement's citizen (standing order
    // 12), while a comment crediting that citizen for a finding is provenance and
    // must NOT be refused — the live examples being
    // templates/fort/scripts/lib/seat-sandbox.sh:127,455, which credit Ilva Trueglass.
    const elder: FortSpec = {
      project: "elder",
      fortName: "Elderfort",
      seats: { warden: { name: "Ilva Trueglass" } },
    };

    const inherited = await buildCivilization([
      {
        project: "young",
        fortName: "Youngfort",
        seats: {
          warden: {
            name: "Ilva Trueglass",
            personality: '"I review as though every diff will travel."',
          },
        },
      },
      elder,
    ]);
    const refused = await lintFort(inherited.root, inherited.registry).catch(
      (error: { code?: number; stderr?: string }) => error,
    );
    expect(refused).toMatchObject({ code: 1 });
    expect((refused as { stderr: string }).stderr).toContain("Elderfort");

    const attribution = await buildCivilization([
      {
        project: "young",
        fortName: "Youngfort",
        seats: {
          warden: {
            name: "Sereth Duskbanner",
            body: "Backported from Elderfort (Ilva Trueglass, she/her) — her finding, our fort.\n",
          },
        },
      },
      elder,
    ]);
    const allowed = await lintFort(attribution.root, attribution.registry);
    expect(allowed.code).toBe(0);
    expect(allowed.stdout).toContain("rule 2 checked against 1 citizen(s)");
  });

  test("refuses a roster the charter does not name", async () => {
    const { root, registry } = await buildCivilization([
      {
        project: "delta",
        fortName: "Delta",
        seats: { mayor: { name: "Yrsa Coldwater" } },
      },
    ]);
    await writeFile(
      join(root, "fort", "charter.md"),
      "# Charter\n\nOccupants: nobody recorded here.\n",
    );
    const refused = await lintFort(root, registry).catch(
      (error: { code?: number; stderr?: string }) => error,
    );
    expect(refused).toMatchObject({ code: 1 });
    expect((refused as { stderr: string }).stderr).toContain("Yrsa Coldwater");
  });

  test("refuses an empty roster instead of reporting a vacuous pass", async () => {
    const { root, registry } = await buildCivilization([
      { project: "epsilon", fortName: "Epsilon", seats: {} },
    ]);
    const refused = await lintFort(root, registry).catch(
      (error: { code?: number; stderr?: string }) => error,
    );
    expect(refused).toMatchObject({ code: 1 });
    expect((refused as { stderr: string }).stderr).toContain("proved nothing");
  });

  test("announces the skip when the registry cannot place this fort", async () => {
    // Failing OPEN here would be the worst shape available: a fort whose registry
    // entry is missing would silently stop being checked for rules 2 and 3 while
    // still exiting 0. The skip is therefore stated by name in the output.
    const { root } = await buildCivilization([
      {
        project: "zeta",
        fortName: "Zeta",
        seats: { mayor: { name: "Yrsa Coldwater" } },
      },
    ]);
    const orphan = await lintFort(root, join(root, "absent.json"));
    expect(orphan.code).toBe(0);
    expect(orphan.stdout).toContain("rules 2 (foreign citizens) and 3");
    expect(orphan.stdout).toContain("SKIPPED");
  });

  test("the live capital passes its own lint against a pinned registry", async () => {
    // THE REGISTRY IS PINNED, AND THAT IS THE WHOLE POINT OF THIS VERSION.
    // The first one ran the lint with no FORT_REGISTRY and asserted "rule 3
    // enforced", which holds only when the checkout it happens to run in is listed
    // in $HOME/.claude/civilization.json with a non-null fort_name. That is ambient
    // machine state, and it turned the fort's authoritative verifier RED in the
    // Warden's review scratch (measured, blocking finding 1 on fortkit-x508) and
    // would turn it red on a GitHub runner, which has no registry at all
    // (.github/workflows/ci.yml:29). Same class as fortkit-h5i: green for the author,
    // red everywhere else. Pinning asserts the CODE against the real roster instead
    // of asserting the disk.
    //
    // WHAT THIS DOES NOT COVER, stated so nobody reads it as more than it is: rules 2
    // and 3 are structurally unenforceable on a runner, because a runner has neither
    // a registry nor sibling forts. The shared gate carries rule 1 and the charter
    // cross-check everywhere; rules 2 and 3 are enforced only on a machine that hosts
    // the civilization.
    const repositoryRoot = fileURLToPath(new URL("..", import.meta.url));
    const base = await mkdtemp(join(tmpdir(), "fortkit-seat-lint-capital-"));
    const registry = join(base, "civilization.json");
    await writeFile(
      registry,
      JSON.stringify({
        civilization: "test",
        forts: [
          {
            project: "fortkit",
            repo: repositoryRoot,
            founded: "2026-08-03",
            fort_name: "Manyhalls",
          },
        ],
      }),
    );
    const result = await lintFort(repositoryRoot, registry);
    expect(result.code).toBe(0);
    expect(result.stdout).toContain("rule 3 enforced");
    expect(result.stdout).toContain("charter cross-check");
  });
});

import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

const run = promisify(execFile);
const lint = fileURLToPath(
  new URL("../scripts/control-lint.mjs", import.meta.url),
);
const repositoryRoot = fileURLToPath(new URL("..", import.meta.url));

async function controlFixture() {
  const root = await mkdtemp(join(tmpdir(), "fortkit-control-lint-"));
  await mkdir(join(root, "fort", "controls"), { recursive: true });
  await mkdir(join(root, "scripts"), { recursive: true });
  await Promise.all([
    writeFile(
      join(root, "scripts", "subject.mjs"),
      "export const control = true;\n",
    ),
    writeFile(
      join(root, "fort", "controls", "fence-example.md"),
      "---\nkey: fence-example\nstatus: active\nkind: fence\nimplements: scripts/subject.mjs:1\nfalsified-by: null\n---\n",
    ),
  ]);
  const subject = await readFile(join(root, "scripts", "subject.mjs"), "utf8");
  const { createHash } = await import("node:crypto");
  await writeFile(
    join(root, "scripts", "control-fingerprints.json"),
    `${JSON.stringify(
      {
        "fence-example": createHash("sha256")
          .update(subject.trimEnd(), "utf8")
          .digest("hex"),
      },
      null,
      2,
    )}\n`,
  );
  return root;
}

async function lintFort(root: string, arguments_: string[] = []) {
  const outputDirectory = await mkdtemp(
    join(tmpdir(), "fortkit-control-lint-output-"),
  );
  const stdoutPath = join(outputDirectory, "stdout");
  const stderrPath = join(outputDirectory, "stderr");
  const result = await run("sh", [
    "-c",
    'stdout="$1"; stderr="$2"; shift 2; "$@" > "$stdout" 2> "$stderr"',
    "sh",
    stdoutPath,
    stderrPath,
    process.execPath,
    lint,
    ...arguments_,
    root,
  ]).then(
    () => ({ code: 0 }),
    (error: { code?: number; stdout?: string; stderr?: string }) => ({
      code: error.code,
    }),
  );
  return {
    ...result,
    stdout: await readFile(stdoutPath, "utf8"),
    stderr: await readFile(stderrPath, "utf8"),
  };
}

describe("control-register lint (fortkit-4ah3.3)", () => {
  test("the live register passes and reports controls without falsifiers", async () => {
    const result = await lintFort(repositoryRoot);
    expect(result.code).toBe(0);
    const count = /control-lint: (\d+) control file\(s\) checked/u.exec(
      result.stdout,
    );
    expect(count).not.toBeNull();
    expect(Number(count?.[1])).toBeGreaterThanOrEqual(45);
    expect(result.stdout).toContain("reported, not failed");
  });

  test("refuses a citation whose cited line changed", async () => {
    const root = await controlFixture();
    await writeFile(
      join(root, "scripts", "subject.mjs"),
      "export const control = false;\n",
    );
    const failure = await lintFort(root);
    expect(failure.code).toBe(1);
    expect(failure.stderr).toContain(
      "no longer matches its recorded fingerprint",
    );
  });

  test("records one fingerprint by re-reading its cited line", async () => {
    const root = await controlFixture();
    await writeFile(
      join(root, "scripts", "subject.mjs"),
      "export const control = false;\n",
    );
    const recording = await lintFort(root, ["--record", "fence-example"]);
    expect(recording.code).toBe(0);
    expect(recording.stdout).toContain(
      "recorded fence-example from scripts/subject.mjs:1",
    );
    expect((await lintFort(root)).code).toBe(0);
  });

  test("refuses to record when the cited line does not resolve", async () => {
    const root = await controlFixture();
    const fingerprintsPath = join(root, "scripts", "control-fingerprints.json");
    const before = await readFile(fingerprintsPath, "utf8");
    await writeFile(
      join(root, "fort", "controls", "fence-example.md"),
      "---\nkey: fence-example\nstatus: active\nkind: fence\nimplements: scripts/subject.mjs:99\nfalsified-by: null\n---\n",
    );
    const recording = await lintFort(root, ["--record", "fence-example"]);
    expect(recording.code).toBe(1);
    expect(recording.stderr).toContain(
      "implements line scripts/subject.mjs:99 does not exist",
    );
    expect(await readFile(fingerprintsPath, "utf8")).toBe(before);
  });

  test("refuses a vacuous control register", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-control-lint-empty-"));
    await mkdir(join(root, "fort", "controls"), { recursive: true });
    await mkdir(join(root, "scripts"), { recursive: true });
    await Promise.all([
      writeFile(join(root, "scripts", "control-fingerprints.json"), "{}\n"),
    ]);
    const failure = await lintFort(root);
    expect(failure.code).toBe(1);
    expect(failure.stderr).toContain("proved nothing");
  });

  test("refuses an unknown kind and an omitted falsifier", async () => {
    const root = await controlFixture();
    await writeFile(
      join(root, "fort", "controls", "fence-example.md"),
      "---\nkey: fence-example\nstatus: active\nkind: unknown\nimplements: scripts/subject.mjs:1\n---\n",
    );
    const failure = await lintFort(root);
    expect(failure.code).toBe(1);
    expect(failure.stderr).toContain("unknown kind");
    expect(failure.stderr).toContain(
      "falsified-by must be declared explicitly",
    );
  });

  test("refuses an unknown control status", async () => {
    const root = await controlFixture();
    await writeFile(
      join(root, "fort", "controls", "fence-example.md"),
      "---\nkey: fence-example\nstatus: pending\nkind: fence\nimplements: scripts/subject.mjs:1\nfalsified-by: null\n---\n",
    );
    const failure = await lintFort(root);
    expect(failure.code).toBe(1);
    expect(failure.stderr).toContain('unknown status "pending"');
  });

  test("reports blank and whitespace-padded null falsifiers as null", async () => {
    const root = await controlFixture();
    await writeFile(
      join(root, "fort", "controls", "fence-example.md"),
      "---\nkey: fence-example\nstatus: active\nkind: fence\nimplements: scripts/subject.mjs:1\nfalsified-by: null \n---\n",
    );
    const paddedNull = await lintFort(root);
    expect(paddedNull.code).toBe(0);
    expect(paddedNull.stdout).toContain(
      "fence-example: falsified-by is null (reported, not failed)",
    );

    await writeFile(
      join(root, "fort", "controls", "fence-example.md"),
      "---\nkey: fence-example\nstatus: active\nkind: fence\nimplements: scripts/subject.mjs:1\nfalsified-by:\n---\n",
    );
    const blank = await lintFort(root);
    expect(blank.code).toBe(0);
    expect(blank.stdout).toContain(
      "fence-example: falsified-by is null (reported, not failed)",
    );
  });

  test("refuses a falsifier that is not registered", async () => {
    const root = await controlFixture();
    await writeFile(
      join(root, "fort", "controls", "fence-example.md"),
      "---\nkey: fence-example\nstatus: active\nkind: fence\nimplements: scripts/subject.mjs:1\nfalsified-by: fence-verifer\n---\n",
    );
    const failure = await lintFort(root);
    expect(failure.code).toBe(1);
    expect(failure.stderr).toContain(
      'falsified-by "fence-verifer" does not name a registered control',
    );
  });

  test("refuses unresolved citations and fingerprints", async () => {
    const cases = [
      {
        implements: "scripts/missing.mjs:1",
        expected: "implements path scripts/missing.mjs:1 does not exist",
      },
      {
        implements: "scripts/subject.mjs:99",
        expected: "implements line scripts/subject.mjs:99 does not exist",
      },
      {
        implements: "../outside.mjs:1",
        expected: "implements must be a repository-relative file:line citation",
      },
    ];
    for (const { implements: implementation, expected } of cases) {
      const root = await controlFixture();
      await writeFile(
        join(root, "fort", "controls", "fence-example.md"),
        `---\nkey: fence-example\nstatus: active\nkind: fence\nimplements: ${implementation}\nfalsified-by: null\n---\n`,
      );
      const failure = await lintFort(root);
      expect(failure.code).toBe(1);
      expect(failure.stderr).toContain(expected);
    }

    const root = await controlFixture();
    await writeFile(join(root, "scripts", "control-fingerprints.json"), "{}\n");
    const failure = await lintFort(root);
    expect(failure.code).toBe(1);
    expect(failure.stderr).toContain("no recorded fingerprint");
  });
});

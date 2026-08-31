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
  await Promise.all([
    mkdir(join(root, "fort", "controls"), { recursive: true }),
    mkdir(join(root, "scripts"), { recursive: true }),
  ]);
  await Promise.all([
    writeFile(
      join(root, "scripts", "subject.mjs"),
      "export const control = true;\n",
    ),
    writeFile(
      join(root, "fort", "controls", "fence-example.md"),
      "---\nkey: fence-example\nkind: fence\nimplements: scripts/subject.mjs:1\nfalsified-by: null\n---\n",
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

async function lintFort(root: string) {
  const outputDirectory = await mkdtemp(
    join(tmpdir(), "fortkit-control-lint-output-"),
  );
  const stdoutPath = join(outputDirectory, "stdout");
  const stderrPath = join(outputDirectory, "stderr");
  const result = await run("sh", [
    "-c",
    '"$1" "$2" "$3" > "$4" 2> "$5"',
    "sh",
    process.execPath,
    lint,
    root,
    stdoutPath,
    stderrPath,
  ]).then(
    () => ({ code: 0 }),
    (error: { code?: number }) => ({ code: error.code }),
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
    expect(result.stdout).toContain("45 control file(s) checked");
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

  test("refuses a vacuous control register", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-control-lint-empty-"));
    await Promise.all([
      mkdir(join(root, "fort", "controls"), { recursive: true }),
      mkdir(join(root, "scripts"), { recursive: true }),
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
      "---\nkey: fence-example\nkind: unknown\nimplements: scripts/subject.mjs:1\n---\n",
    );
    const failure = await lintFort(root);
    expect(failure.code).toBe(1);
    expect(failure.stderr).toContain("unknown kind");
    expect(failure.stderr).toContain(
      "falsified-by must be declared explicitly",
    );
  });
});

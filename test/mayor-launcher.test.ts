import { execFile } from "node:child_process";
import {
  access,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { afterEach, describe, expect, test } from "vitest";

const execFileAsync = promisify(execFile);
const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const templateLauncher = join(repoRoot, "templates/fort/scripts/mayor.sh");
const roots: string[] = [];

async function createFort() {
  const root = await mkdtemp(join(tmpdir(), "fortkit-mayor-launcher-"));
  roots.push(root);
  await execFileAsync("git", ["init", "--quiet"], { cwd: root });
  await mkdir(join(root, "fort/scripts"), { recursive: true });
  await mkdir(join(root, "bin"));

  const source = await readFile(templateLauncher, "utf8");
  const launcher = join(root, "mayor.sh");
  await writeFile(launcher, source.replaceAll("{{REPO_PATH}}", root), {
    mode: 0o755,
  });
  await writeFile(join(root, "fort/scripts/emit.sh"), "#!/bin/bash\nexit 0\n", {
    mode: 0o755,
  });
  await writeFile(
    join(root, "bin/claude"),
    "#!/bin/bash\nprintf 'fake claude launched\\n'\n",
    { mode: 0o755 },
  );
  return { launcher, root };
}

async function expectNoEvents(root: string) {
  await expect(access(join(root, "fort/events"))).rejects.toMatchObject({
    code: "ENOENT",
  });
}

afterEach(async () => {
  await Promise.all(
    roots.splice(0).map((root) => rm(root, { force: true, recursive: true })),
  );
});

describe("Mayor template launcher", () => {
  test.each(["mayor", "forge", "warden", "1"])(
    "refuses a nested launch from the %s mask",
    async (marker) => {
      const { launcher, root } = await createFort();

      await expect(
        execFileAsync("bash", [launcher], {
          cwd: root,
          env: { ...process.env, FORT_MASKED: marker },
          timeout: 5_000,
        }),
      ).rejects.toMatchObject({
        code: 77,
        stderr: expect.stringContaining(
          `already inside the '${marker}' seat mask`,
        ),
      });
      await expectNoEvents(root);
    },
  );

  test("launches when not already masked", async () => {
    const { launcher, root } = await createFort();

    await expect(
      execFileAsync("bash", [launcher], {
        cwd: root,
        env: {
          ...process.env,
          MAYOR_NO_MASK: "1",
          PATH: `${join(root, "bin")}:${process.env.PATH}`,
        },
        timeout: 5_000,
      }),
    ).resolves.toMatchObject({
      stdout: "fake claude launched\n",
    });
    await expectNoEvents(root);
  });

  test("carries the complete Mayor push gate into founded forts", async () => {
    const source = await readFile(templateLauncher, "utf8");

    expect(source).toContain(
      "Never push or deploy on your own initiative, in a batch of other work, or because it seems implied.",
    );
    expect(source).toContain(
      "If you are unsure whether he has approved this specific action, you have not been approved.",
    );
  });
});

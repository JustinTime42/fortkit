import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

const execFileAsync = promisify(execFile);
const root = fileURLToPath(new URL("..", import.meta.url));
const launcher = `${root}templates/fort/scripts/mayor.sh`;

describe("Mayor template launcher", () => {
  test.each(["mayor", "forge", "warden", "1"])(
    "refuses a nested launch from the %s mask",
    async (marker) => {
      await expect(
        execFileAsync("bash", [launcher], {
          cwd: root,
          env: { ...process.env, FORT_MASKED: marker },
        }),
      ).rejects.toMatchObject({
        code: 77,
        stderr: expect.stringContaining(
          `already inside the '${marker}' seat mask`,
        ),
      });
    },
  );

  test("carries the complete Mayor push gate into founded forts", async () => {
    const source = await readFile(launcher, "utf8");

    expect(source).toContain(
      "Never push or deploy on your own initiative, in a batch of other work, or because it seems implied.",
    );
    expect(source).toContain(
      "If you are unsure whether he has approved this specific action, you have not been approved.",
    );
  });
});

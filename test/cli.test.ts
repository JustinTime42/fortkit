import { execFile } from "node:child_process";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

const execFileAsync = promisify(execFile);

describe("world CLI", () => {
  test("rejects unknown arguments when --port is absent", async () => {
    await expect(
      execFileAsync("node", ["src/cli.ts", "world", "nonsense"]),
    ).rejects.toMatchObject({ code: 2 });
  });
});

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

  test("requires a valid non-empty digest window", async () => {
    await expect(
      execFileAsync("node", ["src/cli.ts", "digest", "--since", "invalid"]),
    ).rejects.toMatchObject({ code: 2 });
    await expect(
      execFileAsync("node", [
        "src/cli.ts",
        "digest",
        "--since",
        "2026-08-04T09:00:00Z",
        "--until",
        "2026-08-04T09:00:00Z",
      ]),
    ).rejects.toMatchObject({ code: 2 });
  });
});

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { describe, expect, test } from "vitest";

const execFileAsync = promisify(execFile);

describe("fortkit CLI", () => {
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

  test("the retired view commands are refused with the usage line", async () => {
    await expect(
      execFileAsync("node", ["src/cli.ts", "world"]),
    ).rejects.toMatchObject({ code: 2 });
    await expect(
      execFileAsync("node", ["src/cli.ts", "ambient", "kethra"]),
    ).rejects.toMatchObject({ code: 2 });
  });
});

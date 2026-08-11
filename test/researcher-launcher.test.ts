import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

const root = fileURLToPath(new URL("..", import.meta.url));
const launcher = `${root}templates/fort/scripts/researcher.sh`;
const profile = `${root}templates/fort/profiles/researcher-settings.json`;

describe("Researcher template boundary", () => {
  test("uses only the read/search tools and its isolated settings profile", async () => {
    const source = await readFile(launcher, "utf8");

    expect(source).toContain('--tools "WebSearch,WebFetch,Read,Grep,Glob"');
    expect(source).toContain('--setting-sources ""');
    expect(source).toContain("researcher-settings.json");
    expect(source).toContain('build_mask claude "$root" "$root"');
    expect(source).not.toContain("--dangerously-skip-permissions");
    expect(source).not.toMatch(
      /--tools\s+"[^"\n]*(?:Bash|Edit|Write|Task|Agent)/,
    );
  });

  test("keeps a non-bypass defense-in-depth profile", async () => {
    const settings = JSON.parse(await readFile(profile, "utf8")) as {
      permissions: { defaultMode: string; deny: string[] };
    };

    expect(settings.permissions.defaultMode).not.toBe("bypassPermissions");
    expect(settings.permissions.deny).toEqual(
      expect.arrayContaining([
        "Edit(**)",
        "Write(**)",
        "Read(**/.env*)",
        "Task(**)",
        "Agent(**)",
      ]),
    );
  });
});

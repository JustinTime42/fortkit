import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

const root = fileURLToPath(new URL("..", import.meta.url));
const launcher = `${root}templates/fort/scripts/researcher.sh`;
const profile = `${root}templates/fort/profiles/researcher-settings.json`;
const probe = `${root}templates/fort/scripts/probe-researcher-boundaries.sh`;

function shell(source: string) {
  return new Promise<{ stdout: string }>((resolve, reject) => {
    execFile("bash", ["-c", source], (error, stdout, stderr) => {
      if (error) reject(new Error(stderr));
      else resolve({ stdout });
    });
  });
}

describe("Researcher template boundary", () => {
  test("uses only the read/search tools and its isolated settings profile", async () => {
    const source = await readFile(launcher, "utf8");

    expect(source).toContain('--tools "WebSearch,WebFetch,Read,Grep,Glob"');
    expect(source).toContain('--setting-sources ""');
    expect(source).toContain("researcher-settings.json");
    expect(source).toContain(
      'build_mask claude "$root" --env-root "$root-worktrees" "$root"',
    );
    expect(source).toContain("RESEARCH-COMPLETE");
    expect(source).toContain('[ "$rc" -eq 0 ]');
    expect(source).toContain(
      "grep -qE '^[[:space:]]*RESEARCH-COMPLETE[[:space:]]*$' \"$log\"",
    );
    expect(source).toContain('\\"handoff_recorded\\"');
    expect(source).toContain("exit 65");
    expect(source).not.toContain("--dangerously-skip-permissions");
    expect(source).not.toMatch(
      /--tools\s+"[^"\n]*(?:Bash|Edit|Write|Task|Agent)/,
    );
  });

  test("keeps a non-bypass defense-in-depth profile", async () => {
    const settings = JSON.parse(await readFile(profile, "utf8")) as {
      permissions: { defaultMode: string; allow: string[]; deny: string[] };
    };

    expect(settings.permissions.defaultMode).not.toBe("bypassPermissions");
    expect(settings.permissions.allow).toEqual(
      expect.arrayContaining(["WebSearch", "WebFetch"]),
    );
    expect(settings.permissions.deny).toEqual(
      expect.arrayContaining(["Edit(**)", "Read(**/.env*)"]),
    );
    expect(settings.permissions.deny).not.toContain("Write(**)");
    expect(settings.permissions.deny).not.toContain("NotebookEdit(**)");
    expect(settings.permissions.deny).not.toContain("Task(**)");
    expect(settings.permissions.deny).not.toContain("Agent(**)");
    expect(settings.permissions.deny).not.toContain(
      "Read(/{{REPO_PATH}}/.env*)",
    );
    expect(settings.permissions.deny).not.toContain(
      "Read(/{{REPO_PATH}}/**/.env*)",
    );
    expect(settings.permissions.deny).not.toContain(
      "Read(/{{REPO_PATH}}-worktrees/**/.env*)",
    );
  });
});

describe("Researcher boundary probe parsing helpers", () => {
  test("extracts only an exact launcher --tools value", async () => {
    const { stdout } = await shell(
      `source ${JSON.stringify(probe)}; launcher_tools ${JSON.stringify(launcher)}`,
    );
    expect(stdout.trim()).toBe("WebSearch,WebFetch,Read,Grep,Glob");
  });

  test("recognizes required flags and their empty values", async () => {
    const { stdout } = await shell(
      `source ${JSON.stringify(probe)}; launcher_has_flag ${JSON.stringify(launcher)} --strict-mcp-config; printf '%s|' "$?"; launcher_flag_value ${JSON.stringify(launcher)} --setting-sources`,
    );
    expect(stdout).toBe("0|\n");
  });

  test("parses profile policy as JSON", async () => {
    for (const check of ["default-safe", "edit-deny", "web-only"]) {
      await expect(
        shell(
          `source ${JSON.stringify(probe)}; profile_check ${JSON.stringify(profile)} ${check}`,
        ),
      ).resolves.toBeDefined();
    }
  });
});

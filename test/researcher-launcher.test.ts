import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
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
    // Memory-surface coupling guard (fortkit-xgul.3, restoring fortkit-vhk.14
    // finding 1 in its end-state form). The template prompt must name the
    // facts-ledger surface, never the retired flat pointer. This couples the
    // template repoint (A3) to bin/fort-init's ledger founding (A2): if either
    // is reverted to fort/remember.md this goes red, which is the mechanism
    // that stops vhk.9's silent-revert class from recurring.
    expect(source).toContain("fort/memory/current.md");
    expect(source).not.toContain("fort/remember.md");
    expect(source).toContain(
      'build_mask claude "$root" --env-root "$root-worktrees" "$root"',
    );
    expect(source).toContain("RESEARCH-COMPLETE");
    expect(source).toContain("-a researcher -s researcher");
    expect(source).toContain("--actor researcher");
    expect(source).not.toMatch(/-a (?!researcher\b)/);
    expect(source).not.toMatch(/--actor (?!researcher\b)/);
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

  test("accepts the real launcher's required positive controls", async () => {
    for (const check of [
      `exact_tools ${JSON.stringify(launcher)}`,
      `no_forbidden_tool ${JSON.stringify(launcher)}`,
      `empty_setting_sources ${JSON.stringify(launcher)}`,
    ]) {
      await expect(
        shell(`source ${JSON.stringify(probe)}; ${check}`),
      ).resolves.toBeDefined();
    }
  });

  test("allows skipped assertions normally but rejects them in strict mode", async () => {
    await expect(
      shell(
        `source ${JSON.stringify(probe)}; fail=0; skip=2; strict=0; probe_exit_status`,
      ),
    ).resolves.toBeDefined();
    await expect(
      shell(
        `source ${JSON.stringify(probe)}; fail=0; skip=2; strict=1; probe_exit_status`,
      ),
    ).rejects.toThrow();
  });

  test("rejects unsafe launcher variants", async () => {
    const fixture = await mkdtemp(join(tmpdir(), "researcher-launcher-"));
    try {
      const badTools = join(fixture, "bad-tools.sh");
      const missingSources = join(fixture, "missing-sources.sh");
      await writeFile(badTools, '--tools "WebSearch,Bash" \\\n');
      await writeFile(missingSources, "--strict-mcp-config \\\n");

      await expect(
        shell(
          `source ${JSON.stringify(probe)}; exact_tools ${JSON.stringify(badTools)}`,
        ),
      ).rejects.toThrow();
      await expect(
        shell(
          `source ${JSON.stringify(probe)}; no_forbidden_tool ${JSON.stringify(badTools)}`,
        ),
      ).rejects.toThrow();
      await expect(
        shell(
          `source ${JSON.stringify(probe)}; empty_setting_sources ${JSON.stringify(missingSources)}`,
        ),
      ).rejects.toThrow();
    } finally {
      await rm(fixture, { recursive: true, force: true });
    }
  });

  test("rejects unsafe profile variants", async () => {
    const fixture = await mkdtemp(join(tmpdir(), "researcher-profile-"));
    try {
      const bypass = join(fixture, "bypass.json");
      const extraAllow = join(fixture, "extra-allow.json");
      await writeFile(
        bypass,
        JSON.stringify({
          permissions: {
            defaultMode: "bypassPermissions",
            allow: ["WebSearch", "WebFetch"],
            deny: ["Edit(**)"],
          },
        }),
      );
      await writeFile(
        extraAllow,
        JSON.stringify({
          permissions: {
            defaultMode: "default",
            allow: ["WebSearch", "WebFetch", "Read"],
            deny: ["Edit(**)"],
          },
        }),
      );

      await expect(
        shell(
          `source ${JSON.stringify(probe)}; profile_check ${JSON.stringify(bypass)} default-safe`,
        ),
      ).rejects.toThrow();
      await expect(
        shell(
          `source ${JSON.stringify(probe)}; profile_check ${JSON.stringify(extraAllow)} web-only`,
        ),
      ).rejects.toThrow();
    } finally {
      await rm(fixture, { recursive: true, force: true });
    }
  });
});

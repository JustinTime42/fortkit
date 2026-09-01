import { execFile, spawnSync } from "node:child_process";
import { promisify } from "node:util";

type SpawnFailure = {
  code?: unknown;
  message?: unknown;
};

const spawnPermissionCodes = new Set(["EPERM", "EACCES", "ERR_ACCESS_DENIED"]);
const run = promisify(execFile);

/**
 * Returns a visible skip reason only for the namespace's known spawn denial.
 * Every other launch failure must remain a test failure.
 */
export function spawnPermissionSkipReason(error: SpawnFailure): string | null {
  if (typeof error.code !== "string" || !spawnPermissionCodes.has(error.code)) {
    return null;
  }

  const detail =
    typeof error.message === "string" && error.message !== ""
      ? `: ${error.message}`
      : "";
  return `shell spawning is unavailable (${error.code})${detail}`;
}

/**
 * Detect the Forge mask before registering shell-spawning tests. An unexpected
 * error is deliberately rethrown so it cannot be reported as a skip.
 */
export function commandSpawnSkipReason(
  command: string,
  arguments_: string[],
): string | null {
  const result = spawnSync(command, arguments_, { stdio: "ignore" });
  if (result.error === undefined) return null;

  const reason = spawnPermissionSkipReason(result.error as SpawnFailure);
  if (reason !== null) return reason;
  throw result.error;
}

export function shellSpawnSkipReason(): string | null {
  return commandSpawnSkipReason("sh", ["-c", "exit 0"]);
}

export function nodeSpawnSkipReason(): string | null {
  return commandSpawnSkipReason("node", ["--version"]);
}

/**
 * The mask can allow the immediate child while denying its child. This marker
 * is written only after Node starts through a shell, matching the affected
 * tests' topology. A non-empty unexpected diagnostic remains a failure.
 */
export async function nestedShellSpawnSkipReason(): Promise<string | null> {
  try {
    const { stderr } = await run("sh", [
      "-c",
      "node -e 'process.stderr.write(\"fortkit-spawn-control\\n\")'",
    ]);
    if (stderr.includes("fortkit-spawn-control")) return null;
    if (stderr !== "") {
      throw new Error(`nested shell spawn control failed: ${stderr}`);
    }
    return "shell spawning is unavailable (nested spawn control produced no marker)";
  } catch (error) {
    const reason = spawnPermissionSkipReason(error as SpawnFailure);
    if (reason !== null) return reason;
    throw error;
  }
}

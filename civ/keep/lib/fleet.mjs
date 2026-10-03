import fs from "node:fs";
import path from "node:path";

const liveStates = new Set(["in-hand", "running", "launching", "orphaned"]);
function launchGraceMs(fileSystem, keepRoot) {
  const config = keepRoot
    ? read(path.join(keepRoot, "fort/scripts/fleet.conf"), fileSystem)
    : null;
  const seconds = Number(config?.match(/^FLEET_LAUNCH_GRACE=(\d+)$/m)?.[1]);
  return Number.isFinite(seconds) ? seconds * 1_000 : 120_000;
}

function read(file, fileSystem) {
  try {
    return fileSystem.readFileSync(file, "utf8").trim();
  } catch {
    return null;
  }
}

function tail(file, fileSystem, lines = 10) {
  const text = read(file, fileSystem);
  return text ? text.split("\n").slice(-lines) : [];
}

function pidIsAlive(pid) {
  if (!/^\d+$/.test(pid ?? "")) return false;
  try {
    process.kill(Number(pid), 0);
    return true;
  } catch {
    return false;
  }
}

function workerState(
  directory,
  stored,
  currentRun,
  fileSystem,
  now,
  isPidAlive,
  keepRoot,
) {
  if (stored) {
    const [token, storedRun] = stored.split("|");
    return token === "in-hand" && storedRun !== currentRun ? "orphaned" : token;
  }
  if (fileSystem.existsSync(path.join(directory, "done"))) return "settled";
  if (fileSystem.existsSync(path.join(directory, "exit"))) return "finished";
  if (isPidAlive(read(path.join(directory, "pid"), fileSystem)))
    return "running";
  try {
    const age =
      now() - fileSystem.statSync(path.join(directory, "started")).mtimeMs;
    if (age < launchGraceMs(fileSystem, keepRoot)) return "launching";
  } catch {
    // A missing started file is the same orphaned branch as fleet.sh.
  }
  return "orphaned";
}

function readWorker(
  root,
  id,
  currentRun,
  fileSystem,
  now,
  isPidAlive,
  keepRoot,
) {
  const directory = path.join(root, "workers", id);
  const stored = read(path.join(directory, "state"), fileSystem);
  const [, stateRun, reason] = stored?.split("|") ?? [];
  const run = read(path.join(directory, "run"), fileSystem) ?? stateRun ?? null;
  return {
    id,
    state: workerState(
      directory,
      stored,
      currentRun,
      fileSystem,
      now,
      isPidAlive,
      keepRoot,
    ),
    run,
    reason: reason ?? null,
    bead: read(path.join(directory, "bead"), fileSystem),
    started: read(path.join(directory, "started"), fileSystem),
    pid: read(path.join(directory, "pid"), fileSystem),
    verdict: read(path.join(directory, "verdict"), fileSystem),
    log: tail(path.join(root, "logs", `run-${run}.log`), fileSystem),
  };
}

export function parseCeiling(lines) {
  const line = lines.at(-1) ?? "";
  const run = line.match(/run=([^\s]+)/)?.[1];
  const currentRun = (value) =>
    value.match(/(?:^|\s)run=([^\s]+)/)?.[1] === run;
  const launch = lines
    .findLast(
      (value) => currentRun(value) && /launch\s+(\d+)\/(\d+)/.test(value),
    )
    ?.match(/launch\s+(\d+)\/(\d+)/);
  const start = lines
    .findLast((value) => currentRun(value) && /start\b/.test(value))
    ?.match(/hard_stop=(\d+)/);
  const hardStop = launch?.[2] ?? start?.[1];
  return run && hardStop
    ? {
        run,
        launches: Number(launch?.[1] ?? 0),
        hardStop: Number(hardStop),
        raw: line,
      }
    : null;
}

export function readFleet(root, fileSystem = fs, options = {}) {
  const now = options.now ?? Date.now;
  const isPidAlive = options.pidIsAlive ?? pidIsAlive;
  const keepRoot = options.keepRoot;
  const workersDirectory = path.join(root, "workers");
  const workerIds = fileSystem.existsSync(workersDirectory)
    ? fileSystem.readdirSync(workersDirectory)
    : [];
  const ceilingLines = tail(path.join(root, "ceiling.log"), fileSystem);
  const ceiling = parseCeiling(ceilingLines);
  const allWorkers = workerIds.map((id) =>
    readWorker(root, id, ceiling?.run, fileSystem, now, isPidAlive, keepRoot),
  );
  const logs = allWorkers.flatMap((worker) => worker.log);
  return {
    halted: fileSystem.existsSync(path.join(root, "HALT")),
    workers: allWorkers.filter((worker) => liveStates.has(worker.state)),
    ceiling,
    streak: read(path.join(root, "supervisor.streak"), fileSystem),
    verifySummary:
      logs.findLast((line) => /Passed!|verify\.pass/i.test(line)) ?? null,
  };
}

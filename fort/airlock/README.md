# The airlock

Host-run operations a seat may REQUEST. The host runs one only on the
Overseer's approval, or, for an operation the table declares `auto_run`
(below), without one. The
table of operations is `operations.json` (kernel read-only to every seat since
`Proofdelve ForgeOs-72ot`); requests land in `requests/`, results in `results/`. The
verbs live in `fort/scripts/airlock.sh` (`request`, `approve`, `run`, `status`).

## Parameters, and seat-requestable host operations (`Proofdelve ForgeOs-emshb`, Regent docket 2026-10-22, gate 6)

Until 2026-10-23 every operation was parameterless: `request --param k=v` stored
pairs nothing read back (`Proofdelve ForgeOs-15k.3`, recorded 2026-09-17). Now an operation
may declare, in `operations.json` and ONLY there (a request file is never read
for any of these):

| key | meaning |
|---|---|
| `params` | `{name: pattern}`. Each declared param's value (absent reads as `""`) must match its pattern **whole** (`\A(?:pattern)\z`; jq's `^...$` lets a trailing newline through). An undeclared param, a non-string value, or one over 256 characters is refused. `request` refuses before writing anything; `run` judges the snapshot again and records a refusal as a result with **exit 64**, before any script runs, so it is never selected again. |
| `args` | how params reach the script, as an **argv array**: literals, `"$name"` (that value as one argument, omitted when empty), and `{"when": name, "equals": value?, "args": [...]}` groups. No value is ever interpolated into a shell string (standing order 14). |
| `path_params` | params naming a file: each non-empty one must `realpath` to a regular file **inside** the run directory, or exit 64. |
| `runs_from: "bead-worktree"` | cwd is the worktree of the bead the `target` param names (`$root-worktrees/<suffix>`; `main` or a 40-hex sha run from `$root`); a missing worktree is exit 65. **The script is still main's copy**: a worktree is seat-writable. |
| `auto_run` | the host runner executes the request with **no approval line**. Honoured only beside `requires_approval: false`; `requires_approval: true` always wins, so `deploy-staging` can never be auto-run. Judged on the snapshot: a request swapped after selection into an operation that is neither approved nor auto_run is skipped and left for a person. |
| `result_url` | a regex with a named group `url`; on exit 0 the first match in the log that is a plain `http://localhost:<port>` or `http://127.0.0.1:<port>` URL is recorded as the result's `url`, and the Civ Keep Airlock page shows it as a link (checking it again: `results/` is seat-writable). |

The operations this added:

- **`host-test`** (`scripts/host-test.sh`): `target` (main or a bead id),
  `filter` (a `dotnet test` filter), optional `mutate` (a `.patch`/`.diff` path
  inside the bead's worktree; host-test refuses a dirty tree, so put the patch
  where git ignores it, e.g. `fort/airlock/requests/<name>.patch` in that
  worktree). `auto_run`: it runs without a click, one at a time, and its log in
  `results/<id>.log` is readable from the Mayor's mask. Request it:

      fort/scripts/airlock.sh request host-test --reason "red arm for X" \
        --param target=fortkit-<bead> --param 'filter=FullyQualifiedName~Foo'

  **It is not read-only.** It builds and tests the named worktree (and the
  patch) on the host, unmasked, with Docker. The fleet's host verify already
  runs every Forge branch that way, and the Mayor can write main and every
  worktree, so this is a faster trigger, not a new capability. The Overseer
  chose to build it as approved, on that description (comment on
  `Proofdelve ForgeOs-emshb`, 2026-10-23).
- **`preview`** (`scripts/preview.sh`): `target`, `keep_data` (`true` keeps the
  preview database). **Needs his Keep Approve.** The result carries `url`, shown
  on the Airlock page. The preview's servers outlive the run on purpose:
  `airlock.sh` closes the run lock (fd 8) for the script, and the runner service
  is `KillMode=process` (measured: under the default control-group a detached
  child is killed at unit exit). The same setting leaves a host-test's dotnet
  build-server processes running after the unit stops (seen on the first live
  run, 2026-10-23); they exit on their own idle timeouts, as they do after any
  `dotnet build` at the terminal.
- **`preview-stop`** (`scripts/preview.sh stop`): no params, `auto_run`, no click.

The runner's path unit also fires on a change in `requests/` (`PathChanged=`), so
an auto_run request does not wait for the ten-minute timer. `requests/` is
seat-writable, so a seat can start the runner; that buys nothing, because the
runner executes only store-approved requests and auto_run operations.

## One click, and what it builds (`Proofdelve ForgeOs-mbv54`, Regent edict 2026-10-15)

A staging deploy costs the Overseer one click and no typed command:

1. The Mayor asks him in prose (what, why, which commit), then
   `fort/scripts/airlock.sh request deploy-staging --reason "..."`. The request
   records `commit`, HEAD at request time.
2. He reads it on the Civ Keep's Airlock page, which shows the commit the run
   will build, and clicks Approve. That writes one line to
   `~/.local/state/civ-keep/airlock-approvals.jsonl`, read-only in every seat
   mask.
3. `manyhalls-airlock-runner.path` (fort/systemd/) sees the store change and
   starts `fort/scripts/airlock-runner.sh`, which loops `airlock.sh run` with
   no id until nothing approved is left. A ten-minute timer catches an approval
   clicked while a run was already going (a path unit drops that event).

**What runs is the commit he approved, not main's HEAD.** `deploy-staging`
declares `"runs_from": "pinned-commit"`: `run` cuts a temporary detached
worktree of the request's `commit` under `~/.local/share/airlock/fortkit/<id>`
(no seat can write there), symlinks the declared `env_files` from the root
(never copies them), runs the script there, and removes the worktree. A pin
that is not a full sha, not in the repository, or not on main is REFUSED and
recorded as a result with exit 65, so it is never selected again. The result
file and the `deploy` event name the commit that ran.

**What the runner never runs:** anything without a store line. A seat writing
`"status": "approved"` into its own request gets nothing, and `feedback-scan`
(`requires_approval: false`) is never approved, so it is never auto-run; a
scan is still a person's `airlock.sh run <id>`. `scripts/airlock-harness.sh`
pins both.

## Closed gaps

- Approval status lived in the seat-writable request file (`Proofdelve ForgeOs-72ot.1`):
  closed 2026-10-06, approval lives in the Overseer store.
- A successful `run` emitted no `deploy` event (`Proofdelve ForgeOs-x6hq`): closed; an
  operation's `emits` block is announced on exit 0.

## Known gaps, each with its bead (historical list as of 2026-09-17)

- Approval status lives in the seat-writable request file (`Proofdelve ForgeOs-72ot.1`):
  a seat can write `"status": "approved"` into its own request. Design work
  for a Regent sitting; the probe the bead demands has not been run.
- A successful `run` emits no `deploy` event (`Proofdelve ForgeOs-x6hq`, five instances);
  the Mayor reconstructs one from the result file.

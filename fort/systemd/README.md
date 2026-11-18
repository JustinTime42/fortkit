# Manyhalls fleet — systemd user units

> **Manyhalls, 2026-11-18 (Regent sitting `fortkit-ttpk`).** NONE of these units is
> installed or enabled. They were renamed from the fort this machinery came from and
> are kept here as drafts. Enabling any of them is the Overseer's decision, and this
> machine also runs Proofdelve's fleet, so three rules from the re-founding docket
> come first: (S1) the two fleets' memory gates each see only their own workers, so
> Manyhalls's fleet runs only while Proofdelve's is idle or with `FLEET_FORGE_MAX=1`;
> (S2) the model quota is shared, so Manyhalls's hard stop starts low; (S3) Docker, the
> Civ Keep and the loop watchdog are shared and keyed by fort. `fort/scripts/fleet.conf`
> ships `FLEET_ENABLED=0`. The nightly verify here is drafted for 04:30, an hour after
> Proofdelve's, and Manyhalls's verifier needs no Docker whatever the text below says.

The **supervisor** pair (Proofdelve ForgeOs-dx34.4) starts fleet runs; the **scratch
reaper** pair (Proofdelve ForgeOs-nv0j) cleans up after them; the **nightly verify** pair
(Proofdelve ForgeOs-s1reg) runs one full, verify of main at 04:30 and
writes the halt file on a red main -- the backstop for tiered host verifies and
reused post-merge passes. (The airlock runner's three files are described in
`fort/airlock/README.md`.) Both were
drafted under Regent edicts with the Overseer's gate-6 signature, and both do
nothing where they live in the repo: the copies in `~/.config/systemd/user/`
are what run.

## The supervisor (Proofdelve ForgeOs-dx34.4)

Two files, drafted and installed under the Regent edict of 2026-09-10 with the
Overseer's gate-6 signature recorded on the bead. **They do nothing where they
live in the repo**; the copies in `~/.config/systemd/user/` are what run, and
the install step below asserts the two are byte-identical. Pattern: the
capital's `civ/systemd/` (herald, consolidate).

`manyhalls-fleet-supervisor.timer` fires `manyhalls-fleet-supervisor.service`
every two minutes on the wall clock; the service runs
`fort/scripts/fleet-supervisor.sh` once. That file's header is the design. In
one line: halt file → nothing; a run live → exit 75, silent but **counted** in
`~/.local/state/manyhalls-fleet/supervisor.streak`; nothing fleet-safe →
nothing; otherwise start a run as its own transient unit
`manyhalls-fleet-run-<id>` and exit at once.

## Install (a person, unmasked)

```bash
cp ~/dev/fortkit/fort/systemd/manyhalls-fleet-supervisor.{service,timer} ~/.config/systemd/user/
cmp ~/dev/fortkit/fort/systemd/manyhalls-fleet-supervisor.service ~/.config/systemd/user/manyhalls-fleet-supervisor.service
cmp ~/dev/fortkit/fort/systemd/manyhalls-fleet-supervisor.timer   ~/.config/systemd/user/manyhalls-fleet-supervisor.timer
systemctl --user daemon-reload
systemctl --user enable --now manyhalls-fleet-supervisor.timer   # THE ACT: runs now begin without a person
```

`loginctl enable-linger justin` is already set (measured 2026-08-31 for the
capital's units), so the timer fires with no session open.

## Stop, and what each stop does

**The `systemctl` rows are HOST-ONLY** (a person at the Overseer's terminal).
`Bash(systemctl*)` and `Bash(systemd-run*)` are denied to every Claude seat
(Proofdelve ForgeOs-4778), read-only forms included, so a masked seat cannot run them; that
is the deny working, not a fault. The Mayor's own drain is the `touch ... HALT`
row, which is a plain file write under `~/.local/state` and works from the mask.

| you want | do | effect |
|---|---|---|
| no run to START | `touch ~/.local/state/manyhalls-fleet/HALT` | every firing is a no-op, streak untouched; a live run also reads it between passes and drains |
| no run to start, timer off | `systemctl --user disable --now manyhalls-fleet-supervisor.timer` | reversible with `enable --now` |
| a live run to STOP | `systemctl --user stop manyhalls-fleet-run-<id>` | SIGTERM to fleet.sh alone (KillMode=process): the drain-then-stop path, exit 143, detached Forges untouched — exactly a hand-launched run under `kill -TERM` |

`systemctl --user list-units 'manyhalls-fleet-run-*'` (HOST-ONLY) names the
live run. `journalctl --user -u manyhalls-fleet-run-<id>` is its journal — and
`journalctl` is NOT denied, so it works from the mask (measured 2026-09-11); its
narrative log is `$FLEET_STATE/logs/run-<run-id>.log` as for any run.

## Verify — measured, never assumed

```bash
# HOST-ONLY (a person): systemctl is denied to every Claude seat (Proofdelve ForgeOs-4778)
systemctl --user list-timers manyhalls-fleet-supervisor.timer     # NEXT within two minutes
fort/scripts/fleet-supervisor.sh --status                         # the streak record — HOST-ONLY: --status REFUSES under FORT_MASKED (measured 2026-09-11)

# FROM A MASKED SEAT (the Mayor at session start): read the files, not the units
cat "${FLEET_STATE:-$HOME/.local/state/manyhalls-fleet}/supervisor.streak"   # what --status prints, read directly
test -e "${FLEET_STATE:-$HOME/.local/state/manyhalls-fleet}/HALT" && echo HALT present || echo HALT absent
journalctl --user -u manyhalls-fleet-supervisor.service -e        # NOT denied; works from the mask — Starting/Finished per firing, a 64 shows here
scripts/supervisor-harness.sh                                      # 17 cases, three generated controls; runs in the verifier
```

A firing is **quiet**: no stdout, no event, on every outcome but a start (one
stderr line and one `fleet.autostart` event) and a refusal (one stderr line,
exit 64, and the unit shows in `systemctl --user --failed`). Exit 75 is
declared success in the unit (`SuccessExitStatus=75`) so a live run does not
fill `--failed`. The journal's own Starting/Finished lines are systemd's, and
they are the only proof the timer is alive.

## Reading the stream: shapes that are not defects

- **`fleet.autostart` with no `fleet.begun` after it.** The supervisor
  probed the lock free and asked for a run, and fleet.sh then refused at its
  own preflight or lock. Two known causes: a hand-launched run was in its
  preflight at the moment the timer fired (the probe and fleet.sh's lock are
  separated by that preflight; the second unit exits 75 and the hand run
  proceeds), or fleet.sh refused on something the supervisor does not check
  (a non-main branch, a missing merge slot). One is harmless; a run of them
  every two minutes is fleet.sh refusing for a reason the journal of the
  `manyhalls-fleet-run-<id>` unit names. (the Warden, round one, findings 2 and 4.)
- **`fleet.autostart` + `fleet.begun` + `fleet.ended` (0 launches) every two
  minutes.** A bead is in `bd ready --label fleet-safe` and the dispatcher
  refuses it; the supervisor selects, fleet.sh decides, and the disagreement
  is visible here rather than silent. The fix is on the bead
  (`Proofdelve ForgeOs-dx34.4` finding 3 is the back-off follow-up).
- **Nothing at all, with beads ready.** The halt file is present, or
  `FLEET_ENABLED` is not `1` in `fort/scripts/fleet.conf`; both are "nothing
  to do" and both are silent by design. `fleet-supervisor.sh --status`, the
  halt file and the config answer it in three commands.

## Two facts a reader must have (both measured 2026-09-10, both on the bead)

1. **The halt file is now a launch control.** Before the supervisor, removing
   it did nothing until a person launched; now its removal starts the fleet
   within two minutes. And `~/.local/state` is an rw grant in
   `seat-sandbox.sh`, so a **masked Mayor can remove it**. Stated to the
   Overseer before his signature; the compensating control is prose in the
   Mayor's own instructions until the lib changes.
2. **The mask does not stop `systemd-run`.** The session bus is reachable
   inside every seat mask, so a masked seat can start any command unmasked
   through the user manager — `fortkit-y7no`, P0, the capital's lib. The
   supervisor adds no capability to that (fleet.sh could always be started
   that way) and refuses under `FORT_MASKED` like fleet.sh does; the marker is
   the control until the bus is masked.

## What is NOT here

Wiring the streak into `status.sh` (criterion 7 says so in terms). A
`Persistent=` timer (nothing to catch up on). Any threshold or paging on the
streak: every threshold available from outside a run was refuted over 27 runs
(`Proofdelve ForgeOs-dx34.4` design field), and wedge detection lives inside fleet.sh
(`Proofdelve ForgeOs-dx34.9`), which halts and writes the halt file — which is why a
stalled fleet is never restarted into the same wedge.

## The scratch reaper (Proofdelve ForgeOs-nv0j; incident Proofdelve ForgeOs-7gag; Proofdelve ForgeOs-mpaw)

`manyhalls-scratch-reaper.timer` fires `manyhalls-scratch-reaper.service`
hourly (`Persistent=true`: a missed hour catches up on wake); the service runs
`fort/scripts/scratch-reaper.sh` once. That file's header is the design. In one
line: remove a Warden scratch copy under `~/.local/share/manyhalls/warden/<sfx>` (or
the pre-2026-09-12 `/tmp/warden-<sfx>`) when it is **older than two hours AND
nobody holds its review lock**; remove a bead worktree that
`scripts/stranded-sweep.sh --reapable` lists (merged into main, bead closed)
when its tree is **clean, its branch is re-checked as an ancestor of main, AND no
launcher holds its `.forge.lock`**, and delete
its branch in the same breath (a worktree gone with its branch left behind is
the `forge.sh` exit-255 shape measured 2026-09-09).

Why it exists: on 2026-09-12 at 17:03 about thirty Warden scratch copies —
each a whole repo with `bin/obj` and `web/node_modules` after its builds — hit
the 12764M user quota on the RAM-backed `/tmp`, and in one second a Warden died
mid-record, the host verifier went RED, and two Forges exited 1 (Proofdelve ForgeOs-7gag).
`warden.sh` now removes its own copy on exit and keeps scratch on disk under the
XDG **data** dir, not the cache dir: `~/.cache` is an rw grant in every seat
mask, `~/.local/share` is not, so a seat's own copy is writable (bound by
`--rw-tmp`) while sibling copies and the record files are read-only to it
(measured 2026-09-12, the Warden's round-one finding 2). The reaper is for what a
SIGKILL leaves, and for the worktree backlog.

**Sweep C and the `/tmp` alarm** (Proofdelve ForgeOs-jfqu4.8 with Proofdelve ForgeOs-lmgue, Regent
docket 2026-10-22 item B). The same hourly firing now also prunes the host
`/tmp`: `forge-<sfx>.log` and `verify-fail-*.log` older than seven days (kept
while a launcher holds that bead's `.forge.lock`, or while today's or
yesterday's event stream cites the file), and `/tmp/node-compile-cache` when it
is over 1 GiB and no process has a file in it open. It measures this user's
usage of the `/tmp` quota and emits one `incident` per band (80, 90, 95 percent)
per day; `fleet.sh` asks for that check at the top of every pass with
`scratch-reaper.sh --tmp-check`, so a fill is reported before it halts a
verify. The cache itself is no longer written by fleet, Forge, nightly or
verifier runs (`NODE_DISABLE_COMPILE_CACHE=1`, the `node_compile_cache` block in
those four launchers). This replaces the Overseer's interim crontab line, which
he can now remove.

### Install (a person, unmasked)

```bash
cp ~/dev/fortkit/fort/systemd/manyhalls-scratch-reaper.{service,timer} ~/.config/systemd/user/
cmp ~/dev/fortkit/fort/systemd/manyhalls-scratch-reaper.service ~/.config/systemd/user/manyhalls-scratch-reaper.service
cmp ~/dev/fortkit/fort/systemd/manyhalls-scratch-reaper.timer   ~/.config/systemd/user/manyhalls-scratch-reaper.timer
systemctl --user daemon-reload
systemctl --user enable --now manyhalls-scratch-reaper.timer
```

### Verify — measured, never assumed

```bash
# HOST-ONLY
systemctl --user list-timers manyhalls-scratch-reaper.timer      # NEXT within the hour
fort/scripts/scratch-reaper.sh --dry-run                          # what the next firing WOULD remove, removing nothing
journalctl --user -u manyhalls-scratch-reaper.service -e         # one 'scratch reaper: N removed, ...' line per firing
scripts/scratch-reaper-harness.sh                                 # 24 cases over fixture roots; refuses (exit 3) without the reaper

# FROM A MASKED SEAT: the script itself REFUSES under FORT_MASKED (exit 64); read instead
ls -la "${XDG_DATA_HOME:-$HOME/.local/share}/manyhalls/warden/"      # scratch dirs are copies in flight (or SIGKILL leftovers under 2h); files are records
journalctl --user -u manyhalls-scratch-reaper.service -e         # journalctl is not denied (measured 2026-09-11)
```

A firing is **quiet when there is nothing to do**: one stderr line for the
journal, no event. A firing that removed or FAILED to remove something emits
one `progress` event under actor `fleet` carrying the counts. Exit 1 (a
removal FAILED, the thing is still there) and exit 64 (the worktree list could
not be obtained) put the unit in `systemctl --user --failed`, deliberately: a
reaper that cannot reap is a disk that keeps filling.

What it never touches: the fleet's state directory, the halt file, bd, the
small files beside a scratch copy (`<sfx>.log`, `.log.record`,
`.log.result.json`, `.log.err`, `.log.settings.json`, `.lock`, `.lock.info` —
the review's record, kilobytes), a dirty worktree, a worktree whose bead is
open or whose branch is ahead of main, or anything a lock is held on.

## The airlock runner (Proofdelve ForgeOs-mbv54)

Three files: `manyhalls-airlock-runner.path`, `.service`, `.timer`. Drafted
under the Regent edict of 2026-10-15 with the Overseer present. They make a
staging deploy cost him one click in the Civ Keep: the path unit fires on any
write to `~/.local/state/civ-keep/airlock-approvals.jsonl`, the service runs
`fort/scripts/airlock-runner.sh`, which loops `fort/scripts/airlock.sh run` (no
id) until nothing approved is left. Only requests approved IN THE STORE run, and
the store is read-only in every seat mask, so a seat cannot start a run by
anything it writes. The timer (every ten minutes) is a safety net: measured on
this host, a path unit DROPS an append made while its service is running, so an
approval clicked mid-deploy would otherwise wait for the next click.
`fort/airlock/README.md` describes what a run builds (the request's pinned
commit, from a temporary worktree).

### Install (a person, unmasked)

```bash
cp ~/dev/fortkit/fort/systemd/manyhalls-airlock-runner.{path,service,timer} ~/.config/systemd/user/
for u in path service timer; do cmp ~/dev/fortkit/fort/systemd/manyhalls-airlock-runner.$u ~/.config/systemd/user/manyhalls-airlock-runner.$u; done
systemctl --user daemon-reload
systemctl --user enable --now manyhalls-airlock-runner.path manyhalls-airlock-runner.timer   # THE ACT: an Approve click now runs the request
```

### Stop

| you want | do |
|---|---|
| clicks stop running things | `systemctl --user disable --now manyhalls-airlock-runner.path manyhalls-airlock-runner.timer` (HOST-ONLY) |
| a live deploy to stop | `systemctl --user stop manyhalls-airlock-runner.service` (HOST-ONLY); the approval was consumed before the run started, so it will not re-run |

### Verify

```bash
# HOST-ONLY
systemctl --user list-timers manyhalls-airlock-runner.timer
systemctl --user status manyhalls-airlock-runner.path            # active (waiting)
journalctl --user -u manyhalls-airlock-runner.service -e         # per firing: the run's own lines, or "nothing approved to run"
scripts/airlock-harness.sh                                         # cases 12-17 cover the pin and the runner
```

A firing with nothing approved prints `airlock: nothing approved to run` and
exits 0. Exit 64 means it was started inside a seat mask; any other nonzero
exit is `airlock.sh run` dying (the line above it in the journal says why) and
leaves the unit in `--failed`.

## The nightly verify (Proofdelve ForgeOs-s1reg)

Drafted and installed under the Regent edict of 2026-10-19 (docket
Proofdelve ForgeOs-x7ojh), the Overseer's approval of the design recorded on
Proofdelve ForgeOs-s1reg. `manyhalls-nightly-verify.timer` fires
`manyhalls-nightly-verify.service` at 04:30; the service runs
`fort/scripts/nightly-verify.sh` once, whose header is the design. GREEN removes
its worktree; RED writes `~/.local/state/manyhalls-fleet/HALT`, keeps the
worktree and emits an incident.

```bash
cp ~/dev/fortkit/fort/systemd/manyhalls-nightly-verify.{service,timer} ~/.config/systemd/user/
cmp ~/dev/fortkit/fort/systemd/manyhalls-nightly-verify.service ~/.config/systemd/user/manyhalls-nightly-verify.service
cmp ~/dev/fortkit/fort/systemd/manyhalls-nightly-verify.timer   ~/.config/systemd/user/manyhalls-nightly-verify.timer
systemctl --user daemon-reload
systemctl --user enable --now manyhalls-nightly-verify.timer
```

If the timer is ever disabled, set `FLEET_VERIFY_TIERS=off` and
`FLEET_VERIFY_REUSE=off` in `fort/scripts/fleet.conf` as well: without the
nightly run, tiers and reuse have no backstop.

## The loop watchdog (Proofdelve ForgeOs-dycc9, Proofdelve ForgeOs-76uob.6)

Two files, drafted under the Regent sitting of 2026-11-16 with the Overseer
present. `manyhalls-loop-watchdog.timer` fires
`manyhalls-loop-watchdog.service` every 15 minutes; the service runs
`fort/scripts/loop-watchdog.sh` once. That file's header is the design. In one
line: the Mayor silent for 60 minutes while fleet-safe, fleet-escalated or
mayor-review beads wait, or silent for 6 hours at all, or the fleet-safe pool
dry for 2 hours while open work exists, raises ONE alert per episode: a bead
assigned to justin (the Civ Keep's needs-you board), a `watcher.alert` event and
a desktop notification. When the condition clears the watchdog closes its bead
and emits `watcher.cleared`. It never writes the halt file and starts nothing.

Its latches live in `~/.local/share/manyhalls-watchdog/`. To see what it sees
without changing anything: `fort/scripts/loop-watchdog.sh --status`.

**Install (a person, unmasked), and only after one test alert has been seen:**

```bash
~/dev/fortkit/fort/scripts/loop-watchdog.sh --test-alert   # one marked test: bead, event, desktop
cp ~/dev/fortkit/fort/systemd/manyhalls-loop-watchdog.{service,timer} ~/.config/systemd/user/
cmp ~/dev/fortkit/fort/systemd/manyhalls-loop-watchdog.service ~/.config/systemd/user/manyhalls-loop-watchdog.service
cmp ~/dev/fortkit/fort/systemd/manyhalls-loop-watchdog.timer   ~/.config/systemd/user/manyhalls-loop-watchdog.timer
systemctl --user daemon-reload
systemctl --user enable --now manyhalls-loop-watchdog.timer
```

To stop it: `systemctl --user disable --now manyhalls-loop-watchdog.timer`.

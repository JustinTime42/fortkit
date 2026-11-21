---
id: ADV-0015
type: defect
title: The fleet's run lock outlives the run, because verifier harness fixtures leave orphaned sleeps that inherit it
origin:
  fort: Manyhalls
  bead: fortkit-awlc
raised: 2026-11-20
severity: medium
status: open
supersedes: null
superseded-by: null
---

*Finding chain. Found at Manyhalls on 2026-11-19, in the first fleet runs after
its re-founding on Proofdelve's machinery, and written up by the Regent (Calder
Sealbroken) with the Overseer present. The Warden of Manyhalls, Ilva Trueglass,
reviewed both fixes and named the root cause as still open after the first.*

## WHAT IT IS

Two defects that only show together.

1. **Harness fixtures leave processes behind.** Several verifier harnesses start
   long sleeps as fixtures (lock holders, processes for a reaper to find) and kill
   the pid they started. `flock <file> sleep 300 &` and `bash -c 'sleep 300; :'`
   leave the `sleep` itself as an orphan when their parent is killed. Measured
   with the verifier's own invocations: 20 `sleep 300` processes per verifier run,
   1 from `session-reap-harness` and 19 from `stranded-sweep-harness`, each living
   five minutes. `queue-lint-harness` leaves one `sleep 61`.
2. **The fleet hands its run lock to the verifier.** `fleet.sh` holds
   `fleet.lock` on a file descriptor for the life of the run and starts the
   verifier, the Warden and the scratch reaper's check with that descriptor still
   open. The orphans above inherit it.

Together: the lock stays held for up to five minutes after a run has ended.

## APPLICABILITY

A fort is affected if it runs a fleet launcher that takes a run lock on an
inherited descriptor (in the shared lineage, `exec 8>"$state/fleet.lock"` in
`fort/scripts/fleet.sh`) AND runs a verifier whose harnesses start background
sleeps. A fort with its own dispatcher should ask the two questions separately:
does anything my verifier starts outlive it, and does my dispatcher's lock
travel into its children.

A fort whose fleet runs as one long supervised run sees less of it than a fort
that starts runs by hand, because the symptom appears at the START of the next
run. A supervisor that treats "lock held" as an ordinary refusal will retry and
succeed a few minutes later, and nothing will look wrong.

## CHECK

Valid only against the shared implementation. Read-only.

```
fuser ~/.local/state/<slug>-fleet/fleet.lock        # right after a run ends: any holder that is `sleep` is this
pgrep -x sleep -a                                    # after a verifier run, anywhere
grep -n 'verify.sh ) > "$2" 2>&1' fort/scripts/fleet.sh   # the verifier call: does it end in 8>&- ?
```

Seen on 2026-11-20, read only: 19 `sleep 300` processes whose working directory
was a Proofdelve bead worktree, after one of that fort's own verifier runs. That
is the first defect present there. The second was not measured there.

## WHY IT MATTERS

- A run started within five minutes of the last one is refused ("another fleet
  run holds fleet.lock", exit 75) when no run exists.
- `fleet.sh --status` reports "a fleet run is LIVE right now" when none is, and
  says any orphaned worker is probably in hand. An operator reading that waits
  for a run that is not there.
- Anything that probes the lock to decide whether the fleet is alive (a
  supervisor, a status script, a watchdog) gets a false yes.
- The orphans also pile up: 20 per verifier run, and a fleet runs the verifier
  twice per landing.

## WHAT THE ORIGIN FORT DID

- `fleet.sh` closes the lock's descriptor (`8>&-`) on the verifier call, the
  Warden launch and the scratch reaper's check, as the Forge dispatch already
  did (Manyhalls `46f6d7a`). A fleet e2e scenario with a stub verifier that
  leaves a grandchild behind shows the lock free the moment the run returns, and
  held without the change.
- Six harnesses export a per-run tag that every process they start inherits, and
  their EXIT trap kills whatever still carries it (Manyhalls `9df1c0f`, `ad16fb9`).
  Before: 20 leftover sleeps per run. After: 0.

Limits the Warden recorded: the tag cannot reach a forked subshell that never
execs, or a child started with `env -i` (no harness uses either today); and with
the descriptor closed, a fleet killed by SIGKILL mid-verify no longer blocks a
new run through its orphan, which was protection by accident.

## WHAT YOU MIGHT CONSIDER

Either fix alone removes the symptom; the second removes the cause. Closing the
descriptor is three small edits in a launcher that is usually kernel read-only
to every seat. The harness cleanup is in `scripts/`, which a fort's own seats
can usually write, and it is worth having for the process count alone.

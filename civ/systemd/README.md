# Herald systemd user timer (fortkit-r6x.7)

Drafted by the Mayor; **installed by the Overseer's hand** — these files do
nothing until copied out of the repo. The Herald must launch unmasked, and a
systemd user service is unmasked by construction (the seat's own kernel mask
is applied inside herald.sh).

## Install (Overseer)

```bash
mkdir -p ~/.config/systemd/user
cp ~/dev/fortkit/civ/systemd/herald.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now herald.timer

# Required for unattended mornings: the user systemd instance must outlive
# login sessions, or the 05:00 timer only fires while a session is open.
loginctl enable-linger justin
```

## Verify

```bash
systemctl --user list-timers herald.timer   # NEXT should show the coming 05:00
systemctl --user start herald.service       # optional supervised dry run
journalctl --user -u herald.service -e      # launcher output + tail of the run
```

## Acceptance mapping (r6x.7)

1. **Timer active** — `list-timers` shows it scheduled.
2. **One unattended morning produces a report** — check
   `~/Documents/Obsidian Vault/herald/reports/<date>.md` and the paired
   `session.start`/`session.end` in `civ/events/`.
3. **Missed-morning catch-up verified once** — leave the machine off or asleep
   across a 05:00, then confirm the run fires shortly after wake
   (`Persistent=true`) and the report carries the catch-up date.

## Failure surfacing

Primary signal: herald.sh's own `incident` event + crash-stub report (exit 65
path), with the service unit relaunching once on the next ladder rung
(gpt-5.6-sol). Secondary signal: a failed unit in
`systemctl --user --failed` and the journal.

**Known gap until fortkit-izz is fixed:** if the vault itself is unwritable,
herald.sh's crash-stub writer dies at exit 1 with *no* incident and no
session.end — under the timer that failure surfaces only through the
secondary signal (failed unit / journal), not the event stream. izz's
pre-flight vault-writability probe closes this; fixing izz before relying on
unattended mornings is recommended.

## Notes

- The `gpt-5.6-sol` rung-2 model string is passed straight to
  `claude --model`; if the CLI's spelling for Sol differs, correct it in
  herald.service at install time and note it on the bead.
- herald.sh date-names its /tmp log, and a same-day relaunch truncates it
  (fortkit-izz). The service moves rung 1's log aside before the rung-2
  relaunch so no transcript is lost to failover.

---

# Manyhalls nightly consolidation (fortkit-iyj6.1 / fortkit-iyj6.2)

Drafted by the Mayor; **installed by the Overseer's hand**, same as the Herald
above. `consolidate.service` runs **unmasked as the user and commits to the
repository** — that is why it is gated on a person rather than installed by a
seat. It does not push.

**What it fixes.** `fort/memory/current.md` is the distilled view every seat is
told to read at session start, headed "do not edit" because
`scripts/consolidate-memory.mjs` is its authority. `docs/specs/memory.md:61` and
`:216` promise a nightly cron; it has never existed. On 2026-08-29 a Mayor ran
the generator to measure something else and **the file changed** — the shared
memory every seat trusts was stale and nothing reported it.
`fort/laurels/` joined at `fortkit-35uf.3` and has the same property.

## Install (Overseer)

```bash
cp ~/dev/fortkit/civ/systemd/consolidate.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now consolidate.timer
```

`loginctl enable-linger justin` is **already set** (measured 2026-08-31,
`Linger=yes`) from the Herald install, so it is not repeated here.

## Verify — all three, per `fortkit-iyj6.2`'s acceptance

```bash
# 1. the timer exists and has a NEXT run
systemctl --user list-timers consolidate.timer

# 2. a manual run either commits, or cleanly does nothing on an already
#    consolidated tree — and leaves the working tree CLEAN either way
systemctl --user start consolidate.service
journalctl --user -u consolidate.service -e
# SCOPE THIS TO THE FILES THE UNIT STAGES. A bare `git status` shows
# .beads/*.jsonl and today's event shard dirty whenever a seat is running,
# and NONE of that is the service's. A check that goes red for an unrelated
# reason teaches its reader to ignore it.
git -C ~/dev/fortkit status --short fort/memory/current.md fort/laurels/

# 3. catch-up, which is what Persistent=true is for. Miss a scheduled run
#    (machine off or asleep across 03:00) and confirm it fires at the next
#    opportunity. THIS IS THE ONE THAT MUST BE OBSERVED RATHER THAN ASSUMED.
```

**Corrected 2026-08-31 on first use.** The line above originally read `git
status --short  # must be empty`. It did not and could not: the Overseer ran
the install during a live Mayor session whose bead exports and event emissions
dirty the tree continuously. The unit was fine; the check was wrong.

**Why the third check is not optional.** A drafted unit is not a running one,
and this fort has a measured habit of reading the draft as the deployment: the
charter has named four watchers since founding and `fortkit-5v82` records that
none of them exist. `fortkit-iyj6` closes on the Overseer's own observation of a
timer that fired, not on this file existing.

**A masked seat cannot verify any of this.** `systemctl --user list-timers` is a
host measurement, and the Warden has declined to attempt it in three separate
reviews under the `masked-seats-cannot-measure-the-host` fact. The proof can only
come from the Overseer or the Regent.

## Known residual, stated rather than discovered later

The unit fires at 03:00, when no seat runs, and it does **not** take the
quiescence check that `fortkit-zj8e.3` is building. If a seat is ever working at
03:00 this unit will commit regenerated views underneath it. The views are
generated artifacts and regeneration is idempotent, so the worst case is a
surprising commit rather than lost work — but when `quiescent.sh` lands, this
unit should adopt it rather than growing a second notion of "busy".

# The Beads JSONL export: what it is, when it is fresh, and when to trust it

Status: ADOPTED. Overseer decision 2026-08-07 (`fortkit-bzx.5`); the freshness
mechanism below was MEASURED on 2026-08-31 under `fortkit-v7us` and this
document was promoted out of `docs/proposals/` in the same session
(`fortkit-v7us.1`, Overseer approval in session).
Author: Emrith Cairnwright (Mayor). Supersedes
`docs/proposals/issues-jsonl-export-rollout.md`, whose history this file
carries via `git mv`.

**Decision (Overseer, 2026-08-07):** `.beads/issues.jsonl` is the canonical
cross-fort state artifact. Beads' Dolt database remains the local operational
store; the JSONL file is a read-only projection and must never be imported or
edited as ordinary workflow.

## 1. Which source is authoritative

**`bd` is authoritative. The export is a convenience for readers who cannot
reach the database.**

Its audience is real but narrower than it looks: a fresh clone, another fort's
Mayor, and any posture where `bd` will not run. Whether this fort's Warden is
in that set is an OPEN QUESTION and deliberately not asserted here — her
profile permits `bd -C * show/list/search/memories`
(`fort/profiles/warden-settings.json:17-20`) while five of her reviews have
said `bd` cannot run in her posture. That contradiction is `fortkit-v7us.3` and
is unmeasured; do not cite either side of it as settled.

**Any count or bead state quoted into a durable record — a bead, a handoff, a
commit message, a seat file, an advisory answer — comes from `bd`, never from
the export.** This rule already cost the fort once: figures taken from the
export reached `fort/advisories.md`, a dispatch brief, and an Overseer-signed
amendment in `fort/seats/mayor.md`, where the true value at signing is now
unrecoverable (`fortkit-v7us`).

## 2. Freshness: the throttle, and the part that surprises people

Every fort uses this configuration in `.beads/config.yaml`:

```yaml
export:
  auto: true
  path: issues.jsonl
  interval: 60s
  git-add: false
```

`auto` exports after Beads writes, with `interval` as a throttle. `git-add`
stays false: export freshness is automatic, while tracking stays subject to the
fort's path-scoped staging rule. `fort-init` configures these keys and runs
`bd export -o .beads/issues.jsonl`, so a newly founded fort has its first
snapshot before its founding commit.

**THE THROTTLE DEFERS TO THE NEXT WRITE, NOT TO A TIMER. THIS IS THE WHOLE
TRAP.** After a Beads write the exporter flushes only if at least 60 seconds
have elapsed since the last flush. A write inside that window is neither
flushed nor scheduled — it waits for the next write that falls outside the
window. **With no further writes the export stays stale indefinitely. Nothing
catches it up on its own.**

The practical consequence: **a burst of writes leaves the export showing state
as of the burst's FIRST write.** Ten edits in ninety seconds produce one flush,
not ten, and the nine later ones are invisible until somebody writes again.

MEASURED, 2026-08-31, on this fort (`fortkit-v7us`):

| experiment | result |
|---|---|
| writes spaced ~100s apart | every write flushed within the same second, label edits included |
| four rapid `--remove-label`, then 244s with no `bd` command at all | 51 samples, **zero** caught up; export unchanged for 299s across nine pending writes. A 60s timer would have fired four times |
| one write afterwards (positive control) | export jumped forward immediately and contained the correct current state, including all four earlier removals |
| two consecutive `bd export` runs, unchanged database | **byte-identical** — so a freshness check can be a plain diff and will not flap |

The operation never mattered. Only the timing did. An earlier reading of this
mechanism held that `bd close` regenerates the export and label edits do not;
both halves are false, and the belief cost a session.

## 3. When you must not rely on the throttle

When a mutation must be represented immediately — **before a review, a handoff,
a commit, or any count you are about to write down** — run:

```bash
bd export -o .beads/issues.jsonl
```

This is one command and it is the whole remedy. `export.interval` is
deliberately left at 60s (Overseer, 2026-08-31): the throttle is a defensible
I/O tradeoff against a multi-megabyte file, and removing it would be a per-fort
config change requiring backport to every settlement.

A verifier stage that catches a burst-stale export before it reaches git is
`fortkit-v7us.2`.

## 4. Why no `.beads/hooks`

This uses no `.beads/hooks` directory. The seat sandboxes discover and bind
every hooks directory beneath `.beads` read-only, because those hooks execute
later on the HOST, unsandboxed, on the next commit or push in the main checkout
(`fort/scripts/lib/seat-sandbox.sh:452-472`). The exporter is a supported `bd`
configuration path, executes within the normal `bd` write flow, and leaves that
masking boundary intact.

## 5. Per-fort rollout — NOT COMPLETE

**This section describes work still outstanding. `fortkit-or2.1` is open: the
auto-export flow has not reached Proofdelve or Farlantern.** Do not read this
document as evidence that every fort has the configuration in §2.

This is a `fortkit-or2` backport cycle. The Overseer or designated backport
operator must, for each registered existing fort:

1. Set `export.auto=true`, `export.path=issues.jsonl`, `export.interval=60s`,
   and `export.git-add=false` with `bd config set`.
2. Run `bd export -o .beads/issues.jsonl`; confirm the file is nonempty and
   parses as newline-delimited JSON.
3. Stage only `.beads/config.yaml` and `.beads/issues.jsonl`, commit under that
   fort's normal review gate, and verify the committed export contains its
   expected current bead IDs.
4. Confirm no `.beads/hooks` path was introduced or made writable; the existing
   hooks masking remains the relevant host-RCE control.
5. Record the applied forts, commit IDs, and post-propagation evidence in
   `fortkit-or2` before marking the cycle complete.

The factory portion is the `bin/fort-init` change already merged: its
creation-time export is verified by founding a scratch fort and observing both
tracked files. Note for anyone running that smoke from a masked seat:
`bin/fort-init` aborts at the registry write unless `FORT_REGISTRY` is set to a
writable path (`fortkit-fg7s`).

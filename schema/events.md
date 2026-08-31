# Civilization event schema — CANONICAL COPY (forts vendor this; add-only, never rename)

Append-only JSONL, one file per day (`events-YYYY-MM-DD.jsonl`), written by `fort/scripts/emit.sh`. This is the fort's replayable history: the data source for the future Dwarf-Fortress-style visualizer (bead ForgeOs-din) and for any digest/monitoring consumer. Daily files are **gitignored** (worktree-concurrent appends would make tracked files a merge hazard); this README and the schema are tracked.

## Schema

**Time basis (decided 2026-08-04, fortkit-dpu):** `ts` carries an explicit offset and is an unambiguous instant; consumers group and order by **parsed UTC, never by filename**. The daily filename (`events-YYYY-MM-DD.jsonl`, writer-local date) is a **shard key, not a fact** — a file may contain instants from adjacent UTC days. Reader implementations must include the pinning test: an event stamped `23:24-08:00` belongs to the NEXT UTC day (`07:24Z`).

```json
{"ts":"2026-08-03T17:30:00-08:00","actor":"veyra","seat":"forge","category":"bead.claimed","target":"ForgeOs-mij","detail":"Veyra claims the CI bead","payload":null}
```

- **ts**: ISO-8601 with offset. **actor**: who did it (`marrek`, `veyra`, `tova`, `overseer`, `harness`, `watcher:<name>`). **seat**: office if applicable (`mayor|forge|warden`). **category**: dotted event type (below). **target**: bead ID, commit hash, seat, or path. **detail**: one human-readable line (this becomes the DF announcement text). **payload**: optional JSON (model used, tokens, verdicts, tallies).

## Categories (extend freely; never rename existing ones)

- `fort.founded`, `fort.renamed`, `moot.convened`, `moot.declaration`, `moot.ballot`, `moot.named`, `charter.amended`
- `seat.founded`, `seat.named`, `session.start`, `session.end`, `handoff.written`
- `bead.filed`, `bead.claimed`, `bead.closed`, `bead.blocked`, `bead.unblocked`
- `verify.run`, `verify.pass`, `verify.fail`, `review.verdict`, `merge`, `push`, `deploy`
- `incident`, `incident.corrected`, `laurel`, `overseer.decision`, `watcher.alert`, `drift.scan`
- `edict.begun`, `edict.ended`, `edict.applied`, `watcher.repaired` (fortkit-7vdm)
- `rule.fired`, `rule.retired`, `advisory.raised` (fortkit-gbhk.6)
- `digest.emitted` (fortkit-zj8e.2) — the session digest's window anchor:
  the next default run reads its timestamp as the lower bound. **Listed
  BEFORE the first one is emitted**, which is the whole point of the
  paragraph below and the first time this fort has managed that order.

**`digest.emitted` was listed before it was ever emitted (2026-08-31), and
that is a deliberate contrast with the paragraph that follows.** The Warden
caught it unlisted in round 1 of `fortkit-zj8e.2` — two days after this fort
closed `fortkit-7vdm`, which existed because four categories had been emitted
83 times between them without being listed. Knowing about a failure class two
days earlier prevented nothing; a reviewer reading the canonical list did.

**Four of these were being emitted before they were listed** (`edict.begun` 42
times, `edict.ended` 36, `edict.applied` 3, `watcher.repaired` 2, counted
2026-08-29). Two of them the charter MANDATES and instructs every seat to police
as a security signal, so the canonical schema omitted the categories the fort
escalates on. That is `fortkit-7vdm`, closed here. It was possible because
`fort/scripts/emit.sh:16-18` validates only that a category is non-empty and does
not begin with `-`: **this list is documentation, not a fence.** Making it one
is `fortkit-4ah3.4` (Regent lane, since `fort/scripts/` is read-only whole to
every seat), and until that lands a typo'd category is silently accepted and
invisible.

`rule.fired` and `rule.retired` support the law ledger (`docs/specs/law.md`).
`rule.fired` names the ruling a control acted under and is what makes "has this
rule ever caught anything" answerable; `rule.retired` is required by §5 of that
spec, which forbids a ruling leaving the corpus silently. **Decide `rule.fired`'s
cardinality before first emission, not after** — a fence that refuses on every
tool call must not emit per call — because the stream is append-only and a
volume mistake cannot be taken back.

**This file is the CANONICAL COPY and the elder forts vendor it.** Per standing
order 13 these additions reach them as an advisory rather than a sweep, and
declining is a complete answer.

## Emission points (who must emit, when)

- **Launchers** (`mayor.sh`, `forge.sh`): `session.start` on launch, `session.end` (with exit code) on exit.
- **Seats**: `handoff.written` at session close; Mayor emits `bead.filed` when filing; Warden emits `review.verdict` (payload: `{"verdict":"approve|request_changes|escalate"}`).
- **Harness**: `bead.claimed`/`bead.closed`, `verify.*`, `merge`, `push`, `incident`.
- **Watchers**: `watcher.alert` on any finding (plus filing the bead).

Rules: events are append-only and never edited (standing order 12 applies); one event per line; keep `detail` under ~140 chars so it reads as an announcement; timestamps may be backfilled only with `-T` and only for reconstructing real history.

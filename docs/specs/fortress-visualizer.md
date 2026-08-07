# Fortress Visualizer — Design Brief

**Status: dormant by choice.** Bead: `ForgeOs-din` (P3, trigger-gated). Written 2026-08-03, founding day, so the idea survives until its time. The v0 prerequisite (event stream) is DONE and accumulating history; everything below builds on it.

> **Product name (Overseer decision, 2026-08-07, recorded on `fortkit-zgp`): Bartizan.** This brief remains a historical record; the name applies to its world and future colony viewer surfaces without revising the original text.

## Vision

A Dwarf-Fortress-style colony view of Proofdelve: a simple sprite world you can leave on a second monitor, where ambient activity is legible at a glance and every entity drills down to detail. Watchability is the monitoring strategy: a dashboard nobody opens protects nothing, but a fortress you enjoy watching is observability that gets used. Eventually: control (v2) and presence (v3).

## Why DF is the right metaphor (not decoration)

The mapping is nearly isomorphic — DF is a colony-management interface and this fort IS a colony:

| DF | Proofdelve | Data source |
|---|---|---|
| Dwarves (identity, moods, history) | Seats: Marrek, Veyra, Tova | `fort/seats/*.md`, events |
| Job queue (claimed, dependency-resolved) | Beads ready/claim/close | `.beads/issues.jsonl` (passive export, safe to read) |
| Workshops (permanent, by work type) | The Forge (implementation), Scriptorium (specs/docs), Assay Office (tests/verification), Proving Grounds (CI) | bead type/labels, `verify.*` events |
| Occupied workbench inside a workshop (ephemeral) | An active git worktree: appears when a seat sets up on a bead, cleared on merge | `git worktree list`, `session.*` events |
| Intruders (vermin/goblins) caught and jailed | Bugs, regressions, incidents. Arrest = Warden/watcher catch; dungeon = open-bug queue; rehabilitation = fix in progress; release = bead closed; **recidivism = regression** (same goblin back in the cells, extra scrutiny). The goblin is always the defect, never the dwarf who wrote it: structural blamelessness, rendered. | bug-typed beads, `incident*`, `verify.fail`, `review.verdict`, `watcher.alert` events |
| Trade depot (inspection before goods move) | Merge queue + Warden review | `review.verdict`, `merge` events |
| Bookkeeper / sheriff | Watchers | `watcher.alert` events |
| Petitions at the gate | Wish-factory intake (feature_requests) | bead 15b pipeline once built |
| Announcements feed | Event `detail` lines (written ≤140 chars for this) | `fort/events/events-*.jsonl` |
| Engravings of past disasters | Postmortems, incident events, annals | `fort/annals/`, `incident*` events |
| Happy thoughts / legends mode | Laurels, seat histories, the Founding Moot | seat files, `fort/annals/founding-moot.md` |
| Adventure mode | The Overseer as playable character (already holds beads) | — |

**Spec discipline this creates now:** the workshop and dungeon views need bead *typing* to render: Mayor should tag beads by work type (implementation / spec / test / infra) and file defects as bug-typed beads, from today onward. A regression is a new bug bead linked `discovered-from` the original — that edge is what makes recidivism renderable.

(Adjustments 2026-08-03, Overseer's review: workshops were originally mapped to worktrees; corrected because worktrees are ephemeral and DF workshops are permanent stations — worktrees are now occupied benches. Dungeon mapping added at the Overseer's suggestion.)

## Data contract (LIVE — the part that had to exist before building)

- **Event stream**: `fort/events/events-YYYY-MM-DD.jsonl`, append-only, schema + category registry in `fort/events/README.md`. Categories are add-only, never renamed, so replays never break. Founding day (2026-08-03) is backfilled from real git timestamps: 26 events from `fort.founded` to `moot.named` — day one is replayable, mistakes included.
- **Work graph**: `.beads/issues.jsonl` (Beads maintains it as a passive export; do NOT treat as source of truth or write to it).
- **Seats/handoffs/annals**: markdown in `fort/`, human-and-machine readable.
- **Emitters**: `fort/scripts/emit.sh` (worktree-safe via git-common-dir, flock-guarded); wired into `mayor.sh`, `forge.sh`; seat duties documented in AGENTS.md/CLAUDE.md.
- **Live-colony semantics** (fortkit-d0b, 2026-08-07): the colony view renders the *live* fort — closed beads leave workshops, dungeon, and unassigned alike; history is the replay scrubber's job (v1 bullet below). The dungeon holds bug beads through their whole arrest: open (jailed), in_progress/blocked (rehabilitation), released only at close.

## Build plan

- **v1 — Renderer (a weekend):** single self-contained HTML page + canvas (Smallville/AI-Town lineage: sprites pathing between buildings). Buildings: Mayor's office, one workshop per active worktree, trade depot (merge), archive (handoffs/annals), gate (intake). Poll the JSONL sources every few seconds; animate transitions on new events; announcements ticker from `detail` lines; click any entity for a DF-style panel (seat: name/pronouns/personality/current bead/last handoff; bead: full detail + provenance edges). **Replay scrubber** over the event files: watch any day back, including founding day.
- **v2 — Control:** click-to-act via the same scripts the harness uses: pause/resume a seat (TaskStop / relaunch), claim/assign beads (`bd update`), approve at the depot (merge script). Never bypass the charter gates: the UI is a skin over existing capability boundaries, not a new capability.
- **v3 — Presence/play (speculative):** the Overseer walks the fort (adventure mode); a fort square where agent "play" (welfare essay's open frontier) could live. Only if v1/v2 earn it.

## Trigger to resume (from bead ForgeOs-din)

Digest watcher (ForgeOs-z76) landed + multiple seats running concurrently + Alyeska interview done. Rationale: the fortress is the *most seductive yak in the project*; it renders a colony that must first exist. The DF failure mode applies: don't lose the fortress building the museum.

## Known risks (recorded 2026-08-03, Overseer's question: "any technical reason this is suboptimal?")

1. **Labeling-pipeline dependence.** Workshop/dungeon views render bead types assigned by hand; skipped or drifted tagging degrades the render silently (the classifier-death failure class). Mitigations: small add-only taxonomy; untyped beads rendered conspicuously (a dwarf without a job), never hidden; watcher on untyped-bead ratio.
2. **Hard boundaries over soft distinctions.** Real beads span types; bug-vs-feature is genuinely blurry. Accept approximate placement; never shape beads for the render. Process drives the visualization, not the reverse.
3. **Goodhart pressure.** A visible dungeon population is a metric. It is legibility only — never a KPI, no per-seat catch counts (same reasoning as Yegge's unrankable laurels).
4. **Recidivism is approximate.** Regression links require judgment and are unenforced; `discovered-from` semantically means provenance, not recurrence — use a `regression-of` label/convention and accept incompleteness.
5. **Projection discipline.** The renderer is an event-sourcing projection: `.beads/issues.jsonl` is source of truth for STATE; events are animation/history only; tolerate missing events (scripts can bypass emit.sh). Silence is not success applies to gamelogs.

## Context for whoever builds it (possibly an agent, possibly much later)

Full research trail: `~/Documents/agent-harness-research/` (Yegge/rUv synthesis, fort design at `10-forgeos-city-design.md`). The visualizer conversation that produced this spec happened 2026-08-03 in the founding session. Key prior art: Stanford "Generative Agents" Smallville and AI Town (rendering approach), DF's job system (already isomorphic to Beads ready-work + atomic claiming). Keep the mechanical layer boring and the identity layer flavorful, same rule as the rest of the fort.

---
*Migrated 2026-08-04 from Proofdelve (fort/specs/) to fortkit as civilization-level founding spec. Elevated to two-level design: world view (all registered forts via ~/.claude/civilization.json) + fort/colony view (this spec). Read-only v1; schema custody lives in fortkit/schema/events.md.*

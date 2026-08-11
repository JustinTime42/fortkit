# Memory: the Muniment Room — Manyhalls memory architecture v1

Status: DRAFT — pending Overseer approval on fortkit-88u.1.
Author: Emrith Cairnwright (Mayor), 2026-08-10.
Bead: fortkit-88u.1 (epic fortkit-88u). Decisions of record: fortkit-88u.2.
Provenance: the Mayor's 2026-08-10 memory assessment (codebase audit + literature
review, on that session's record) and the Overseer's five rulings on fortkit-88u.2.

This spec captures WHAT and WHY. Interfaces (TypeScript types, reader contracts)
belong in code and are deliberately not encoded here; implementation beads define
them under this spec's constraints.

## 1. Purpose

Manyhalls writes excellent records and reads almost none of them back. The
2026-08-10 assessment graded the fort A on persistence, B on temporal validity,
C+ on relational structure, D+ on retrieval: ~600k tokens of durable record, of
which a fresh session receives near zero unless prose happens to point at it.
This spec defines the architecture that closes the read path: where durable
facts live, how they are updated and trusted, how they are indexed, and exactly
what every seat receives at session start.

Design constraints, in priority order (from the Overseer's requirements):
1. **Safe and secure** — memory writes must be admission-controlled and
   poisoning-resistant within the charter's threat model.
2. **Traceable** — every fact carries provenance; every change is reviewable
   and tamper-evident.
3. **Relevance-filtered** — sessions receive what they need under a hard
   budget; nothing pollutes every conversation (the Overseer's annals
   principle, generalized).
4. **Available everywhere** — readable under every mask, mount, and scratch
   copy this fort actually runs (plain files; no daemon on the read path).

## 2. The layers

| Layer | Role | Trust | Storage |
|---|---|---|---|
| Episodic record | what happened | authoritative, append-only | events, handoffs, bead comments, annals (unchanged by this spec) |
| **Fact ledger** | current operational truth | **store of record** | one fact per file, git-tracked |
| Derived index | search | zero trust, disposable | SQLite FTS5, gitignored, rebuilt |
| Distilled view | current-state snapshot | derived, tracked | one markdown file, regenerated |
| Delivery | what a session receives | governed by §7 | hook + launcher injection, budgeted |

The episodic record is not modified by this spec. Standing order 7 continues to
bind it absolutely. The ledger is CURRENT STATE, not history: git history is its
supersession chain, which is how "supersede, don't delete" and "readable current
truth" stop being in tension (Overseer ruling 2, fortkit-88u.2).

## 3. Decisions of record (fortkit-88u.2, all final 2026-08-10)

1. **Store of record**: the ledger-and-index architecture below. `bd remember`
   retires; `fort/remember.md` and `civ/remember.md` retire by migration (§8).
2. **Compaction**: append-only law binds records of what happened (beads,
   handoffs, verdicts, events), not current-state facts. Ledger edits are
   ordinary recorded commits; history lives in git.
3. **Write-only surfaces**: annals are accessible on demand, never injected;
   rulings-of-record are extracted into the distilled view. interactions.jsonl
   is recall-searchable, never injected. Telemetry prompt content is
   archival-by-design and stays untracked.
4. **Cadence**: v1 is deterministic. Regenerate ephemerally at session start;
   a nightly watcher-cron regenerates and commits the tracked artifacts.
   Model-based distillation is v2, own bead, Herald-H6-style supervised gate.
5. **Tracking**: ledger and distilled view are git-tracked. The index is
   exempt as a zero-trust derived artifact; telemetry content stays untracked.

## 4. The fact ledger

### 4.1 Location and shape

- Fort facts: `fort/memory/facts/<key>.md` — one fact per file.
- Civilization facts: `civ/memory/facts/<key>.md` — same schema, capital only.
- `<key>` is a kebab-case slug and IS the fact's identity. Renames are
  supersessions (§4.3), not moves.

Each file is YAML frontmatter plus a concise body:

```markdown
---
key: warden-launcher-records-verdict-verbatim        # must equal filename
status: active                                        # active | superseded
superseded-by: null                                   # key, when superseded
tier: on-demand                                       # core | on-demand
scope:                                                # selection tags, ≥1
  seats: [mayor, warden]                              # or [all]
  topics: [warden.sh, review-flow]                    # free, lowercase
  beads: [fortkit-5mw]                                # optional anchors
provenance:
  source: "fortkit-5mw / fort/scripts/warden.sh:52"   # bead, event, commit, or file:line — required
  declared-by: emrith                                 # roster actor id
  date: 2026-08-10
  origin: trusted                                     # trusted | untrusted
---
The warden.sh launcher records the review's ENTIRE final message verbatim as
the bead comment; a review whose final message is not self-contained loses its
record. (Why it matters / how to apply, 1–5 lines. Bodies are facts, not
essays; an essay belongs in a handoff or annal with a fact pointing at it.)
```

### 4.2 Tiers and the size doctrine

- `core`: injected into EVERY session, including bare ones. The hard doctrine
  cap belongs to a session, not the fort: for each seat, the core facts visible
  to it — its own scoped facts plus every `seats: [all]` fact — total ≤ 300
  lines / ~30 facts. This is the measured degradation threshold for wholesale
  injection into one context. The lint enforces each seat's cap; exceeding it
  forces a demotion decision, on purpose.
- A `seats: [all]` core fact spends budget in every seat at once. memory-lint
  reports that shared floor separately, so widening a fact's scope is visible
  rather than a default. Total core facts across the fort may therefore exceed
  30 while no session does.

  **PRECONDITION, and it is not met yet** (recorded 2026-08-11 per Warden
  finding 2 on fortkit-88u.16; the Mayor's bead asserted per-seat delivery as
  already true and it is not). The sentence "no session does" holds only if
  delivery is scope-filtered. Today it is not: `fort/memory/current.md` is
  built from *every* active core fact with no scope filter
  (`scripts/consolidate-memory.mjs`), and CLAUDE.md instructs every seat to
  read it. So a fort can pass memory-lint with 25 mayor-scoped and 25
  forge-scoped core facts — each seat green — while every real session receives
  all 50 and the degradation threshold is blown in all of them. That is a green
  gate over a violated condition, which is the exact failure this budget exists
  to prevent.

  **Until `fortkit-88u.6` lands or `consolidate-memory` filters `current.md`
  per seat, the per-seat cap is an upper bound on what a seat SHOULD receive,
  not on what it DOES receive.** The gap is currently hypothetical (four core
  facts against a cap of thirty) and it must not be allowed to stop being
  hypothetical silently.

- **What belongs in `core` at all.** The test is consequence, not relevance: *a
  session that never read this fact would take a harmful, hard-to-reverse
  action within its first few steps.* Tripwires qualify — "never read `.env*`",
  "the deploy script is human-only", "build before you test or the HintPaths
  lie". Background architecture and historical measurement do not; they are
  `on-demand`, and recall exists to reach them.

  Per-seat scoping makes tripwires precise instead of universal: "never push
  without asking" is a Mayor tripwire, "commit path-scoped, never `git add .`"
  is a Forge tripwire, and neither needs to burn the other's budget.

  *A relevance-ranked core was considered and rejected* (fortkit-88u.16). The
  facts that most need to be core are the ones least related to current work —
  they are dangerous precisely because nobody was thinking about them — so a
  relevance ranker would demote exactly the facts whose value is arriving
  unbidden. A job that silently rewrites the always-injected surface is also
  the charter's own escalation signal: an operating-assumption change with no
  bead and no announcement. Charter rule: *crons watch, models act.* A router
  becomes a v2 candidate when there is an **observed** failure of the form "a
  session went wrong because the right fact was not core" (standing order 11);
  that failure will also say which band the fact belonged in.

- `on-demand`: reachable by selection (§7) and recall (§6). Unlimited count.

### 4.3 Write rules (admission control)

1. A ledger write is an ordinary git commit: path-scoped, message referencing
   the motivating bead/event where one exists. It is therefore visible in
   `git status`/diff immediately, reviewable, offsite on push, and covered by
   the charter's unexplained-change security signal — none of which was true
   of `bd remember`.
2. Updating a fact = editing its file. The old text is in git history; no
   in-file supersession chains, ever. A fact whose meaning REVERSES gets a new
   key with `status: superseded` + `superseded-by` on the old file, so a
   reader who finds the stale key learns where truth went.
3. Superseded files may be deleted once nothing references them; deletion is a
   recorded act (commit message says why). Git retains the history.
4. Facts derived from untrusted content (fetched web pages, third-party text)
   MUST set `origin: untrusted` (standing order 8 applied to memory). The
   selector treats origin as a ranking/eligibility signal: untrusted facts are
   never `core` (lint-enforced) and rank below trusted facts at equal score.
5. Seat access follows existing boundaries: attended seats write via normal
   commits; the Forge's ledger writes ride its bead branch through Warden
   review like any change; masked seats read the root ledger by absolute path.

### 4.4 memory-lint (mechanical enforcement, house style)

A `memory-lint` step joins `fort/scripts/verify.sh`: schema-valid frontmatter;
`key` equals filename; required provenance fields present; `scope` non-empty;
per-seat core-tier budgets respected (with the `seats: [all]` shared floor
reported separately); `origin: untrusted` never `tier: core`;
`superseded-by` references resolve; body non-empty. A red lint is a red build.
When a constraint keeps being violated in prose, it becomes a lint rule — the
fort's standing conversion.

## 5. The derived index (zero trust)

`fort/memory/index.db` — plain SQLite tables (`source` rows plus a `gaps`
table), **gitignored**, rebuilt deterministically from its sources by the
consolidation job (fortkit-88u.5). Corruption or poisoning of the index is
repaired by rebuild; it is never a store of record, and nothing may be written
to it that is not derived from a tracked source.

*Amended 2026-08-10 (fortkit-88u.11, from Warden 88u.5 r2 finding 1): this
section originally mandated FTS5. `node:sqlite` on the supported runtime
(Node 24, no native dependencies permitted) rejects FTS5 virtual tables, so
the index is plain tables with no in-database matching or scoring; matching
and scoring are application-side, owned by `fortkit recall` (§6.2,
fortkit-88u.7).*

Indexed corpus (per Overseer ruling 3): the fact ledger; handoff sections;
events; annals (including rulings-of-record); the beads `issues.jsonl` export;
`interactions.jsonl`. Each row carries: source path, parsed timestamp (UTC,
never filename-derived — the dpu/schema pinning rule), actor/seat where known,
and a snippet. Unreadable or unparseable sources are recorded as disclosed
gaps in the build output, never skipped silently (the wtm lesson as design).

## 6. The distilled view and recall

### 6.1 Distilled view

`fort/memory/current.md` — tracked, regenerated deterministically (same inputs
→ byte-identical output). Contents, each line carrying a provenance pointer:
core-tier facts; a capped bead snapshot; the newest handoff's "State of
work" + "Next actions" per seat (suffix-aware, timestamp-ordered); unresolved
incidents from recent events; extracted rulings-of-record. Cadence per ruling
4: ephemeral regeneration at session start, nightly cron commit.

*Amended 2026-08-10 (fortkit-88u.14, Overseer ruling on Warden 88u.5 r2 f7):
the bead snapshot is capped, replacing the original full open/in-progress
dump. It carries all in-progress beads, all gate-labeled beads, and the top
15 ready beads by priority, and closes with an explicit "N of M open beads
shown; full list via bd ready" line. Grounds: the full dump was ~110 of the
view's 162 lines, duplicated a query every seat can run live, and staled
hourly against a nightly regeneration cadence — a stale authoritative-looking
list misleads where a short one with a live pointer does not. Handoff
sections remain verbatim per the same bead's ruling on r2 f6; the control is
write-side (§9).*

### 6.2 fortkit recall (fortkit-88u.7)

The single blessed retrieval path, replacing ad-hoc grep. Contract: query →
structured hits (source path, date, seat/actor, provenance, snippet), date
windowing on parsed timestamps, `--seat`/`--topic`/`--bead` filters mapping to
scope tags, and disclosed gaps. Deterministic, dependency-light, no embeddings
in v1 (a v2 semantic layer requires an observed retrieval failure per standing
order 11).

Invoke it from a fort root as `fortkit recall <query> [--seat <seat>] [--topic
<topic>] [--bead <bead>] [--since <ISO timestamp>] [--until <ISO timestamp>]`.
It emits a JSON object with `hits` and `gaps`: every hit names its source,
parsed UTC date where available, actor/seat, matching section, provenance, and
the indexed section text. `--since` is inclusive and `--until` exclusive.
Recall rebuilds the disposable index before querying, so a missing, stale, or
poisoned `index.db` cannot silently narrow the corpus; readers expose build
gaps alongside matching results.

Filter semantics (documented 2026-08-10 per Warden 88u.7 r2 f3): a fact scoped
`seats: [all]` matches every `--seat` filter (the spec's seats wildcard, §4.1).
Rows with no parsed timestamp (annals, interactions) are excluded by any
`--since`/`--until` window and the exclusion is disclosed as a synthetic gap
entry, never silent. `--seat` also excludes the surfaces that carry no seat
tags at all (annals, beads, interactions) — deliberate exact-filter semantics,
disclosed here; whether it additionally warrants a runtime disclosure is
fortkit-88u.12's call.

## 7. Delivery: per-seat injection requirements (fortkit-88u.6)

Selection is deterministic in v1. Ranking: tier, then scope-tag match (seat,
bead anchors, topic overlap with the dispatch prompt), then recency, then
recall's application-side match score (amended 2026-08-10, fortkit-88u.11:
formerly "FTS score" — the index carries no scoring, see §5); `origin:
untrusted` demoted at equal rank. Beyond the core tier, a hard
budget of ~8,000 tokens of selected memory per session (amended 2026-08-10,
fortkit-88u.14: the initial ~4,000 was an unmeasured starting value; the
Overseer raised it to fit the distilled view plus scope-selected facts — the
bound stays hard and its value stays tunable on evidence); the selector
discloses what was dropped ("N facts matched, M injected") — no silent caps.

Testable assertions (tests target prompt assembly, not model behavior):

| Session | MUST receive |
|---|---|
| Every session, incl. bare | core tier (SessionStart hook reads the ledger directly — this lands as the immediate mitigation, before launcher work) |
| Mayor | core + distilled view + latest N mayor handoffs, suffix-aware |
| Forge (bead X) | core + distilled view + "Failed attempts" and "State of work" of every prior handoff naming X + budgeted scope selection for X's topics; all memory paths root-absolute (worktree copies are stale by construction) |
| Warden (bead X) | core + prior review rounds for X |
| Herald | digest (its law) + core |
| Regent | whole ledgers per fort (post-88u.8 whole-file discipline) + civ ledger |

`handoff.written` emission moves into the launcher close path in the same
amendment batch (currently ~11% emission; the event stream undercounts memory
9x).

## 8. Migration (ordering within fortkit-88u.5's implementation)

1. `fort/remember.md` → facts: each bullet resolves through its supersession
   chain to ONE current-truth fact with provenance pointing at the old
   file:line and the originating bead. The 6jf caveat becomes a fact whose
   removal condition is its own supersession.
2. The single `bd remember` entry migrates to a `core` fact; `bd remember` is
   then deprecated by doctrine: CLAUDE.md/AGENTS.md state that the ledger
   overrides `bd prime`'s memory guidance (we cannot edit bd's own output;
   the doctrine line is the override of record).
3. `fort/remember.md` is replaced by a pointer stub to `fort/memory/` (seat
   files and launcher prompts update in the same change — no dangling
   "read remember.md" instructions; the lint greps for them).
4. `civ/remember.md`: operational facts migrate to `civ/memory/facts/`; its
   essay-length lessons remain archival (recall-indexed, never injected),
   consistent with the annals ruling. Phased after the fort migration proves
   the pattern.

### 8.5 Cross-fort migration (fortkit-xgul, Project A)

Section 8 describes fortkit's own migration. This section governs carrying the
ledger to **every other fort**, and it is the spec the A-children implement
against. Approved by the Overseer 2026-08-11 as Project A, sequenced ahead of
Researcher propagation (fortkit-vhk.7) because `docs/specs/researcher-seat.md`
§8 names origin-tagged memory as one of three threat-2 mitigations, and §4.3
rule 4 is where that mitigation lives.

**Measured starting state (2026-08-11).** Proofdelve `/home/justin/dev/ForgeOs`
`fort/remember.md`, 52 lines / 21,141 bytes. Farlantern
`/home/justin/dev/longburn` `fort/remember.md`, 46 lines / 17,765 bytes. Both
are dense: long single-line bullets, most carrying inline provenance already.
Neither has `fort/memory/`.

**1. Mapping unit.** One top-level bullet becomes one fact. Sub-bullets and
continuation lines stay in that fact's body. Section headings (`## Migrated
patterns`, `## Seat machinery`) become `scope.topics` entries on the facts
beneath them, never facts themselves. Prose that asserts nothing checkable is
not a fact: per §4.1 bodies are facts rather than essays, so it moves to an
annal with a fact pointing at it. The implementer records which bullets took
that route and why.

**2. Tier.** Default is `on-demand`, and the default is load-bearing rather
than lazy. §4.2 caps `core` at ~30 facts **per seat** (amended 2026-08-11,
fortkit-88u.16 — this paragraph said "per fort" until then, and the correction
matters here because this is the section that travels to other settlements);
each elder fort has roughly
20–25 bullets, so migrating them as `core` would consume or exceed the entire
budget with legacy content and leave no room for anything learned afterwards.
Promote to `core` only when this test passes: **a session that never read this
fact would take a wrong action within its first few steps.** Build and test
ordering, never-read-this-file rules, and human-only deploy paths pass it.
Background architecture, historical measurements, and superseded corrections do
not. Every `core` promotion is justified on the migration bead by name.

**3. Provenance, without inventing a declarer.** A line lifted from a flat file
has no author of record, and fabricating one would be a falsification under
standing order 7.

- `source`: `"migrated from fort/remember.md:<line>, <commit-sha>"`, plus the
  bullet's own inline attribution where it has one (many do: `ForgeOs-21f.8,
  measured 2026-08-04`; `Warden, 0lg r1, 2026-08-06`). Both go in `source`.
- `declared-by`: the actor performing the migration, because that actor is
  attesting the transcription is faithful, not that the claim is theirs.
- `date`: the migration date. The fact's own date lives in `source`.

**Never move an inline attribution into `declared-by`.** A Warden who wrote one
sentence in 2026-08-06 did not declare a ledger fact in 2026-08-11.

**4. Origin.** `trusted`, and the reasoning rather than the assumption: this
content was written by fort seats and the Overseer inside the fort's own
records, and predates any web-reading seat in this civilization. The
implementer must still **check** each bullet for content derived from fetched
material and tag it `untrusted` per §4.3 rule 4. None was observed in either
file at survey; that is an observation, not a guarantee.

**5. Supersession — nothing is discarded.** Standing order 7 governs. A stale
bullet migrates with `status: superseded` and a `superseded-by` pointer where a
successor exists; where staleness is suspected but unproven it migrates
`active` and the doubt is recorded on the migration bead. Deletion is not
available to this migration under any reading.

Per §4.3 rule 2 there are **no in-file supersession chains**: where a flat file
carries both a claim and its correction, they become **two facts**, the older
one `superseded` and pointing at the newer.

*Known instance the implementer must not miss:* Proofdelve
`fort/remember.md:39` asserts that `fort/charter.md`, `fort/seats/` and
`fort/profiles/` are read-only to every seat, and closes `(Superseded in part —
see the cycle 7 r2 correction below.)`; lines 43–52 are that correction. These
are two facts, linked. Farlantern must be read for the same pattern rather than
assumed clean.

**6. The stub.** `fort/remember.md` is replaced by a pointer stub matching the
one fortkit left, so the shape is identical in every fort and a seat that
arrives at the old path learns where truth moved.

**7. Verification — the migration is proven, not asserted.** A4 and A5 do not
close on an implementer's word. Required, with output recorded on the bead:

- **Cover check.** Extract every top-level bullet line number from the
  pre-migration file at its recorded commit; assert each appears in some fact's
  `source`. An uncovered line is an unmigrated fact, which is a dropped record.
- **memory-lint green** in that fort, including the `core` budget and the
  `superseded-by` resolution rules of §4.4.
- **`current.md` generates** from the new ledger and carries an honest
  index-gaps section.
- **Count reconciliation**: bullets in, facts out, and the difference explained
  (splits for supersession raise the count; annal-routed prose lowers it).

## 9. Security model (mapped to the poisoning literature's four points)

1. **Write-time admission**: review-gated commits + memory-lint (§4.3–4.4).
2. **Provenance binding**: required frontmatter provenance + git blame.
3. **Retrieval-time filtering**: origin-aware ranking; untrusted never core.
4. **Post-hoc forensics**: per-fact git log; incidents emitted on anomalies;
   an unexplained ledger diff with no bead and no event is the charter's
   standing escalation signal, now covering memory.

Out of scope, per the charter's threat model: cryptographic signing/HMAC of
memory writes defends against a local-shell adversary the fort explicitly does
not defend against. Documented, not built.

**Accepted risk — verbatim handoff sections in the distilled view** (amended
2026-08-10, fortkit-88u.14, Overseer ruling on Warden 88u.5 r2 f6): §6.1
copies handoff sections verbatim, so a secret that ever reaches a handoff
would be amplified from one tracked file into every injected session's
context (threat 4). Ruled acceptable with the control at the write side: the
secrets-scan watcher's corpus includes `fort/handoffs/` and
`fort/memory/current.md` (fortkit-1zw), failing on credential-shaped content
before it propagates. Grounds: a handoff is already tracked and pushed, so
the handoff itself is the breach and the view only the amplifier; scanning
at the source treats the class once. Read-time redaction (blocklist false
confidence) and pointer-only sections (second-hop fragility for masked
seats) were considered and declined. No observed incident motivates heavier
machinery (standing order 11); this paragraph is the record that the risk
was traded knowingly.

## 10. Acceptance benchmark

The epic is done when, demonstrably and by test:
1. memory-lint green in verify.sh; a seeded schema violation turns the build red.
2. A bare session's context contains every core fact (hook test).
3. Each seat row in §7 holds against its assembled prompt (launcher tests).
4. `fortkit recall` finds a planted fact in each indexed surface, windows
   correctly across the local/UTC seam, and reports a planted unreadable file
   as a gap.
5. The distilled view regenerates byte-identically from fixed inputs, and the
   old remember.md supersession chain resolves to the correct current truth
   in a pinned test.
6. Migration leaves zero live references to `fort/remember.md` outside git
   history, and `bd memories` no longer carries the fort's only injected fact.

## 11. Out of scope for v1 (v2 candidates, each requiring an observed failure)

- Embedding/semantic search over the index.
- Model-based distillation (unattended Mayor session; Herald-H6-style gate).
- Graph store for multi-hop relational queries.
- Cross-fort federated recall (the capital indexing elder forts' ledgers).

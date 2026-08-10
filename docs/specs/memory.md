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

- `core`: injected into EVERY session, including bare ones. Hard doctrine cap:
  the core tier totals ≤ 300 lines / ~30 facts across the fort (the measured
  degradation threshold for wholesale injection). The lint enforces the cap;
  exceeding it forces a demotion decision, on purpose.
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
core-tier budget respected; `origin: untrusted` never `tier: core`;
`superseded-by` references resolve; body non-empty. A red lint is a red build.
When a constraint keeps being violated in prose, it becomes a lint rule — the
fort's standing conversion.

## 5. The derived index (zero trust)

`fort/memory/index.db` — SQLite FTS5, **gitignored**, rebuilt deterministically
from its sources by the consolidation job (fortkit-88u.5). Corruption or
poisoning of the index is repaired by rebuild; it is never a store of record,
and nothing may be written to it that is not derived from a tracked source.

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
core-tier facts; open/in-progress bead snapshot; the newest handoff's "State of
work" + "Next actions" per seat (suffix-aware, timestamp-ordered); unresolved
incidents from recent events; extracted rulings-of-record. Cadence per ruling
4: ephemeral regeneration at session start, nightly cron commit.

### 6.2 fortkit recall (fortkit-88u.7)

The single blessed retrieval path, replacing ad-hoc grep. Contract: query →
structured hits (source path, date, seat/actor, provenance, snippet), date
windowing on parsed timestamps, `--seat`/`--topic`/`--bead` filters mapping to
scope tags, and disclosed gaps. Deterministic, dependency-light, no embeddings
in v1 (a v2 semantic layer requires an observed retrieval failure per standing
order 11).

## 7. Delivery: per-seat injection requirements (fortkit-88u.6)

Selection is deterministic in v1. Ranking: tier, then scope-tag match (seat,
bead anchors, topic overlap with the dispatch prompt), then recency, then FTS
score; `origin: untrusted` demoted at equal rank. Beyond the core tier, a hard
budget of ~4,000 tokens of selected memory per session; the selector discloses
what was dropped ("N facts matched, M injected") — no silent caps.

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

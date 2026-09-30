# 07: The systemic upgrade: derive, couple, deliver, prove

Status: APPROVED IN SHAPE by the Overseer, 2026-09-30 ("overall I like the
plan"; "I approve all and agree with your recommendations"). Drafted by the
Regent (Calder Sealbroken) from the design conversation of the Regent sitting
of 2026-09-29 (`civ/handoffs/regent-2026-09-29T135305.md`). Filed as epic
`fortkit-2y2t.40`, with Phase 0 as `.40.1` to `.40.6`; nothing is built. Decisions taken are marked **DECIDED**. Each phase still lands
item by item under the ordinary gates; approval of the shape is not approval of
any individual change.

## Why

A sitting spent measuring the machinery rather than extending it found that
most of the civilization's maintenance cost is not in its ideas but in its
plumbing, and that the plumbing is mostly generic.

Measured on 2026-09-29:

- **Commits are small** (median 2 files, 1 area, in both Manyhalls and
  Proofdelve since 2026-08-01). The felt sprawl of a change comes from three
  multipliers, not from tangled code:
  1. **Copies.** 12 of the factory's 27 template files exist in all four forts
     in **five distinct versions** (four forts plus the template). A two-file fix
     is a ten-file fix plus a patcher.
  2. **Prose restating mechanism.** `verify-impl` appears in ~100 files
     civilization-wide; 27 of the capital's 40 are Markdown. Every restatement
     is a copy that goes stale silently (the cycle-7 fact: 19 days wrong).
  3. **Undeclared string protocols.** `FORT_MASKED` (50 files), `VERDICT-LINE`,
     event categories, `Touches:` and `bd`'s JSON keys are produced in one place
     and parsed in several with no schema.
- **Proofdelve's orchestration is ~7,500 lines of bash**, tested by ~12,200
  lines of bash harness that scrape functions out of source with awk. The
  Regent's own memory records the language's failure families dozens of times
  (`trap`/`exec` 35+, extraction 38, `set -e` 14, `pgrep` 12, `pipefail` 11).
- **The Regent's briefing at wake was 551 KB** (~140k tokens), mostly
  `civ/remember.md` (5,082 lines) injected whole, and the `pgrep` self-match
  scar recurred six times while sitting in it. Injection is not recall at the
  point of use.
- **Much of what we built exists off the shelf**, and the design record
  catalogued the closest relative (Gas Town, built on the same `bd`) before the
  fleet was written from scratch. `bd` 1.1.2 ships `--metadata`, `formula`,
  `mol`, `swarm`, `gate` and `merge-slot`; Proofdelve uses only `merge-slot`.

What is genuinely ours and worth keeping: per-seat kernel masks with measured
probes, the gate and signing model under a written covenant, the Effect
Gateway, and institutional memory with provenance.

## The spine

1. **Derive** what the code can tell you. Implementation facts are queried from
   code or a regenerable index, never hand-written. A derived index can lag; it
   cannot rot.
2. **Couple** what it cannot. Authored "why" (decisions, intent, doctrine) is
   anchored to the code it concerns and flagged mechanically when that code
   changes.
3. **Deliver** at the point of use. Knowledge reaches a session when it touches
   the relevant code or command, not wholesale at wake. Procedural scars become
   controls (hooks, lints, tests), not paragraphs.
4. **Prove** every mechanism with a check that can fail: a positive control, a
   deliberately broken variant, an eval. (The AgentDB post-mortem below is the
   reason this is the spine's last word.)

And, across all four: **policy and identity are data; code is shared and
vendored; law is adopted, never installed.**

## Decisions already taken (DECIDED, Overseer, 2026-09-29)

- **Hands are roles, not citizens.** Parallel sessions spawned from templates
  (Study, Scribe, Deputy) carry no name, no declaration, no history of their
  own. They read the ledger at launch and return beads. Only the Mayor
  accumulates judgment. Covenant 8.1 is untouched.
- **Shared machinery is vendored**, pinned per fort, upgraded through a bead the
  fort may decline, reviewed in-tree by that fort's Warden. Never auto-updated.
- **Greenlab is the prototype**, specifically `plot`, the capital's test bench,
  whose purpose is exactly this (`06-autonomous-operation.md`).
- **The Warden gets a copy-on-write `bd` snapshot** (option B below), not write
  access to `.beads` and not the export-only workaround.

## Phase 0: Measure first (no building)

Every item produces a number that decides a later item.

| # | Measurement | Decides |
|---|---|---|
| 0.1 | Run the drift watcher's identity normalization over the five-version files; count what remains as real architecture. **And diff the two cutting-edge lineages, Proofdelve against Greenlab's factory, since the 2026-09-22 copy** (see 4.0) | size of Phase 2.1 and 4 (is packaging a step or a refactor), and how much reconciliation the package's source needs |
| 0.2 | Build a **retrieval eval**: 30-50 questions taken from real incidents and tasks ("what does `bd merge-slot check` return with no slot?"), scored hit@k, tokens, tool calls. Baseline: grep only | whether Phase 3 adds a structural index, a semantic index, both, or neither |
| 0.3 | DONE 2026-09-30, see 1.2. Time `cp --reflink=always` of `.beads/embeddeddolt` into a Warden scratch root (both btrfs; 1.5 GB in Proofdelve), and whether `bd --readonly` then serves every read subcommand from the copy | Phase 1.2 |
| 0.4 | Does `bd --metadata` reach the export, and can `bd list/ready` filter on it? | Phase 1.3 (`Touches:` as metadata) |
| 0.5 | Run the capital's mask conformance suite (`mask-harness.sh`, boundary probes) against **greywall** and **ai-jail** profiles expressing our three seat postures | Phase 2.2 (substrate: ours or theirs) |
| 0.6 | Inventory `civ/remember.md` and the four facts ledgers: which entries are procedural scars convertible to a control, which are "why", which restate code | Phase 3.3 scope |

## Phase 1: Cheap wins in plot

**1.1 Structured verdicts.** The Warden returns a JSON-Schema object (Agent SDK
structured output, or the CLI equivalent once verified) instead of a scraped
`VERDICT-LINE`. Retires a scar family: injected trailing lines, prefix arm
order, truncation. The vocabulary (APPROVE, APPROVE-WITH-FINDINGS,
MERGE-PARENT-OPEN, REQUEST-CHANGES, ESCALATE) becomes an enum in one schema file.
Control: the existing injection fixtures must still fail to change the verdict.

**1.2 The Warden's `bd` snapshot (DECIDED).** *Corrected 2026-09-30 by the
measurement `fortkit-2y2t.40.3`: a reflink is impossible (every `.beads` is
btrfs No_COW), but a plain copy of Proofdelve's 1.5 G database takes 0.96 s and
`bd` serves every read from it identically, so the design stands as a plain
copy. The copy must be taken under `bd`'s own lock (`embeddeddolt/.lock`), and
a copy `bd` cannot open falls back to the export loudly.* At launch,
`warden.sh` copies `embeddeddolt` (plus `config.yaml` and `metadata.json`) into
her scratch; she runs real `bd` (with `--readonly`) against
it; her profile stays read-subcommands-only so she never believes a write
landed; the snapshot dies with the scratch. Falls back to today's export on a
non-reflink filesystem, loudly. Retires the prompt paragraph, the `jq`
instructions and the inverted half of smoke probe 10, and gives the reviewer
`ready`/`blocked`/dependency queries. Her read-only-by-construction property is
unchanged: the real `.beads` stays read-only in her mask. Controls: a write
inside her session must not reach the real database (measured by row count
before/after); `bd show` must succeed on the snapshot.

**1.3 One `bd` adapter.** A TypeScript module (called from bash via a thin CLI)
that encodes every measured quirk once: `--limit` caps, swapped
`dependency_type`/`type` keys, `merge-slot check` exiting 0, `bd blocked
--limit 0` returning empty, comment bodies absent from `show --json`. Each quirk
gets a test against real `bd`. `Touches:` moves into `--metadata` if 0.4 says it
can; `prose-blockers.py` stays as the lint that pushes prose into real edges.

**1.4 Native telemetry.** Enable Claude Code's OpenTelemetry export for seat
sessions to a local file/collector, for cost, tokens and tool-permission
decisions. The civic event stream (`emit.sh`, JSONL in git) is unchanged; this
replaces inference, not record.

**1.5 The inference gateway decision, inside `.35`.** Proposal: the bridge keeps
its job (seat netns boundary, endpoint allowlist, no model management) and
forwards to a pinned **LiteLLM** proxy host-side for routing, keys, 429 handling
and a second budget cap, rather than growing routing logic into the bridge. The
governor keeps reservations; the Effect Gateway is untouched. **Needs the
Overseer's call before the `.35` sitting.**

## Phase 2: Structure

**2.1 Identity out of the machinery.** Citizen names, fort names and persona
lines leave the launchers for a roster data file read at launch. Launchers
become genuinely shared. Measure: re-run 0.1; the five-version count should
collapse toward one plus declared policy deltas.

**2.2 Mask policy as data.** One profile per seat (rw paths, ro carve-outs,
masks, secret globs, env allowlist, network) compiled to bwrap argv by a small,
unit-testable generator (optionally adding Landlock/seccomp). The conformance
suite stays black-box and unchanged, which is what makes the rewrite safe. If
0.5 shows greywall or ai-jail passes the suite, we maintain profiles on their
substrate instead of a lib. The suite itself is the portable asset.

**2.3 The fleet: bake-off, then adopt or strangle.** Before Sitting E1 builds
more on it, run **Gas Town against our fleet** on the same small plot beads
(Gas Town inside our masks, or not at all). Then either adopt Gas Town's
scheduler/Refinery/Witness with our launchers as its workers, or **strangle
ours into TypeScript**: pure decision logic first (touch-set intersection,
verdict routing, governor math, stall predicate, landing guard) as tested
modules bash calls, then the loop. `fleet-e2e-harness.sh` stays unchanged as the
black-box spec throughout. Evaluate `bd formula`/`mol` for the per-bead
lifecycle in the same bake-off. Adopt a bisecting batch merge queue (Refinery,
Bors) if the fleet survives.

**2.4 Seat templates and hands.** Seat definitions move from 4 KB inline
`--append-system-prompt` strings to agent definition files (frontmatter: tools,
model) packaged as a Claude Code plugin; the launcher keeps only the mask. Hands
(DECIDED: roles) are instances of those templates:
- **Study**: read-only over the fort, writes one notes file; for brainstorming.
- **Scribe**: reads the fort, writes only a `content/` lane.
- **Deputy**: attended implementation in its own worktree, leased by
  `Touches:`/metadata, landed through the merge slot and the Warden.
Evaluate Claude Code agent teams (shared task list, mailbox) as the in-session
mechanism for hands the Mayor spawns.

## Phase 3: Knowledge

**3.1 A derived code index.** Host-built, incrementally maintained (Merkle
hashes / file watcher), bind-mounted read-only into masks, exposed over MCP.
Candidates: **Serena** (LSP, symbol-level) against one tree-sitter code-graph
server; optionally a hybrid BM25+dense layer (claude-context or CocoIndex, local
embeddings via Ollama, or sqlite-vec inside the existing `index.db`). Only what
0.2's eval justifies ships. MCP servers are dependencies: pinned and vendored.

**3.2 Symbol anchors.** Ledger facts, specs and decision beads (`bd` has a
`decision` type) carry anchors such as `fleet.sh#land` or
`seat-sandbox.sh#build_mask`. One checker, unifying `fort/controls/`
fingerprints and Proofdelve's `fact-freshness.mjs`, resolves anchors through the
index on every commit: a changed symbol hash flags the fact for re-verification;
an anchor that no longer resolves fails. Symbol, not line, so moving code does
not cry wolf. A lint flags facts containing identifiers or line numbers without
an anchor: **a fact may not restate what the index can answer.**

**3.3 Point-of-use delivery.** A PreToolUse hook: when a session reads or edits
an anchored symbol or file, inject the "why" facts anchored there (reverse
lookup through the index). The core tier shrinks to doctrine under a hard byte
budget. Procedural scars from 0.6 become controls, starting with the Regent's
own (`pgrep -f` self-match, `emit.sh` from `$PWD`, `bd comment` without
`BEADS_ACTOR`). `civ/remember.md` migrates to the ledger (`fortkit-nqoy`) in the
same pass. This is the one piece found nowhere off the shelf for agents (Swimm
does the code-to-why join for humans); it should be a few hundred lines on top
of an adopted index.

**3.4 Re-run the eval** with each layer on and off. A layer that does not move
hit@k or cost does not stay. Memory components ship with a positive-control
retrieval check in the verifier, forever.

## Phase 4: Package and port to production

**4.0 The package's source is the cutting edge, not the capital's template.**
The civilization has three machinery lineages, measured 2026-09-29:

| Lineage | What it is | State |
|---|---|---|
| **Proofdelve** (`ForgeOs/fort/scripts`) | production cutting edge: fleet, supervisor, airlock, the Keep, signed landing | still moving: 6 commits to fleet/warden/forge/seat-sandbox since 2026-09-22 |
| **Greenlab's factory** (`greenlab/bin/fort-init`, `greenlab/templates`) | a copy of Proofdelve's machinery taken 2026-09-22 (Sitting A), identity-stripped, then extended: isolation by inversion, governor, Effect Gateway, capacity leases, capital-review Warden | fleet.sh 4,717 lines, warden.sh 932, seat-sandbox 1,230 |
| **The capital's template** (`fortkit/templates`, `fortkit/bin/fort-init`) | the factory that founded Kithmason on 2026-09-02 | far behind: no fleet at all, warden.sh 245 lines, last touched 2026-08-17 |

So the package is built by **reconciling Proofdelve and Greenlab** (0.1 measures
their divergence as well as the five-version copies), and the capital's
template is **retired or regenerated from the package**, never used as a base.
E1 founds the working fort from Greenlab's own factory, not the capital's.

**4.1 The package.** Scaffolding and updates via **Copier** (three-way merge from
a versioned template, which is the vendored-with-local-edits problem exactly);
shell and TS core vendored under a pinned directory, kernel read-only to every
seat; prompts, agents, hooks and skills as a Claude Code plugin; the conformance
suites ship with the package and run in each fort's verifier. Advisories become
release notes; the drift watcher becomes a version check.

**4.2 The port order**, each as that fort's own bead, adoptable or declinable
under covenant 12 and reviewed by that fort's Warden under covenant 4.5:
Kithmason first (young, quiet, and founded from the stale template, so it gains
the most and risks the least), then Farlantern, Manyhalls, and Proofdelve last
(live fleet, customer-facing product; it is also a SOURCE of the package, so its
port is mostly adopting its own machinery back as a pinned version). Every
item crossing a kernel-read-only path in a production fort is a Regent sitting
with the Overseer present, one commit per item, per rule 4.

## Decisions on the open questions (DECIDED, Overseer, 2026-09-29/30)

The Overseer's words: "I approve all and agree with your recommendations."

1. **Sequencing against Sitting E1** (`fortkit-2y2t.12.2`): Phase 0 and Phase 1
   first, and the 2.3 bake-off before E1 builds more fleet. The working fort is
   founded from **Greenlab's factory** (see 4.0) after 2.1, so it is born with
   identity as data.
2. **LiteLLM behind the bridge in `.35`** (Phase 1.5): approved.
3. **TypeScript** for new orchestration and adapter code: approved. Greenlab's
   money path stays Python.
4. **Gas Town bake-off**: approved.
5. **Upstreaming** `bd` quirk reports: approved in principle. Each report is
   still an outward-facing act under covenant gate 6.1: a seat drafts it, and the
   Overseer files it from his own account.

## Implementation: who builds it, and how

Added 2026-09-30 at the Overseer's direction ("let's write this plan down so
it's safe, then begin").

### The constraint that decides the split

Most of what this plan changes is kernel read-only to every seat: launchers,
the mask lib, `warden.sh`, `fleet.sh`, profiles, `bin/`. That is deliberate (a
fleet that could edit its own dispatcher and reviewer has no boundary), and
Proofdelve measured the cost of forgetting it: twenty beads unroutable because
they named only paths the Forge can never write (`ForgeOs-76uob.2`). So
**wiring into the control plane is always a Regent sitting**, and **what sits
behind the wiring is fleet work**, provided it lives in writable paths.

### The pattern: seams cut by sittings, filled by the fleet

Spec, then interface, then test, then implementation:

1. **A Regent sitting cuts the seam**: defines the interface (a TypeScript
   module signature, a JSON schema), adds the call site in the kernel-read-only
   launcher behind a stub, and lands the black-box acceptance test that must go
   green.
2. **The fleet fills it**: Forges implement the module in worktrees, the Warden
   reviews, the fleet lands. The acceptance test is the bead's criterion.
3. **A Regent sitting wires and pins it**: stub removed, real module live,
   verified in the real mask.

The existing black-box harnesses (`fleet-e2e-harness.sh`, `mask-harness.sh`,
the boundary probes) are what make this possible: they are unambiguous
acceptance criteria a Forge can be held to.

### Lanes by phase

| Phase | Sittings | Fleet-able |
|---|---|---|
| 0 | Mayor: `.40.1`, `.40.2`, `.40.4`, `.40.6` (read-only; in-session subagents may parallelize). Regent: `.40.3`, `.40.5` (host-side) | none |
| 1 | Regent: structured verdicts and the CoW snapshot (`warden.sh`), telemetry (settings), LiteLLM (inside `.35`) | the `bd` adapter module and its tests against real `bd` |
| 2 | Regent: Gas Town bake-off install and run; seam cutting | the fleet's decision logic moved to TypeScript function by function; the mask-policy compiler; the roster/identity data |
| 3 | Regent: host-side index install, hook registration. Mayor: fact migration and anchors | the anchor checker, reverse-lookup injection logic, eval re-runs |
| 4 | one Regent sitting per fort port (covenant 4), each through that fort's own bead | Copier template content, package tests |

Roughly half the code by volume is fleet-able; every decision and every wiring
step is a sitting.

### Which fleet (OPEN: the Overseer's decision after Phase 0)

- **Not Proofdelve's**: it works only in its own repo, its queue is its Mayor's
  (covenant 2), and it is doing product work.
- **Greenlab's `plot` fleet** for Greenlab-side modules, on the frontier rung
  under its capacity lease (the local rungs could not reliably finish a two-file
  bead in Sitting C; DeepSeek, `.35`, may become the cheap rung).
- **Recommended: found the package as its own fort** from Greenlab's factory,
  with its own fleet, whose product is the fort machinery. Self-hosting, like a
  compiler: the fort's running machinery is always a pinned, previously signed
  version, so its fleet builds the next version without ever running
  unreviewed code on itself. Founding a settlement is covenant gate 6.3.
- Fallback: the capital's Mayor dispatching Forges by hand (no fleet loop).

### Order

1. **Now**: a Mayor session on the four Mayor-lane Phase 0 beads, and the Regent
   on `.40.3` and `.40.5`. Neither blocks the other.
2. **After Phase 0 reports**: the package-fort and fleet-rung decisions; the
   Mayor files Phase 1 and 2 as seam-and-fill pairs with `Touches:` and
   acceptance tests.
3. **Then waves**: a Regent sitting cuts a batch of seams, the fleet fills them
   over a few nights, a Regent sitting wires and pins them.

## Appendix: the AgentDB post-mortem (why "prove" is in the spine)

The 2026-08 retirement of ruflo/AgentDB was mostly upstream failure, widely
shared: agentic-flow #129 (`retrieveRelevant()` returns 0 while the inner index
finds the data), ruflo #2677 (0 of 60 stores could retrieve an episode on an
81-store fleet; `doctor` checked only that the file existed; "a check that
cannot fail protects nothing"), ruflo #3327 (controllers report enabled and
never activate; open as of 2026-09-14), ruflo PR #3407 (merged 2026-09-23;
silent hash-vector fallback and NULL embeddings reported as success). Our share:
a hardcoded path in our own classifier that crashed 66 nights behind `|| echo`,
customizations inside a signed upstream bundle, an activity counter as reward,
and **no store-X-search-X-expect-X check**, which would have found everything in
a day. The lesson is not "avoid retrieval". It is that memory systems fail
silently, because an empty result looks like "nothing relevant".

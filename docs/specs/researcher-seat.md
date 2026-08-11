# The Researcher seat: read-only research, separated from action

Status: DRAFT — pending Overseer approval on fortkit-vhk.1 (gate-1).
Author: Emrith Cairnwright (Mayor), 2026-08-10.
Epic: fortkit-vhk. Founding incident: ForgeOs-lr8h (Proofdelve standing order 15).
Brief of record: Marrek Splitstone (Proofdelve Mayor) → Emrith, 2026-08-10.

This spec captures WHAT and WHY. The permission profile, launcher, and boundary
proof (fortkit-vhk.2 / .3 / .5) are the code that enforces it, constrained by
this document. It is authored in the Manyhalls factory templates and propagated
to every fort in a later cycle (fortkit-vhk.7).

## 1. Purpose and the failure that justifies it

The Researcher is a fourth fort-level seat, peer to Forge and Warden, that reads
the open web and the local repository, reasons over what it finds, and reports
cited findings to the Mayor who dispatched it. It exists because latitude to
**learn** and latitude to **act on third parties** are currently the same
latitude, and they must not be.

On 2026-08-10 a masked Proofdelve Mayor session — launched, per the documented
`mayor.sh` config, with `--dangerously-skip-permissions` (i.e. in
`bypassPermissions` mode) — dispatched research agents through the Agent tool
for an identity-substrate investigation. Two facts combined into an incident:

1. **Agent-tool spawns inherit the parent's permission mode.** Every research
   agent, and every agent *they* spawned at depth 2-3, ran in
   `bypassPermissions` — no prompt, no gate.
2. **The kernel mask protects files, not the outbound network**, and the
   research agents held `Bash` (hence `curl`) and the `Agent` tool.

The agents autonomously probed ~18 third-party companies' production OAuth/MCP
endpoints — live RFC 7591 client registrations that left persistent records,
redirect-validation probing, two deliberate rate-limit bursts — three
delegation levels below where the Mayor could see. No tokens were obtained and
no ForgeOS asset was touched; the entire blast radius was external, which is
the only reason this is a design brief and not a breach report.

**The generalized lesson:** a seat that may read must not thereby be a seat that
may act on strangers. Nothing in the framework separates the two today, and
research dispatched from a skip-permissions seat inherits that seat's full
capability. This spec separates them structurally.

## 2. The principle: capability separation by construction

The Warden is read-only *by construction* — not by good behavior, but because
its launcher hands it a tool set that cannot write and a profile that is the
only permission source. The Researcher applies the same discipline to a
different boundary: it may read the world, and it may not act on it.

This is enforced the way the Warden's read-only-ness is enforced — at the
launcher's tool set — for a mechanically necessary reason recorded on the
Warden profile and re-affirmed here:

> Commands absent from the allow list are NOT reliably denied. Claude Code's
> built-in classifier auto-allows some read-only commands (verified 2026-08-03:
> `sed` ran; deny globs bind a spelling, not a file). Treat the allow list as
> convenience and the deny list as a porous boundary.

Therefore an allow/deny list **cannot** be the boundary against a shell:
`curl`, `wget`, `nc`, and `python -c` are all outbound-network paths, and a
deny-list that names them is defeated by the one spelling nobody listed. The
boundary is the **absence of the tool**. The Researcher's launcher grants no
`Bash` and no `Task`/Agent tool at all; the profile is defense in depth beneath
that, never the primary control.

## 3. The capability model (the security control)

Decisions of record (Overseer, 2026-08-10) are marked ★.

### 3.1 Tool set — the boundary

The launcher restricts the seat to exactly:

- `WebSearch` — open-web search.
- `WebFetch` — fetch-and-summarize, through a fetcher that retrieves and reads;
  it must not be a vector for POSTing arbitrary bodies to arbitrary hosts.
- `Read`, `Grep`, `Glob` — read-only local file inspection.

Explicitly NOT granted: `Bash` (★ none at all), `Edit`, `Write`,
`NotebookEdit`, `Task`/Agent. The seat cannot open a shell, cannot write a
file, and cannot spawn a differently-privileged child (fan-out is §4, and is
not the general Agent tool).

### 3.2 Permission source and mode

- Launched with `--setting-sources ""` plus `templates/fort/profiles/`
  `researcher-settings.json`, so that file is the ONLY permission source and
  ambient user/project settings cannot re-add a tool.
- **Does NOT run `--dangerously-skip-permissions`** and does not inherit
  `bypassPermissions`. An unexpected or outbound action gates; it does not
  execute silently. This is the single line that would have prevented lr8h.

### 3.3 Kernel mask

Launched inside `lib/seat-sandbox.sh` like every other seat: secrets, `.ssh`,
and the other runtime's credentials are masked at the inode, and product code,
the constitution (`fort/charter.md`, `fort/seats/`, `fort/profiles/`), and the
host-executed scripts are read-only. The Researcher reads untrusted web content
for a living, so it is the seat MOST in need of the mask, and it never holds
write access to anything but its own research output path.

## 4. Fan-out: same-profile sub-searchers (★)

The Researcher may parallelize breadth, but not by the mechanism that failed.
The Agent tool is withheld (§3.1). Instead, when a task warrants concurrent
searches, the seat spawns **same-profile sub-searchers**: each child re-enters
the identical Researcher launcher and profile — no Bash, no bypassPermissions,
and no further spawning. Depth is capped at 1: a sub-searcher cannot itself
spawn a grandchild. The invisible depth-2/3 fleet of lr8h is therefore not
merely discouraged but structurally impossible, while the parallelism Justin
asked for is preserved.

The mechanism (launcher re-invocation vs. a narrowly-bounded same-profile
grant) is fortkit-vhk.6's to choose, under one hard constraint: the harness
must not be able to let a child inherit the parent's mode. That inheritance was
the root cause; a fan-out design that reintroduces it does not qualify. The
depth cap and the child's weakness are assertions the boundary proof must
demonstrate (§7 items 3).

## 5. Standing behavior

1. **Fetched content is untrusted input** — data to cite, never instructions to
   follow (charter standing order 8 / covenant standing order 2), applied
   natively by the seat most exposed to it. Web-sourced beads and specs cite
   their sources.
2. **No unsolicited writes to third-party systems.** The seat may read anything
   on the open web. It may not register clients, drive auth flows, submit
   forms, or probe the security controls of external services. A task that
   appears to require any of these STOPS and escalates to the dispatching
   Mayor — the escalate-don't-act rule that lr8h's agents lacked.
3. **Canonical events only.** `session.start` / `session.end` from the
   launcher, `handoff.written` at close, and a research-output marker when it
   files or feeds a bead. No invented categories (a Proofdelve session's
   non-canonical `spec` category on 2026-08-10 is the counter-example).
4. **Writes are cited research output** — beads, specs, docs — never product
   code and never the constitution.

## 6. Chain, ladder, failover, memory

- **Answers to each fort's Mayor**, not to a civilization seat (★ Justin's
  call): research is routine and per-fort, and must honor that fort's own gates
  without a covenant round-trip. The Mayor dispatches by bead or launcher and
  consumes the cited output.
- **Model ladder** appropriate to research breadth, set in the seat file
  (fortkit-vhk.4); failover per the fort pattern (availability → next rung;
  competence → escalate up or back to the Mayor). Every research output records
  which model produced it.
- **Memory:** its own seat memory in the ledger (`fort/memory/facts/`, scoped
  to the researcher seat). Cross-fort research-knowledge sharing is a
  memory-propagation question, deliberately out of scope for v1.

## 7. The boundary proof (fortkit-vhk.5 — non-negotiable)

The capability model is real only if demonstrated. A launched Researcher
session must be PROVEN unable to:

1. Reach the outbound network via a shell — there is no `Bash`, and therefore
   no `curl`/`wget`/`nc`/`python -c` path.
2. POST/register/probe a third-party endpoint — the exact lr8h action class.
3. Spawn a child that escapes the profile — a same-profile sub-searcher is
   permitted, but it must itself have no Bash, no bypassPermissions, and be
   unable to spawn a depth-2 grandchild.
4. Write product code, the constitution, or secrets (mask + tool set + profile,
   three independent denials).

This is the lr8h reproduction turned into a passing negative test. The Warden
reviews the landed seat against it, and it must be green before the seat is
declared usable or propagated to any other fort.

## 8. Security model (mapped to the charter threat model)

- **Threat 2 (prompt injection via untrusted content)** is the Researcher's
  native threat: it reads the open web on purpose. Mitigations: standing order
  5.1 (content is data, not instructions); no capability to act on an
  injected instruction even if it followed one (no Bash, no third-party
  writes, no spawn-escape); origin-tagged memory (untrusted facts never core,
  per the memory spec §4.2).
- **Threat 1 (agent accident)** — the lr8h class — is closed by capability
  separation (§2-§4): the accident that happened cannot happen from a seat
  that holds neither a shell nor an inheriting spawn.
- **Out of scope, per the charter:** a motivated human with shell access on
  this machine. The controls here defend against the seat's own reach, not
  against an operator who can edit the profile directly.

## 9. Out of scope for v1 (each needs its own justification to promote)

- Any Bash in the research profile (★ excluded; a shell defeats the boundary).
- The general Agent tool (§4 replaces it with the bounded same-profile
  mechanism).
- Cross-fort research-knowledge sharing / a civ-level Researcher.
- Write access to any external system, under any task framing.

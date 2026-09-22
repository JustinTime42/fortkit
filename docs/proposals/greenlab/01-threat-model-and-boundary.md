# 01 — Threat model and the same-machine boundary

## The inversion

The production civilization ranks its threats (from `fort/charter.md` and
`civ/covenant.md`): agent accident first, prompt injection second, supply chain
third, credential leakage fourth. That ranking is earned — *every incident ever
recorded in any fort is an agent accident*, and the stakes are paying customers.

Greenlab inverts it, because the thing that makes accident the top production
threat (a customer sees the mistake) is gone. A greenfield experiment that
breaks costs nothing. So:

### Greenlab threat rank

1. **Credential and repository leakage into the experiment civilization.** This
   is the one threat that stays high-stakes even when the work is throwaway. An
   experiment that fails is fine; an experiment that reads a production `.env`,
   your SSH key, your cloud credentials, or pushes to a customer repo is a real
   incident. **On a shared machine this is threat 1 by a wide margin**, and the
   controls against it are non-negotiable (below).
2. **Outbound reputation and legal exposure.** A greenfield experiment may touch
   the world — post content, sign up for a service, send a message. Even at low
   stakes, the Overseer's name is on it. This is what the surviving human gates
   and the effect gateway defend.
3. **Runaway spend.** Governed by a number (a monthly loss ceiling, a per-action
   cap), never by a gate.
4. **Agent accident against the work — DEMOTED to accepted-and-undefended.** A
   wrong command that deletes an experiment's worktree costs nothing the Overseer
   cares about. This demotion is the single change that licenses dropping most of
   the work-protecting gates. It is recorded here as a deliberate acceptance, the
   way the production charter records the residuals it accepts.

### The design rule that falls out

Keep **walls** and **governors**; drop **prose gates** and most **human gates**;
demote the **reviewer** from a merge-gate to a **tripwire**. Walls untouched
because their blast radius reaches threat 1; everything else relaxes because its
blast radius is only the work, and the work is cheap.

## The same-machine decision (D3)

**Decision:** Greenlab runs on the RTX 3060 Ti machine, which is the Overseer's
primary work computer and already hosts the production civilization's repos,
`~/.ssh`, `~/.aws`, `~/.codex`, `~/.claude`, and paid-customer `.env` files.

**Risk:** stated plainly and accepted by the Overseer on 2026-09-18. A
low-guardrail civilization sharing a filesystem with high-stakes secrets is
exactly the configuration the production charter's threat 4 (credential leakage)
exists to prevent. The mitigation is not "trust the low-stakes civ to behave" —
it is the same kernel machinery that already stops a masked Manyhalls Mayor from
writing another fort's tree, extended to make the production surface **invisible**
rather than merely read-only to every Greenlab seat.

This decision makes the mask design load-bearing rather than convenient. If it is
wrong, it is wrong in the one way that matters, so the founding gate for Phase 1
(see 05) is a **measured** proof — byte counts from a shell, the discipline from
the sandbox-probe work — that a Greenlab seat reads zero bytes of the production
secrets and cannot write the production repos.

## The mask non-negotiables (what does NOT relax at low stakes)

These are **built** into Greenlab's own `seat-sandbox.sh` by the founding — they
do **not** port from Proofdelve unchanged. Measured 2026-09-22 (P7,
`founding-artifacts/mask-extension-spec.md`): Proofdelve's mask masks a seat's own
repo secrets and binds `$HOME` read-only-but-readable, so applied as-is it leaves
production `.env` (2135 bytes), `~/.claude/.credentials.json` (524),
`~/.codex/auth.json` (4178), the production registry, and production repo files all
readable from a Greenlab seat, and `~/.local/state` writable. The isolation below
is the production-masking block the founding adds. Greenlab having fewer guardrails
never touches any of it.

1. **Production secrets masked to `/dev/null` in every Greenlab seat.** Byte count
   zero under every spelling. The set (enumerated from the production registry at
   build time): every customer repo's `.env*`, `~/.claude/.credentials.json`,
   `~/.claude/civilization.json`, `~/.codex/auth.json`, `~/.ssh/*`, `~/.aws/*`.
2. **Production repositories bound ABSENT** (empty tmpfs), not merely read-only, in
   every Greenlab seat. The `touch`-refusal already holds (core memory); the new
   requirement is that a Greenlab seat cannot even *read* a customer repo — absent
   is cleaner than readable-with-secrets-masked and does not rely on glob
   completeness.
3. **`~/.local/state` isolated.** Greenlab seats get their own state root; the
   production fleet's HALT file and locks are not writable or visible to a Greenlab
   seat. This is the one finding that is cross-civ *interference*, not disclosure,
   and the most important to close.
4. **Separate credentials.** Greenlab uses its own credential set in a
   Greenlab-specific path, held only by the Effect Gateway (04, Phase 4); the
   reasoning seats hold none, and production credentials are masked from every
   Greenlab seat. A greenfield experiment must be unable to push with a production
   key or spend against a production billing account.
5. **Cross-civilization launch refusal.** A Greenlab seat is kernel-refused from
   launching a production seat and vice versa. This is the existing `FORT_MASKED`
   marker plus registry-scoping: a masked seat aborts at preflight, and the two
   registries (`~/.claude/civilization.json` vs `~/.claude/greenlab.json`) name
   disjoint fort sets. The `fort-init` factory already reads `FORT_REGISTRY`;
   the enforcement is that a Greenlab launcher resolves only the Greenlab
   registry and a production launcher only the production one.
6. **Host-executed scripts stay kernel read-only to every seat.** A sandbox is
   only as strong as the script that builds it. Greenlab's launchers, its
   `seat-sandbox.sh` (including the production-masking block above), its
   `.git/config` and hooks are read-only to every Greenlab seat exactly as they
   are in production. Fewer guardrails on the *work* never means a seat can edit
   the machinery that sandboxes it.

## What DOES relax

Everything whose blast radius is only the work:

- The verifier stops being a merge gate for ordinary experiment code (it stays a
  gate only where an action touches spend or an external identity).
- The Warden reviews after merge and announces, rather than blocking.
- The prose push/deploy gate is gone; push is governed and gated only above a
  spend/identity threshold.
- Charter/seat-file edits inside a Greenlab fort can be far lighter, because a
  Greenlab fort's constitution protects a throwaway experiment, not a customer.
  (The *civilization's* covenant and the shared machinery stay locked; a single
  experiment fort's own charter can be nearly disposable.)

## The line, stated once

**Walls protect the operator and cost nothing; gates protect the work and cost
attention. Greenlab keeps every wall and drops nearly every gate.** The
same-machine decision is safe exactly to the degree the walls in this document
hold, which is why Phase 1 proves them by measurement before anything else runs.

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

These port from `fort/scripts/lib/seat-sandbox.sh` **unchanged**. Greenlab
having fewer guardrails never touches any of them.

1. **Production secrets masked to `/dev/null` in every Greenlab seat.** Not
   read-only — masked, so a byte count returns zero under every spelling. This
   is the existing `MASK_FILES` / secret-glob sweep, with its glob extended to
   the production civilization's `.env*` across every customer repo on the disk,
   not just Greenlab's own tree. The production civ's `civilization.json` and
   this planning folder's real-secret neighbours are included.
2. **Production repositories bound read-only or absent** in every Greenlab seat.
   The cross-fort write refusal is already a measured property of the current
   masks (core memory: `touch` fails in `/home/justin/dev/ForgeOs` and
   `/home/justin/dev/longburn` from a masked Manyhalls Mayor). Greenlab extends
   it so a Greenlab Forge cannot even *read* a customer repo it has no business
   in.
3. **`~/.ssh`, `~/.aws` masked; the production `~/.codex` / `~/.claude`
   credentials invisible.** Greenlab uses a **separate credential set** the
   production civ never sees, and the production creds a Greenlab seat never
   sees. A greenfield experiment must be unable to push with a production key or
   spend against a production billing account. This is the effect gateway's job
   (04, and the founder-gateway in 05 Phase 4): it holds Greenlab's own outbound
   credentials, and the reasoning seats hold none.
4. **Cross-civilization launch refusal.** A Greenlab seat is kernel-refused from
   launching a production seat and vice versa. This is the existing `FORT_MASKED`
   marker plus registry-scoping: a masked seat aborts at preflight, and the two
   registries (`~/.claude/civilization.json` vs `~/.claude/greenlab.json`) name
   disjoint fort sets. The `fort-init` factory already reads `FORT_REGISTRY`;
   the enforcement is that a Greenlab launcher resolves only the Greenlab
   registry and a production launcher only the production one.
5. **Host-executed scripts stay kernel read-only to every seat.** A sandbox is
   only as strong as the script that builds it. Greenlab's launchers, its
   `seat-sandbox.sh`, its `.git/config` and hooks are read-only to every Greenlab
   seat exactly as they are in production. Fewer guardrails on the *work* never
   means a seat can edit the machinery that sandboxes it.

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

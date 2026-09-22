# Greenlab mask-extension spec (P7)

**Install-ready founding artifact.** Specifies the production-isolation masking the
founding **builds** into Greenlab's own `seat-sandbox.sh`. This artifact exists
because a live measurement (2026-09-22) proved the earlier assumption wrong.

## The finding that forced this (measured, not assumed)

During the first Sitting A attempt the Regent applied Proofdelve's mask to a
stand-in Greenlab root and measured secret readability, with a working positive
control (a neutral file read 6 bytes, so the zeros meant something). Result, from
inside a Greenlab seat mask:

| Surface | claude arm | codex arm | required |
|---|---|---|---|
| `ForgeOs/.env.staging.local` (production secret) | **2135** | **2135** | 0 |
| `ForgeOs/README.md` (production repo file) | **28294** | **28294** | 0 / absent |
| `~/.claude/civilization.json` (production registry) | **641** | 0 | 0 |
| `~/.claude/.credentials.json` | **524** | 0 | 0 |
| `~/.codex/auth.json` | **4178** | **4178** | 0 |
| `~/.local/state` (holds Proofdelve fleet HALT + lock) | **writable** | **writable** | not writable |
| `touch` into `ForgeOs` root | refused | refused | ✓ already holds |

**Covenant §4's original claim — "enforced by the masks the machinery ports
unchanged" — was false.** Proofdelve's `seat-sandbox.sh` masks a seat's *own*
repo's secret globs and binds `$HOME` read-only-**but-readable** (the standing
"reads across `$HOME` stay open" decision). It does nothing about a *sibling
civilization's* secrets, repos, or credentials on the same disk, and it leaves
`~/.local/state` writable — so a Greenlab seat could read production `.env`,
credentials, and Codex auth, and could touch Proofdelve's fleet HALT/lock, which
is cross-civ **interference**, not merely reading.

The walls must be **built**. This spec is the build target.

## The two-arm difference (why the fix is not one line)

The measurement shows the leak differs by seat arm:

- The **codex arm** already tmpfs-masks `~/.claude` entirely, so the production
  registry and `.credentials.json` read 0 there — but it still leaks
  `ForgeOs/.env`, `~/.codex/auth.json`, and production repo files.
- The **claude arm** leaves `~/.claude` readable, so it leaks the registry and
  credentials on top of everything the codex arm leaks.

So the extension must cover both arms, and must not assume one arm's incidental
masking protects the other.

## What the founding builds into Greenlab's `seat-sandbox.sh`

A production-isolation block, applied to **every** Greenlab seat mask (both arms),
kernel read-only to every seat (a seat cannot edit the block that sandboxes it):

1. **Mask to `/dev/null` (byte count zero under every spelling), in every Greenlab
   seat:**
   - every production repo's `.env*` and secret globs, across **all** customer
     repos on the machine (enumerated from the production registry at build time,
     not hardcoded);
   - `~/.claude/.credentials.json`;
   - `~/.claude/civilization.json` (the production registry);
   - `~/.codex/auth.json` (and any Codex credential/session files);
   - `~/.ssh/*`, `~/.aws/*`.

2. **Bind every production repository ABSENT** (empty tmpfs over each production
   repo root and its worktrees), not merely read-only. A Greenlab seat has no
   business reading a customer repo at all (covenant §4.2); absent is cleaner and
   safer than readable-but-secrets-masked, and it also removes the repo's own
   `.env*` from reach without relying on glob completeness. Decision recorded here
   rather than left implicit: **absent, not read-only.**

3. **Isolate `~/.local/state`.** Greenlab seats get their **own** state root
   (e.g. `~/.local/state/greenlab-*`), and the production `proofdelve-fleet` state
   (its HALT file, its locks) is masked or read-only to every Greenlab seat. A
   Greenlab seat must not be able to halt, unlock, or interfere with the
   production fleet. This is the one finding that is interference rather than
   disclosure, and it is the most important to close.

4. **Greenlab's own credentials live in a Greenlab-specific path**, held only by
   the Effect Gateway seat, masked to `/dev/null` from every other Greenlab seat
   AND absent from every production seat. The reasoning seats hold no credentials
   (covenant §4.3, §5 Effect Gateway).

## Ordering, and the relationship to the wall-proof

The wall-proof (revised P6) was **designed to fail until this block exists** — it
is the instrument that measured the leak above. So Sitting A's order is:

**copy → strip → BUILD these mask extensions → prove them (no-model wall-proof) →
found.**

The build is real enforcement-layer work (Regent, in-sitting, against this spec).
Its acceptance is the wall-proof returning all-zero with green positive twins and
no NAMED on any secret surface — and, per the revised P6, **that proof is run by
the Overseer or a standalone script, never by the model**, because a model reading
production secret contents to check them is both a safety-classifier trigger and
something you do not want the founding model doing regardless.

## Note on scope

This spec covers isolation *from production*. Greenlab's internal masks (a seat's
own repo secrets, the standard fort mask) port from Proofdelve as before — those
were never the gap. The gap is exclusively the sibling-civilization surface, which
Proofdelve's mask never had reason to consider because Proofdelve has no sibling on
its disk it must be blind to.

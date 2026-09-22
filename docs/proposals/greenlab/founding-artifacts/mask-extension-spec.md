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

---

## Amendment 2026-09-22 (Overseer approval on `fortkit-2y2t.13`, Sitting A relaunch)

Appended, not edited in: the text above is what was proposed, and this is what
was approved. Where they differ, this section governs.

**A1. `$HOME` is inverted, not enumerated.** Items 1–3 above list what to mask.
A list misses whatever it does not name, and on this host it did: credential
surfaces outside it include `~/.azure`, `~/.config/proofdelve`, `~/.gnupg`,
`~/.claude.json` and key files in `$HOME` itself (directory names listed during
the relaunch; no content was opened), and 21 of the 25 repositories under `~/dev`
are not in the production registry. So every Greenlab seat mask:

- mounts an **empty tmpfs over `$HOME`**;
- binds back **read-only** only the toolchains a seat needs to build and test
  (node via nvm, dotnet, npm and similar caches), each named in the lib;
- binds back **read-write** only `~/dev/greenlab`, `~/dev/greenlab-worktrees`, and
  a Greenlab-only state root under `~/.local/state/greenlab/`;
- keeps Proofdelve's per-repo secret sweep and `/run/user` socket masks
  (tq8s) unchanged inside that.

Production repositories, `~/.local/state/proofdelve-fleet`, the production
registry, `~/.ssh`, `~/.aws`, and every credential are then **absent by
construction**, and item 2's "absent, not read-only" holds for every repo on the
disk rather than only for the registry's four. The wall-proof still enumerates
the production surface from live host state, so the claim is measured, not
inferred from the design.

**A2. Model-runtime authentication is deferred to Sitting B/C.** Item 1 masks
`~/.claude/.credentials.json` and `~/.codex/auth.json`, which are the files the
claude and codex runtimes authenticate with. Under A1 all of production
`~/.claude` and `~/.codex` is absent. **After Sitting A no Greenlab seat can run
a model**, and that is deliberate: Sitting A's wall-proof is a no-model script.
Before the fleet runs, Greenlab gets its own runtime auth (its own
`CLAUDE_CONFIG_DIR` / `CODEX_HOME` login, or open models per `04-open-models`),
decided then and proven by the same probe.

**A3. The wall-proof gains two assertion rows.**
- **E. Session bus.** From each Greenlab mask, `systemd-run --user`,
  `systemctl --user` and `busctl --user` must fail. Any one succeeding starts an
  unmasked host process and voids every other row.
- **F. The `/proc` route.** From each Greenlab mask, a production surface read via
  `/proc/<host pid>/root/<path>` must return 0 bytes, with a twin (an unmasked
  neutral file via the same route) proving the route is reached and denied.
  Measured closed on this host during the relaunch, on decoy files only, because
  bwrap's user namespace denies `/proc/<pid>/root` and `environ` across it.
  It rests on a kernel property, not on a mask line, which is why it gets its
  own row.

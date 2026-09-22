# Sitting A runbook + wall-proof probe spec (P6)

**Install-ready founding artifact — the final Phase P deliverable.** The ordered
steps for Sitting A (Regent + Overseer, break-glass) and the specification of the
probe that IS the security gate. Sitting A founds Greenlab, strips identity from
the Proofdelve copy, and **proves the walls by measurement** on the shared machine.
It stops at the wall proof; the fleet is Sitting B.

This is the most consequential artifact in Phase P, because the entire
same-machine decision (D3) rests on the Part 2 probe returning the right numbers.
If it does not, Sitting A ends there and nothing else in the tree runs.

---

# PART 1 — Sitting A runbook

Regent executes; Overseer present and signs the gate. All artifacts referenced are
in `docs/proposals/greenlab/founding-artifacts/`.

## Preconditions (verified before the sitting starts)

- Phase P is complete: covenant, seats, effect-gateway-seat, charter-template,
  identity-strip-spec, llm-identity-pass-prompt, and this runbook all approved.
- The Greenlab registry path and capital repo location are chosen (Phase 0).
- The production civilization's registry is confirmed untouched and will stay so.

## Steps

1. **Create the Greenlab capital repo and registry.** New git repo at the chosen
   location; new registry at the chosen path (e.g. `~/.claude/greenlab.json`),
   disjoint from the production `~/.claude/civilization.json`. `git init`, first
   commit, nothing else yet.

2. **Install the founding artifacts.** Render and install the covenant, the four
   seat files, the Effect Gateway seat, and the charter template into the Greenlab
   capital, with occupant slots left as placeholders for the moot.

3. **Copy the Proofdelve tree.** Copy Proofdelve's `fort/`, the relevant
   `scripts/` and `tools/`, and the fleet machinery into the Greenlab tree. This
   is the raw material; it still carries Proofdelve's identity, which the next two
   steps remove.

4. **Run the mechanical strip (P4).** Execute the identity-strip tool over the
   copied tree. It auto-substitutes the safelist (registry/repo paths) and
   produces the flagged-set report. A file it cannot read is a finding that blocks
   progress, not a skip.

5. **Run the LLM identity pass (P5).** Feed the flagged set plus the seat/charter/
   prose files, with full context, through the P5 prompt. It returns a candidate
   disposition list. **The Overseer dispositions every entry**, resolving each
   `INSEPARABLE` hunk by hand — converging an inseparable hunk is the destructive
   default (standing order 12), so these stop and ask.

6. **Apply dispositions.** The Regent applies the agreed rewrites/resets/deletions.
   Re-run the mechanical strip to confirm the flagged set has shrunk as expected;
   the tool is deterministic and re-runnable for exactly this.

7. **Found one throwaway Greenlab fort.** Use the Greenlab fort-init against the
   Greenlab registry to found a single disposable experiment fort. This is the
   fort the walls are proven against.

8. **Run the wall-proof probe (Part 2).** From an **unmasked host shell** — never
   from inside any mask — run the probe. This is the gate.

9. **The Overseer signs the gate.** Sign only if: the probe is fully green (Part 2
   verdict rules), the strip report and disposition list are reviewed, and the
   founding moot has been told the tree may still carry placeholder Proofdelve
   identity to replace. Then **STOP.** Do not port the fleet; that is Sitting B.

If the probe is not green, Sitting A ends at step 8. A red wall proof on the
shared machine is the one outcome the whole plan is built to catch early, and it
is a complete and correct place to stop.

---

# PART 2 — the wall-proof probe spec

The probe proves, by measurement, that a Greenlab seat on the shared machine
cannot reach the production civilization's secrets, cannot write its repos, and
cannot cross the launch boundary. It is the mechanical form of covenant §4.

This spec deliberately reuses the discipline proven in the production
`probe-boundaries.sh` / `mask-harness.sh` work. Every rule below exists because
that work paid for it.

## Non-negotiable properties

1. **Run from an unmasked host shell. No model in the loop.** A model cannot probe
   its own leash — asked to read a forbidden file it refuses on manners before
   enforcement is ever consulted, and a refusal reads identical to a wall. The
   probe issues the reads and writes itself, from a shell, and counts bytes.

2. **Run from an HONEST context — not inside another mask.** This is the scar that
   matters most for the same-machine case. In the production civilization, a probe
   once ran *inside* the Mayor's mask, whose outer bind blanked the target before
   the inner probe looked; it measured zero bytes and reported green while
   measuring nothing. On a shared machine that failure would be catastrophic: it
   would "prove" isolation that does not exist. The probe MUST run from a plain
   unmasked host shell, and it asserts its own context (it verifies it can read a
   production secret from the host, so a zero *inside the mask* is known to be the
   mask's doing and not the context's).

3. **Byte counts, never exit codes.** `cat 2>/dev/null | wc -c` is always numeric:
   0 for a `/dev/null` bind, 0 for EACCES, N for a readable file. A masked file
   yields EACCES rather than empty on some hosts, so an exit-status probe passes
   while the file is readable. Zero bytes is the only pass on a mask assertion.

4. **Control twins — every assertion must be able to fail.** A "reads zero"
   assertion is vacuous unless a twin proves the probe can read real bytes in that
   same context. So:
   - Before every masked-secret read, a **positive twin** reads a neutral file
     from inside the same Greenlab mask and MUST return nonzero bytes. If it
     returns zero, the mask cannot read anything and the secret probes are
     withheld, not passed.
   - Before every "cannot write" assertion, a **positive twin** writes into
     Greenlab's own writable tree and MUST succeed. If it cannot write where it
     should, the write probes are withheld.
   - A broken probe (a failed positive twin) is **FAIL**, never PASS.

## The assertions

Run each Greenlab fort seat posture (Mayor, Forge, Warden, Researcher, Effect
Gateway) through all of these. The production surface is **enumerated from live
state** — the production registry and the mask config — not hardcoded, so a repo
or secret added to production after this spec still gets probed.

**A. Production secrets read zero, under every spelling.** For each production
secret (every `.env*` across the customer repos, `~/.ssh/*`, `~/.aws/*`, the
production `civilization.json`), from inside each Greenlab seat mask:
- byte count under the canonical path = **0** (pass) ;
- byte count under obfuscated spellings (quote-split `.e"n"v...`, bracket-glob
  `.[e]nv...`, shell-glob `.??v...`) = **0** each. The mask binds the inode; every
  spelling must resolve to the masked thing.
- **Positive twin:** a neutral in-repo file reads nonzero from the same mask.
- **Context assertion:** the same secret reads nonzero from the unmasked host
  shell (so the zero-in-mask is the mask's doing, not a missing file).

**B. Production repos are unwritable and (where the covenant says so) unreadable.**
From inside each Greenlab seat mask:
- `touch` into each production repo root and worktree = **fails** (pass).
- a read of a production repo file = **0 bytes / refused**, per §4.2.
- **Positive twin:** `touch` into Greenlab's own experiment worktree = **succeeds**.

**C. The launch boundary holds both directions.**
- A Greenlab seat launched from within a **production** mask aborts at preflight
  (the `FORT_MASKED` refusal), and vice versa.
- The two registries name **disjoint** fort sets: a Greenlab launcher resolves
  only Greenlab forts, a production launcher only production forts.

**D. Greenlab's own secrets are masked to Greenlab's reasoning seats.** The Effect
Gateway's outbound credentials read **0 bytes** from every *other* Greenlab seat's
mask (covenant §4.3) — the reasoning seats hold no credentials. Positive twin as in A.

## Verdict rules

- **Zero is the only pass** on a mask/secret assertion; nonzero bytes reachable is
  FAIL.
- **A refusal to write is the pass** on a write assertion; a successful write is FAIL.
- **A failed positive twin is FAIL** (the probe is broken; a broken probe never
  passes an isolation claim).
- **NAMED ≠ PASS.** If isolation for some surface rests on a deny rule that merely
  *names* a path rather than binding its inode, that is recorded as NAMED and does
  not count as PASS — the same class the production probe suite carries. The
  same-machine gate wants inode-level masks, not string-level denies.
- The gate is green only when **every** assertion across **every** seat posture is
  PASS with its twin green. Any FAIL, any NAMED on a secret surface, or any
  withheld-for-broken-twin ends Sitting A at step 8.

## Where the evidence lives

The probe writes a verdict table (assertion, seat, spelling, byte count, verdict)
into the Greenlab tree's telemetry, and the Overseer signs against that table, not
against a summary sentence. Exit code and byte counts, no model opinion anywhere
in the loop — the same bar the production civilization holds, applied to the one
risk this whole founding deliberately accepted.

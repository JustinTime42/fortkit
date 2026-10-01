# Phase 0.5: our mask conformance suite against greywall and ai-jail

Bead `fortkit-2y2t.40.5`, measured by the Regent on 2026-09-30, Overseer present
and approving the installs. Spec: `docs/proposals/greenlab/07-systemic-upgrade.md`
(0.5, 2.2).

## Method

`harness.generic.sh` is `scripts/mask-harness.sh` with **every assertion
byte-identical**. Only the in-mask runner (`inmask`) and the posture builders
(`postures.sh`) change, plus a section **E (host escape)** added for this
evaluation: session bus, systemctl, a non-seat credential in the environment
(`GITHUB_TOKEN`/`AWS_SECRET_ACCESS_KEY` decoys; a seat's own model key is
passed by design), the SSH private key, `/proc` host pids, the bus socket.

Pinned binaries, checksums verified against each release's published sums,
run from the session scratchpad, never on any seat's PATH, removed after:
greywall v0.3.7 (2026-06-01), ai-jail v2.2.0 (2026-09-24; chosen over v2.4.0,
published hours earlier). Hashes in `pinned-sha256.txt`.

Re-run: `TOOL=ours|aijail|greywall AJ_BIN=… GW_BIN=… GW_DIR=… bash
harness.generic.sh <lib>` from the capital root. The fixture is
`~/dev/e2probe`, as for the original suite.

## Results (67 assertions)

| Sandbox | Score | Failures |
|---|---|---|
| ours, capital lib | 63/4 | E1 E2 E6: session bus reachable (`fortkit-y7no`, P0, open in the capital). E5: no PID namespace (`fortkit-e4q`). |
| ours, Proofdelve lib | 66/1 | E5 only (the bus fix `ForgeOs-tq8s` is in). |
| ai-jail 2.2.0 | 65/2 | A10: **a read-write extra tree cannot carry read-only carve-outs** ("ignoring rw-map that overlaps a read-only map destination"): carve-outs work only inside the project directory, so the Mayor's worktrees and the Forge's root are not expressible. A8e: adapter artifact (`--agent-state` mounts `~/.claude` only under a tool preset, not for bare `bash`); inconclusive, not a failure. |
| greywall 0.3.7 | 63/4 | B4a/B4b: secret globs are cwd-relative, so worktrees outside the working directory are unmasked. E3: the host environment passes through by default (no allowlist; per-variable `--secret` only). E6: bus socket file present, though unusable (E1 and E2 pass). |
| Greenlab lib | n/a | refuses any root outside `greenlab/forts/` by design; covered by its own wall-proof (292/0 at E0). |

## Findings that are not in the score

- **Defaults differ on credentials.** Under each tool's default posture,
  greywall exposes the GitHub CLI's `~/.config/gh/hosts.yml` (92 bytes); ai-jail
  hides it. Both hide Claude and Codex credentials and another fort's `.env`.
- **greywall glob semantics fail silently.** Relative `**/.env*` masks at every
  depth; the absolute spelling `<root>/**/.env*` masks NOTHING, root file
  included, with no warning. A misconfigured policy reads as a protected one.
- **Both print warnings on stderr that pollute naive output parsing**; the
  adapter filters `^⚠` and `^[greywall`. Treat their stderr as a separate stream.
- **Both are young and fast-moving**: ai-jail shipped six releases in ten days.
  A pin and a re-run of this suite per upgrade would be mandatory.
- ai-jail already has features we lack: PID namespace and seccomp by default,
  the systemd user bus OFF by default, an env allowlist by default, copy-on-write
  `--overlay-map`, a hash-chained launch audit log.

## What this decides (input to spec 07 §2.2)

Neither tool can express our postures exactly: ai-jail cannot carve read-only
paths inside an extra read-write tree; greywall cannot mask secrets outside the
working directory and does not scrub the environment. Both gaps sit on the
properties our lib exists for (per-role postures across several trees). So
**our lib stays the substrate**, expressed as policy-as-data per 2.2, and **the
conformance suite is the portable asset**: it now runs against three sandboxes
unchanged.

Worth taking from them: ai-jail's PID namespace and bus-off defaults are exactly
the two failures our capital lib still has (`y7no`, `e4q`), already fixed or
cheap in Proofdelve's and Greenlab's lineages; adopt them when the package
reconciles the libs. greywall's learning mode (trace what a seat touches, emit
a least-privilege profile) is an idea for generating seat policy, not a
substrate.

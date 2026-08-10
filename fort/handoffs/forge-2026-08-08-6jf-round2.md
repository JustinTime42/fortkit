# Handoff: Forge 2026-08-08T02:16:00-08:00

Model: GPT-5 Codex (orchestrated Forge session; not launched through `forge.sh`)

## State of work

- `fortkit-6jf` remains IN_PROGRESS and was not closed or otherwise mutated.
- Round two restores Forge write access to `~/.codex` through the shared
  builder's enumerated grants, while its later RO-path pass still overlays
  `~/.codex/config.toml` when that file exists.
- Forge now supplies its worktree's `.claude`, `fort/charter.md`, `fort/seats`,
  and `fort/profiles` as extra read-only paths. These mounts occur after the
  worktree-wide read/write grant, as required by ForgeOs-01l.
- The live files and fort-init templates are mirrored. The launcher comment now
  accurately says that `SSH_AUTH_SOCK` can be present but names a masked socket.

## Verified facts

- From `/home/justin/dev/fortkit-worktrees/6jf`, after sourcing
  `fort/scripts/lib/seat-sandbox.sh` and calling `build_mask codex` with the
  same Forge arguments, these exact probes each returned `1`:
  `bwrap "${mask[@]}" -- test -w fort/charter.md`,
  `bwrap "${mask[@]}" -- test -w fort/seats`, and
  `bwrap "${mask[@]}" -- test -w fort/profiles`.
- The paired runtime probe `bwrap "${mask[@]}" -- test -w "$HOME/.codex"`
  returned `0`, confirming the `RW_PATHS` grant is effective.
- This host has no `~/.codex/config.toml`, so the builder's existing
  `[ -e "$p" ]` guard means there was no config file available for a direct
  read-only mount probe. The mount order is explicit in
  `fort/scripts/lib/seat-sandbox.sh`: the `.codex` RW grant is installed before
  `RO_PATHS` adds `config.toml`.
- `bash -n`, scoped ShellCheck, `git diff --check`, and exact live/template
  library comparison passed.
- Effective mask summary: filesystem scope is read-only `$HOME` with enumerated
  writable grants for the repo, all repo worktrees, Codex runtime state,
  caches, and `/tmp`; Forge re-overlays its local constitution and `.claude`
  paths read-only; secrets and the SSH-agent socket are dev-null masked;
  credential/config directories are tmpfs masked; `.beads` hooks are rebound
  read-only; and a user-owned SSH config is supplied under a tmpfs `/etc/ssh`.

## Next actions

1. Run `CI=1 fort/scripts/verify.sh --no-emit` and review the scoped commit.
2. The next actual `forge.sh` launch should exercise token refresh with a real
   `~/.codex/config.toml`; the worktree constitution probe above is the
   standing-order-5 assertion for the mechanical boundary.
3. Do not remove the dated `fort/remember.md` caveat until review accepts the
   worktree-scoped probe.

## Open risks / questions

- The intended consequence is that `git checkout` or `git stash` from a Forge
  worktree will fail if it needs to modify its `fort/charter.md`, `fort/seats`,
  or `fort/profiles` paths. That is the authorized gate-1 boundary.
- A direct `config.toml` read-only probe requires a host where that optional
  file exists; this workspace does not have one, and no host configuration was
  created merely for testing.

## Failed attempts

- An initial full-file launcher diff treated expected template-specific actor
  and prompt text as a mismatch, so it did not reach the probe command. Scoped
  syntax, mirror, and bubblewrap checks were then run independently.

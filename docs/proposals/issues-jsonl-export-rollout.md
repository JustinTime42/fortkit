# Canonical Beads JSONL export rollout

**Decision (Overseer, 2026-08-07):** `.beads/issues.jsonl` is the canonical
cross-fort state artifact. Beads' Dolt database remains the local operational
store; the JSONL file is a read-only projection and must never be imported or
edited as ordinary workflow.

## Freshness mechanism

Beads has a built-in JSONL auto-exporter in `.beads/config.yaml`. Every fort
uses the following configuration:

```yaml
export:
  auto: true
  path: issues.jsonl
  interval: 60s
  git-add: false
```

`auto` exports after Beads writes, with `interval` as a throttle. `git-add`
stays false: export freshness is automatic, while tracking stays subject to
the fort's path-scoped staging rule. `fort-init` configures these keys and
runs `bd export -o .beads/issues.jsonl`, so a newly founded fort has its first
snapshot before its founding commit.

When a mutation must be represented immediately (for example, before a
review, handoff, or commit), run:

```bash
bd export -o .beads/issues.jsonl
```

This uses no `.beads/hooks` directory. The existing seat sandboxes discover
and bind every hooks directory beneath `.beads` read-only because those hooks
can execute later on the host. The exporter is a supported `bd` configuration
path, executes within the normal `bd` write flow, and leaves that masking
boundary intact.

## Per-fort rollout

This is a `fortkit-or2` backport cycle after the Manyhalls change is reviewed
and merged. The Overseer or designated backport operator must, for each
registered existing fort:

1. Set `export.auto=true`, `export.path=issues.jsonl`, `export.interval=60s`,
   and `export.git-add=false` with `bd config set`.
2. Run `bd export -o .beads/issues.jsonl`; confirm the file is nonempty and
   parses as newline-delimited JSON.
3. Stage only `.beads/config.yaml` and `.beads/issues.jsonl`, commit under
   that fort's normal review gate, and verify the committed export contains
   its expected current bead IDs.
4. Confirm no `.beads/hooks` path was introduced or made writable; the
   existing hooks masking remains the relevant host-RCE control.
5. Record the applied forts, commit IDs, and post-propagation evidence in
   `fortkit-or2` before marking the cycle complete.

The factory portion is this `bin/fort-init` change: its creation-time export
must be verified by founding a scratch fort and observing both tracked files.

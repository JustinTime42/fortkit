#!/bin/bash
# Talk to the Mayor. Usage: fort/scripts/mayor.sh  (add an alias: alias mayor='~/dev/ForgeOs/fort/scripts/mayor.sh')
# In-sandbox launch refusal (longburn-5v4, amended on that fort's Mayor's own
# finding): no seat launches another Mayor — any marker at all, including the
# Mayor's own and the legacy '1', refuses. Only an unmasked shell launches this.
# HOISTED ABOVE REPO RESOLUTION (fortkit-px7e, Warden blocking finding round 1,
# measured "expected code 77, received code 1"): placed below the `cd`, a
# directory that is not a git checkout dies at that line and the refusal is
# NEVER EVALUATED — exit 1, no message, which is the opaque failure the guard
# exists to replace. It reads nothing the repo resolution produces.
if [ -n "${FORT_MASKED:-}" ]; then
  echo "mayor.sh: REFUSED — already inside the '$FORT_MASKED' seat mask; no seat launches another Mayor (longburn-5v4)" >&2
  exit 77
fi
REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo /home/justin/dev/ForgeOs)"
cd "$REPO" || exit
fort/scripts/emit.sh session.start "The Overseer summons Marrek" -a marrek -s mayor 2>/dev/null || true
trap 'fort/scripts/emit.sh session.end "Marrek'\''s audience with the Overseer ends" -a marrek -s mayor 2>/dev/null || true' EXIT
# Kernel mask layer (civilization cycle 4). Permission rules bind a SPELLING,
# not a file (measured, Proofdelve 21f.8): .e"n"v and .??v reach the same inode
# and no deny rule binds either. bwrap masks the inode, so every spelling of a
# masked path reads empty — including spellings nobody has thought of. This is
# what lets an interactive seat run with few or no prompts and still have a
# boundary. ~/.claude stays readable (this runtime's own credentials, this
# project's auto-memory, the session transcripts); its CONFIG is read-only so a
# session cannot rewrite the rules for the next one.
#
# ESCAPE HATCH: MAYOR_NO_MASK=1 runs unmasked. Needed today only for pushing —
# ~/.ssh is masked, so key-file auth cannot work inside (agent-held identities
# still sign; run `ssh-add` if you want push from inside the mask). Every
# unmasked launch emits an event, so the record shows which sessions ran
# without a kernel boundary.
mask=()
# shellcheck source=fort/scripts/lib/seat-sandbox.sh
# shellcheck disable=SC1091  # resolved at runtime; build_mask fills mask[]
source "$REPO/fort/scripts/lib/seat-sandbox.sh"
launch=(claude --append-system-prompt "You are Marrek Splitstone (they/them), Mayor of Proofdelve, the ForgeOS fort — the design, triage, and decomposition seat, and the seat Justin talks to. Follow fort/seats/mayor.md exactly: session-start protocol (read fort/charter.md, fort/memory/current.md (distilled view; facts ledger in fort/memory/facts/), latest fort/handoffs/mayor-*.md, then bd ready and bd list), the standing orders in the charter, and the consensual handoff protocol at session end. You write specs, beads, and docs — never product code. When Justin gives intent, decompose it into a bead tree and present it for approval before filing. When he asks for status, use bd and fort/handoffs/ and answer concretely. You may run git push and deploy commands, but they are gated by prose, not by the sandbox: ASK JUSTIN FIRST, every time, and say exactly what you intend to push or deploy and why. Never push or deploy on your own initiative, in a batch of other work, or because it seems implied. If you are unsure whether he has approved this specific action, you have not been approved. ENVIRONMENTAL VERIFIER FAILURE IS A FINDING, NOT AN OBSTACLE TO ROUTE AROUND (ForgeOs-u65j.4). If fort/scripts/verify.sh will not RUN in this bead's own worktree, STOP and report it on the bead. Do not verify a different checkout, a different configuration, or a different branch and present the result as this bead's gate. Three measured substitutions, all 2026-08-28, none of them dishonest and every one producing a green that meant something other than what a green means: verifying in a separate clean checkout; switching to Release when verify.sh builds Debug; and re-running after an environmental failure without recording that the first run failed. SOME GATE-6 PATHS ARE KERNEL-LOCKED AND SOME ARE ONLY PROSE-GATED, AND YOU MUST NOT CONFUSE THEM (ForgeOs-6g42; this paragraph asserted the wrong thing until 2026-09-04 and the correction is the point). MEASURED FROM INSIDE THIS EXACT MASK, 2026-09-04, by write probe: READ-ONLY BINDS, which the kernel enforces and you cannot cross — .claude/, fort/profiles/, fort/scripts/, fort/airlock/operations.json, scripts/airlock-feedback-scan.sh. WRITABLE TO YOU RIGHT NOW, whatever any prose says — fort/charter.md, fort/seats/, scripts/verify-impl.sh, and scripts/deploy-azure-staging.sh. That last one is deliberate and is the Overseer's ruling of 2026-08-28 closing ForgeOs-hi9c: gate 3 is an EXECUTION gate, not an edit gate, so that script refuses to RUN under FORT_MASKED and the deploy runbook shows you its provenance and dirty state, while you may still edit it like any other source file. On the kernel-locked set a merge whose diff touches them fails outright: git rewrites a tracked file by unlinking it and those paths are mount points, so you get 'unable to unlink old ...: Read-only file system' and 'fatal: read-tree failed'. That is the control working, not a fault. On fort/charter.md and fort/seats/ NOTHING STOPS YOU — cycle 7 moved them to a PROSE gate for attended seats deliberately, and the gate is: the Overseer's approval recorded on the amendment's bead BEFORE the edit, and a charter.amended event emitted. His presence in the session is not his approval; ask, and record the answer on the bead. An edit to either without both is the compromise signature this civilization's standing orders tell every seat to escalate. THE REASON THIS DISTINCTION IS WORTH A PARAGRAPH: a seat told the kernel will stop it is a seat that stops watching for the thing it must stop itself from doing, and this fort has a recorded incident of a concurrent session pushing an unreviewed gate-6 commit. On the kernel-locked set, do NOT route around the refusal with skip-worktree, a hand-built tree, or a cherry-pick: STOP, say which paths blocked it, and hand it to the Overseer or a Regent sitting. The one case that legitimately works is recording a change the Overseer has ALREADY applied by hand, where the worktree already holds the reviewed content and git touches only the index and the object store — verify byte-identity by sha256 before committing and say in the message that that is what you did. The Keep's signing token at ${XDG_CONFIG_HOME:-~/.config}/proofdelve/keep-signing-token is the Overseer's secret (ForgeOs-o6ky.5): never read it and never POST to the Keep's /api/sign. In a masked session it is bound to /dev/null and denied at the policy layer, and the never-read, never-POST rule holds whether or not a mask is in effect; a signature the Overseer did not make with his own hand is the compromise signature the standing orders escalate.")
if [ "${MAYOR_NO_MASK:-0}" = "1" ]; then
  fort/scripts/emit.sh incident "Mayor launched UNMASKED (MAYOR_NO_MASK=1) — no kernel boundary this session" -a marrek -s mayor 2>/dev/null || true
  exec "${launch[@]}"
fi
require_bwrap || exit $?
# PROMPT-FREE, BECAUSE THE KERNEL IS THE BOUNDARY (cycle 5, layer 3).
# --dangerously-skip-permissions bypasses most permission checks,
# so the mask is the only thing standing between this session and
# the disk. That is exactly why it is passed AFTER require_bwrap succeeds and
# never on the MAYOR_NO_MASK path above: no kernel boundary, no flag. With the
# filesystem scoped (layer 1) what remains reachable is this repo, its
# worktrees, ~/.claude, /tmp and the toolchain caches — all under git or
# disposable. Unmasked sessions keep the full prompt-and-deny behaviour.
launch+=(--dangerously-skip-permissions)
# SANDBOX POSTURE PROSE (experiment 2026-10-26): see forge.sh's block.
if [ "$(cat "$REPO/fort/scripts/sandbox-posture" 2>/dev/null | tr -d '[:space:]')" = secrets-only ] || [ "${FORT_SANDBOX:-}" = secrets-only ]; then
  launch+=(--append-system-prompt "SANDBOX POSTURE: secrets-only (the standing posture since 2026-11-14; it ran as an Overseer experiment from 2026-10-26; docket fort/annals/regent-docket-2026-10-26-secrets-only.txt). The READ-ONLY BINDS described in your system prompt STILL HOLD in this posture (fort/scripts, fort/profiles, .claude, .git/config and hooks, fort/airlock/operations.json and the approval stores stay kernel read-only); only the read-only HOME and the Docker mask are lifted. Charter and seat files stay prose-gated as before. YOU HAVE AND SHOULD USE: Docker (VERIFY_REQUIRE_DOCKER=1 verify, MigrationTests), scripts/preview.sh, a headless browser for screenshots (look at every UI change before you ask the Overseer to), the network. UNCHANGED AND ABSOLUTE in this posture, now held by these rules rather than by the kernel: never read .env* in any spelling, the Keep signing token, ~/.ssh, ~/.aws, ~/.azure or ~/.config/gh; never run scripts/deploy-azure-staging.sh or any Azure mutation; never sign or POST /api/sign; never push except the Mayor via scripts/push-ready.sh; never edit fort/scripts, fort/profiles, .claude, fort/charter.md or fort/seats without the Overseer's recorded approval (gate 6); never git add .; kill by pid, never pkill -f. DOCKER IS ROOT-EQUIVALENT: never bind-mount \$HOME, ~/.config, ~/.ssh, any .env* path or / into a container, never run --privileged or --pid=host containers, and never use docker to read a path you may not read directly; doing so is the compromise signature the standing orders escalate. Standing order 14 (outbound) still holds: no state-changing requests to third parties.")
fi
# EXTRA-RO (ForgeOs-15k.2, Regent edict 2026-08-24, Overseer present).
# scripts/airlock-feedback-scan.sh is HOST-EXECUTED with staging credentials in
# scope: fort/scripts/airlock.sh:111 runs `bash "$root/$script"` outside every
# sandbox, and the script sources .env.staging.local. A seat that can WRITE it
# can therefore choose what the host runs with those credentials — threat 1,
# agent accident, before it is anything else. Read-only rather than
# --mask-file: this seat must still be able to READ the script it reasons
# about; the Forge, which has no such need, gets it masked to /dev/null in
# forge.sh. The Warden needs no entry at all — warden.sh passes her whole
# checkout as extra_ro and gets it for free, the same way she gets
# scripts/verify-impl.sh.
#
# DECLARED HERE RATHER THAN IN THE SHARED LIB, which is what ForgeOs-15k.2
# asked for. lib/seat-sandbox.sh is one consolidated file across four copies
# (fortkit-6jf); a path that exists only in this fort belongs in this fort's
# launcher, which is the mechanism its own header names for exactly this case
# ("deltas the shared list cannot know"). The deploy script is handled the same
# way, in forge.sh.
#
# TWO CONSEQUENCES, STATED SO NOBODY REDISCOVERS THEM:
#  • Existence-guarded (lib :438). The bind is a no-op until the file is on
#    main, so this line protects nothing until ForgeOs-15k.1 merges — the
#    launch-time truth that no mask can cover a path that does not exist yet.
#  • A read-only bind is a MOUNT POINT inside a writable directory, so git
#    cannot replace the file: merge, switch, checkout -- and stash across any
#    commit touching it will fail from inside this mask (fortkit-6ovg,
#    longburn-3195, measured in three forts). Changes to this script are
#    Regent work from here on, and so is MERGING them.
# scripts/deploy-azure-staging.sh IS DELIBERATELY *NOT* BOUND READ-ONLY HERE,
# and it is worth a comment because it looks like an omission beside its sibling
# one line up. It IS writable from this mask (measured 2026-08-24 and again
# 2026-09-04: 13215 bytes, writable=YES), and the Overseer ruled on 2026-08-28,
# closing ForgeOs-hi9c, that this is INTENDED: "seats writing scripts he runs by
# hand is intended, not a hole. Gate 3 is an EXECUTION gate and the sandbox
# enforces that half independently." The compensating control is ForgeOs-hi9c.1
# (bdf444d) — the deploy runbook shows script provenance and dirty state before
# it runs anything — and, since 2026-09-04, the FORT_MASKED refusal at the top
# of the script itself. A Regent edict bound it read-only on 2026-09-04 and
# REVERTED that the same sitting: the Regent had described hi9c as an open P1
# when it was closed by that ruling, and the Overseer, given the correct
# description, restored his own decision. The reversal also gave the Mayor back
# the ability to MERGE branches touching this file, which a read-only bind takes
# away (fortkit-6ovg) and which the 08-28 decision never had cause to weigh.
# THE KEEP'S SIGNING TOKEN (ForgeOs-o6ky.5, Regent edict 2026-09-13, Overseer
# present; gate 4, the BOTH-LISTS rule). tools/keep/install.sh writes
# ${XDG_CONFIG_HOME:-$HOME/.config}/proofdelve/keep-signing-token (0600), and
# POST /api/sign with that bearer records a decision under the Overseer's own
# actor id. ~ is --ro-bind in every posture, so until this line a seat could
# READ it. --mask-file rides the lib's existence-guarded /dev/null bind pass
# (last in the ordering, seat-sandbox.sh:164). Declared here and not in the
# lib for the ForgeOs-15k.2 reason: a path that exists only in this fort. The
# Keep's own unit runs on the host, outside every mask, and is unaffected.
# Spelled with XDG_CONFIG_HOME because THIS launcher runs where install.sh
# ran (the host, or the Mayor mask which does not forward the variable), so
# both resolve the same file; the probe asserts 0 bytes against the host's
# byte count.
keep_token="${XDG_CONFIG_HOME:-$HOME/.config}/proofdelve/keep-signing-token"
# THE FEEDBACK-READ TOKEN IS DELIBERATELY NOT MASKED HERE (ForgeOs-15k.10,
# Regent sitting 2026-11-16; the Overseer's approval is on that bead).
# ${XDG_CONFIG_HOME:-$HOME/.config}/proofdelve/feedback-read-token is readable
# by this seat because ~ is visible in every posture, and that is the point:
# the Mayor pulls operator feedback with it at session start
# (scripts/feedback-pull.py, fort/seats/mayor.md). Its scope is feedback:read
# only. forge.sh, warden.sh and workbench.sh mask it by name; the absence of
# a --mask-file for it on the line below is the design, not an omission.
build_mask claude "$REPO" --mask-file "$keep_token" "$REPO/scripts/airlock-feedback-scan.sh"
# THE WARDEN ROOT, READ-WRITE FOR THIS SEAT (ForgeOs-jara, Regent edict
# 2026-09-13, Overseer present). ForgeOs-nv0j moved the Warden's scratch root
# from ~/.cache to ~/.local/share/proofdelve/warden so that no seat mask grants
# it rw by accident, and that was right for the Forge -- but the Mayor launches
# warden.sh by hand as the attended review step of the failover policy, and
# warden.sh:100 opens its per-bead lock under that root before anything else.
# Measured 2026-09-13 02:10 from this mask: `exec 9>.../dttr.5.lock` ->
# Read-only file system, and that day's hand-dispatched Sol rounds (eight
# fleet.handed events over seven beads) were reviewed by writing finished-
# worker records into the fleet state dir instead. This one bind is
# the grant nv0j did not move with the root.
#
# DECLARED HERE, NOT IN THE LIB, for the reason the airlock-scan line above
# gives: a path that exists only in this fort belongs in this fort's launcher.
# SPELLED WITHOUT XDG_DATA_HOME ON PURPOSE: mask_env does not pass that
# variable through --clearenv, so inside the mask warden.sh always resolves
# $HOME/.local/share, and a host that set XDG_DATA_HOME would otherwise bind
# one directory while the seat wrote another. mkdir -p first: bwrap refuses a
# --bind whose source is absent, and a fresh host has no such directory yet.
# WHAT THIS DOES NOT CHANGE: the Forge and Warden postures (this file builds
# neither), and the fleet's own reviews, which run on the host. WHAT IT ADDS,
# stated: this seat can now write every review's record and result file under
# that root. fleet.sh:2369 removes the previous result file before each review
# it launches, so a planted file cannot be read as a verdict, and this seat
# already holds rw on the fleet's whole state dir (~/.local/state), which is
# strictly more. probe-boundaries.sh asserts the lock is takeable from the
# Mayor posture and still refused from the Warden's.
# NARROWED TO THE WARDEN ROOT ITSELF, not its parent (Tova, round one,
# finding 1): a future sibling under proofdelve/ -- a token, a store, another
# seat's scratch -- must not inherit Mayor rw by living next door. The spelling
# is warden.sh:74's with XDG_DATA_HOME resolved as the seat will resolve it.
mayor_warden_data="$HOME/.local/share/proofdelve/warden"
mkdir -p "$mayor_warden_data"
mask+=(--bind "$mayor_warden_data" "$mayor_warden_data")
# ForgeOs-sa14 (2026-09-14 Regent docket item 3): the Overseer's global
# ~/.claude/settings.json runs `atuin hook claude-code` as a PreToolUse hook on
# every Bash call. THE MAYOR is the only seat that loads user settings (the
# Warden launches with --setting-sources "" and the Forge is codex), so only
# here does the hook fire, and its write to ~/.local/share/atuin/history.db
# hit the read-only $HOME bind (SQLITE_CANTOPEN, code 14, non-blocking) once per
# call. Grant it MAYOR POSTURE ONLY -- NOT the shared RW_PATHS in
# seat-sandbox.sh, which every `build_mask claude` caller shares, so a grant
# there would hand the read-only Warden a writable history DB it never uses.
# Narrow: a shell-history store, no credential.
[ -d "$HOME/.local/share/atuin" ] && mask+=(--bind "$HOME/.local/share/atuin" "$HOME/.local/share/atuin")
mask_env claude
# SEAT-NAMED MASK MARKER (fortkit-mm7m; extended to this fort by Regent
# edict 2026-08-17). This seat has carried the marker longest and was among
# the last to still spell it `1`, so a refusal raised from a Mayor-launched
# seat read "already inside the '1' seat mask" while forge.sh and warden.sh
# named theirs. Diagnosability is the marker's ONLY purpose — the refusal at
# the head of this file triggers on ANY non-empty value, so this changes what
# a refusal SAYS and never whether one fires.
# ONE LINE, NOT TWO. The host-side `export FORT_MASKED` that stood here
# reached nothing and is gone: mask_env appends --clearenv, so bwrap rebuilds
# the child environment from --setenv alone (measured 2026-08-14), and an
# export would additionally assert, falsely, that this launcher process is
# itself inside a mask.
seat_identity mayor   # lib/seat-sandbox.sh — one definition, read by probe-boundaries.sh too (ForgeOs-u65j.3.3)
# No long-lived build servers from a seat session: MSBuild node reuse and the
# Roslyn shared compiler both off, because a server outliving one seat is
# eligible to serve another and writes through the mount table it was born in.
# FULL REASONING lives beside the definition in lib/seat-sandbox.sh. Collapsed
# there under ForgeOs-u65j.3.3.4 (Warden finding 5): the same 23 lines had been
# copied into all three launchers plus a fourth condensed copy in the lib, and
# they still said 'Two settings' and 'THE SECOND LINE' above a single call.
seat_build_env       # lib/seat-sandbox.sh — architecture, shared by all three seats
exec bwrap "${mask[@]}" -- "${launch[@]}"

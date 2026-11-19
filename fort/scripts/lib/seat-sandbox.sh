#!/bin/bash
# Shared kernel-mask builder for seat launchers. Source this, call build_mask,
# then run: bwrap "${mask[@]}" -- <your command>
#
# MODE IS 0644 AND THAT IS THE DECISION, NOT AN OVERSIGHT (fortkit-n3bk finding
# 7, decided by the E8 sitting 2026-08-13). This file is SOURCED, never executed:
# no caller invokes it as a program, so the executable bit would grant a way to
# run it that nothing needs. All three forts' copies measured -rw-r--r-- on
# 2026-08-13, so there is no single-file mode change to explain and the gate-1
# escalation class the finding invoked does not apply. The shebang is kept for
# editors and ShellCheck, which is why it looks executable and is not.
#
# WHY THIS EXISTS (Proofdelve 21f.3/21f.5/21f.8, civilization cycle 4):
# Permission rules in both harnesses match the TEXT of a command, so a deny
# rule binds a SPELLING, not a file — measured six-for-six against obfuscated
# path forms (.e"n"v, .[e]nv, .??v all reach the same inode, none bind a rule).
# bwrap masks the inode. Every spelling of a masked path, including ones nobody
# has thought of, reads empty. That is why the kernel layer is the boundary and
# the deny lists are convenience.
#
# A masked FILE reads as EMPTY-AND-SUCCESSFUL, not as an error; on SELinux hosts
# the /dev/null bind may instead yield EACCES. Probes must assert byte counts and
# accept either outcome — never trust an "access denied" narration from a model.
#
# Usage:  build_mask <seat-type> <repo-root> [--env-root <path>] [--rw-tree <path>]
#                    [--mask-file <path>] [--mask-ssh-auth-sock] [extra-ro-path ...]
#   seat-type: "codex" (Forge) or "claude" (Mayor, Warden)
#   --rw-tree: a SECOND writable checkout (a worktree). Grants it AND applies
#              every enforcement carve-out to it. See fortkit-1q9 below.
#   --mask-file: a caller-specific path to mask to /dev/null, joining MASK_FILES
#              so it is bound in the correct pass. For deltas the shared list
#              cannot know — Proofdelve's deploy scripts, which its charter gate 3
#              keeps out of every agent's hands, in both the root and the worktree
#              copy. An extra-ro-path would leave such a file READABLE; this makes
#              it read empty. Added by fortkit-52vf.10 for the forge.sh port,
#              deliberately as a parameter rather than a second copy of the logic.
#              TAKES A FILE, AND SILENTLY IGNORES A DIRECTORY (Warden finding 7
#              on fortkit-52vf.10): the bind site tests [ -e ] && [ ! -d ],
#              correctly — MASK_FILES also carries sockets, and `--ro-bind
#              /dev/null <dir>` ABORTS BWRAP so no seat launches anywhere — but
#              a caller passing a directory therefore gets no mask AND no
#              output. That is the same silent-gap class this file discloses at
#              length for the secret sweep below; pass directories as
#              extra-ro-paths, or add them to MASK_DIRS.
# Each seat type keeps its OWN runtime's credentials readable — masking them
# breaks the launch outright — and masks the other runtime's entirely.

# OUTPUT: sets the global array `mask` (consumers declare mask=() before sourcing).
# shellcheck disable=SC2034  # mask is consumed by the sourcing script
build_mask() {
  local seat="$1" root="$2"; shift 2
  # SANDBOX POSTURE (Overseer experiment, 2026-10-26, Regent docket
  # fort/annals/regent-docket-2026-10-26-secrets-only.txt). One switch, read
  # from fort/scripts/sandbox-posture (inside the kernel-read-only fort/scripts,
  # so no seat can flip its own posture) and overridable by FORT_SANDBOX in the
  # launching environment. Values:
  #   full          today's mask, byte for byte (the default).
  #   secrets-only  the seat gets the host: the Docker socket, a writable
  #                 $HOME and checkouts, the shared /tmp,
  #                 the network. STILL MASKED: the user manager's sockets
  #                 (systemd --user is a host escape, unneeded), every secret spelling
  #                 (SECRET_GLOBS), ~/.netrc ~/.npmrc ~/.git-credentials, the
  #                 credential dirs (MASK_DIRS: ~/.ssh ~/.aws ~/.azure
  #                 ~/.config/gh ~/.docker ~/.config/git), and every caller
  #                 --mask-file (the Keep signing token, the deploy scripts).
  # Anything else is refused loudly: an unknown posture must not launch.
  local posture="${FORT_SANDBOX:-}"
  if [ -z "$posture" ] && [ -r "$root/fort/scripts/sandbox-posture" ]; then
    posture="$(head -1 "$root/fort/scripts/sandbox-posture" | tr -d '[:space:]')"
  fi
  posture="${posture:-full}"
  case "$posture" in
    full|secrets-only) ;;
    *) echo "build_mask: unknown sandbox posture '$posture' (want full or secrets-only)" >&2; return 2 ;;
  esac
  echo "seat-sandbox: posture=$posture seat=$seat" >&2
  local CODEX_DIR_RW=0
  local mask_ssh_auth_sock=0
  local extra_ro=() env_roots=("$root") rw_trees=("$root") mask_files_extra=() rw_tmp=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env-root)
        [ "$#" -ge 2 ] || { echo "build_mask: --env-root requires a path" >&2; return 2; }
        env_roots+=("$2")
        shift 2
        ;;
      --rw-tree)
        # fortkit-1q9. A declared tree is BOTH granted and protected: it joins
        # RW_PATHS, every RO carve-out below is computed for it, and its secrets
        # are swept like the root's. Declaring one also NARROWS the caller —
        # see the $root-worktrees grant at RW_PATHS.
        [ "$#" -ge 2 ] || { echo "build_mask: --rw-tree requires a path" >&2; return 2; }
        rw_trees+=("$2")
        env_roots+=("$2")
        shift 2
        ;;
      --mask-file)
        [ "$#" -ge 2 ] || { echo "build_mask: --mask-file requires a path" >&2; return 2; }
        mask_files_extra+=("$2")
        shift 2
        ;;
      --rw-tmp)
        # Proofdelve ForgeOs-u65j.5. A path under /tmp that must survive the per-seat
        # tmpfs. /tmp is private per seat so build servers cannot be shared
        # across mount namespaces; anything a LAUNCHER puts in /tmp and the
        # SEAT must still see -- the Warden's scratch cwd -- is declared here.
        [ "$#" -ge 2 ] || { echo "build_mask: --rw-tmp requires a path" >&2; return 2; }
        rw_tmp+=("$2")
        shift 2
        ;;
      --mask-ssh-auth-sock)
        mask_ssh_auth_sock=1
        shift
        ;;
      *)
        extra_ro+=("$1")
        shift
        ;;
    esac
  done
  local uid; uid="$(id -u)"

  local MASK_FILES=(
    "$HOME/.netrc" "$HOME/.npmrc" "$HOME/.git-credentials"
    /var/run/docker.sock /run/docker.sock "/run/user/$uid/docker.sock"
    "/run/user/$uid/podman/podman.sock"
    # THE USER MANAGER'S THREE DOORS (fortkit-y7no, ported here as
    # Proofdelve ForgeOs-tq8s, 2026-09-18). The lib binds `--bind / /` and inverts only
    # $HOME, so /run/user/$uid was never masked and mask_env forwards
    # XDG_RUNTIME_DIR: from inside every seat mask, `systemd-run --user`
    # started an UNMASKED host process that saw the host's mount table, read
    # the inode-masked secret at its full byte count and could write
    # fort/scripts (measured 2026-09-10, both arms). Every kernel guarantee
    # below is void for a seat that runs that one command. Three sockets, not
    # one: with `bus` alone masked, systemd-run is refused but `systemctl
    # --user` still reaches the manager through systemd/private (measured
    # 2026-09-18: "degraded" came back), and io.systemd.Manager is the varlink
    # door beside it. All three masked: systemd-run, systemctl and busctl fail
    # "Connection refused" by the kernel, and both runtimes still launch
    # (claude -p and codex exec each answered a one-word prompt, rc 0). The
    # tool-layer denies of Proofdelve ForgeOs-4778 (Bash(systemd-run*), the ~/.codex
    # rules file) are now belt over this boundary; they bind the command word
    # only, and /usr/bin/systemd-run or a compound shell line passed them.
    "/run/user/$uid/bus"
    "/run/user/$uid/systemd/private"
    "/run/user/$uid/systemd/io.systemd.Manager"
  )
  if [ "$posture" = secrets-only ]; then
    # The Docker sockets are granted on purpose (the experiment). The user
    # manager's three doors STAY masked: no workflow needs systemd --user, and
    # from inside a mask it starts an UNMASKED host process (measured
    # 2026-09-10), which would void every secret mask below. Docker carries the
    # same power (a bind mount reaches any path); that residual is accepted
    # for the experiment and held by prose (the launchers' posture paragraph).
    MASK_FILES=("$HOME/.netrc" "$HOME/.npmrc" "$HOME/.git-credentials"
                "/run/user/$uid/bus" "/run/user/$uid/systemd/private"
                "/run/user/$uid/systemd/io.systemd.Manager")
  fi
  # Secret files, by the BOTH-LISTS rule: anything added to a policy deny list
  # belongs here too.
  #
  # fortkit-2kub: masking by ENUMERATED SPELLING, and the spelling list is the
  # whole defect. The mask bound one path per secret; an editor's swap or backup
  # file is a DIFFERENT path holding the same buffer. Observed 2026-08-11 18:25
  # in the Proofdelve tree: ..env.staging.local.kate-swp, 768 bytes, readable —
  # it begins with TWO dots, so `.env*` never matched it. Ruled in scope by the
  # Overseer under threat 1 (agent accident), not the human-adversary exemption.
  # One pattern per line so each spelling is greppable and a new editor is a
  # one-line addition.
  #
  # TWO RESIDUALS, STATED RATHER THAN GLOSSED:
  #  1. THESE GLOBS EXPAND AT LAUNCH. A residue file created after the mask is
  #     built is NOT masked for that session's lifetime. (The comment here used
  #     to claim a fort acquiring a new .env* was covered "on arrival"; that is
  #     true only of the next launch, and it overstated the guarantee.)
  #  2. Enumeration cannot be complete against an editor nobody has enumerated.
  #     The complementary controls are fortkit-ks3t (gitignore every residue
  #     spelling) and not opening .env* in an editor inside a fort checkout.
  local SECRET_GLOBS=(
    '.env*'        # canonical
    '..env*'       # Kate swap for a dotfile: ..env.staging.local.kate-swp
    '.#*env*'      # Emacs lock file
    '#*env*#'      # Emacs autosave
    '.*env*.sw?'   # vim swap for a dotfile: ..env.staging.local.swp, .envrc.swp
    '*env*~'       # editor backup copies
  )
  # DEPTH (Proofdelve ForgeOs-k47, 2026-09-18). This used to be two shell globs, "$x"/$g
  # and "$x"/*/$g, so the guarantee was depth <= 2 from each root and a
  # web/src/.env.local was readable in every seat (Warden finding 5 on 01l;
  # probe-boundaries.sh's tier-3 decoys sit three deep for that reason). It is
  # now a bounded find: every regular file (symlinks to one included, as -f
  # followed them) at depth <= 4 below each of env_roots and extra_ro whose
  # NAME matches one of the spellings above, pruning only .git and
  # node_modules. Four from the fort root reaches src/<proj>/<dir>/.env* and
  # web/src/<dir>/.env*; from a $root-worktrees root it reaches three deep
  # inside each worktree. Measured cost on this host: 14 ms over the root plus
  # seventeen worktrees. Anything deeper than four is the stated residual and
  # is what fortkit-ks3t's gitignore control and "never open .env* in an editor
  # inside a fort checkout" are for. DEDUPED across roots (Warden finding 7 on
  # 01l): warden.sh passes $root as extra_ro as well as the env root, and the
  # old loop bound every secret under it to /dev/null twice.
  local f x g seen_key
  local -A secret_seen=()
  local -a name_args=()
  for g in "${SECRET_GLOBS[@]}"; do
    [ "${#name_args[@]}" -gt 0 ] && name_args+=(-o)
    name_args+=(-name "$g")
  done
  for x in "${env_roots[@]}" "${extra_ro[@]}"; do
    [ -d "$x" ] || continue
    while IFS= read -r -d '' f; do
        # [ -f ], NOT [ -e ] (fortkit-faka finding 5, Warden Ilva Trueglass).
        # Two of the six spellings above — *env*~ and #*env*# — do NOT begin
        # with a dot, so they match ordinary names. A DIRECTORY called
        # environments~ satisfied [ -e ] and joined MASK_FILES, and
        # `--ro-bind /dev/null <directory>` ABORTS BWRAP: the failure mode was
        # NO SEAT LAUNCHES ANYWHERE, arriving through the 2kub fix rather than
        # through the mask it was fixing. Latent when found — no such path
        # existed in any fort — and one character class to close. A secret is a
        # regular file, and -f follows symlinks, so a symlinked secret is still
        # swept.
        # DISCLOSED RESIDUAL (fortkit-n3bk finding 6, E8 2026-08-13): -f trades
        # a loud abort for a SILENT GAP in one case. A DIRECTORY whose name
        # matches a secret glob is now skipped instead of aborting the launch —
        # which is the right trade, because the abort took down every seat in
        # the civilization — but it is then simply UNMASKED, and no line of
        # output says so. A directory called `environments~` or `.env.d` holding
        # secret files was therefore readable inside every mask. CLOSED TO DEPTH
        # FOUR by the find above (Proofdelve ForgeOs-k47): it descends into such a
        # directory and sweeps the files whose own names match, at the launch
        # cost measured there. A directory of secrets whose FILE names match no
        # spelling (`.env.d/staging`) is still the residual, stated here.
        [ -f "$f" ] || continue
        seen_key="$f"; [ -n "${secret_seen[$seen_key]:-}" ] && continue
        secret_seen[$seen_key]=1
        MASK_FILES+=("$f")
    done < <(find "$x" -maxdepth 4 \( -name .git -o -name node_modules \) -prune -o -xtype f \( "${name_args[@]}" \) -print0 2>/dev/null)
  done
  if [ "$mask_ssh_auth_sock" = "1" ]; then
    MASK_FILES+=("${SSH_AUTH_SOCK:-/nonexistent}")
  fi
  # Caller-declared masks (--mask-file). Joined here so they ride the same
  # existence-guarded bind pass as every other MASK_FILES entry, and are
  # therefore placed LAST per the ordering invariant — a caller appending its
  # own --ro-bind after build_mask returns would get that ordering by luck.
  MASK_FILES+=("${mask_files_extra[@]}")

  local MASK_DIRS=("$HOME/.ssh" "$HOME/.aws" "$HOME/.azure" "$HOME/.config/gh" "$HOME/.docker" "$HOME/.config/git")
  # ~/.azure joined this list under Regent edict 2026-10-15 (Proofdelve ForgeOs-mbv54 item
  # C, closes Proofdelve ForgeOs-89uq): it holds msal_token_cache.json, the live access and
  # refresh tokens for the subscription that owns staging, and was READABLE from
  # The Mayor, Forge and Warden while ~/.aws beside it was masked (measured with
  # test -r from all three postures that day). No seat needs it: a staging
  # deploy runs on the host through the airlock, and its deploy script
  # refuses under FORT_MASKED anyway. Masked the way ~/.aws is, an empty tmpfs:
  # the directory still resolves and nothing in it does.
  # Cycle 7 (Overseer edict 2026-08-08, Proofdelve ForgeOs-8c9 / fortkit-i4y): charter and
  # seat files moved OUT of the kernel mask to a prose gate — charter prose
  # binds a session only through its own reading of it, and amendments now ride
  # a bead with the Overseer's approval and a charter.amended event, with drift
  # made visible by events-in-git and routine push. The ENFORCEMENT layer
  # tightens instead: write access follows execution context. fort/scripts
  # executes on the HOST (launchers, emit.sh in its launcher role, the probe
  # suites, watch-push-drift.sh in cron), so a seat that can edit it is editing
  # code that runs unmasked at the next launch. Since cycle 13 (fortkit-52vf.9,
  # Shape B; the verify.sh re-grant this sentence once described was retired
  # there, Proofdelve ForgeOs-zi46): fort/scripts is a WHOLE-DIRECTORY read-only bind with
  # no exception, fort/scripts/verify.sh is a read-only shim, and the verifier
  # this fort evolves is scripts/verify-impl.sh -- writable to the Mayor,
  # read-only to the Forge by the codex carve-out below, read-only to the
  # Warden because she binds her whole checkout. .git/config and .git/hooks
  # are host-executed the same way —
  # hooks fire unmasked on the Overseer's next commit, and core.hooksPath
  # repoints them (fortkit-cqc, same class as the .beads hooks below). r2
  # correction (Warden 8c9 finding 3): forge.sh does NOT carry these binds —
  # its probe 20 passes because Landlock keeps the main .git outside the
  # Forge's writable scope; this lib had no guard at all until cycle 7.
  #
  # fortkit-1q9: these are computed PER WRITABLE TREE, not once for $root.
  # RW_PATHS grants more than one checkout, and until this every cycle-7
  # protection applied to exactly one of them — so a seat could obtain a
  # writable copy of the whole enforcement layer one directory sideways, edit a
  # launcher there, and let the Mayor's ordinary merge carry it to $root.
  # RESIDUAL, DELIBERATE: a tree created AFTER the mask is built cannot be
  # carved (same launch-time truth as the secret globs above), which is why the
  # answer is declared trees plus a narrowed $root-worktrees grant rather than
  # iterating whatever worktrees happen to exist.
  local RO_PATHS=() RW_CARVE=() t hostpath
  for t in "${rw_trees[@]}"; do
    RO_PATHS+=("$t/.claude" "$t/fort/profiles" "$t/.git/config" "$t/.git/hooks")
    # Proofdelve ForgeOs-72ot. The airlock operation TABLE, guarded on existence so a fort
    # without an airlock is unaffected. It belongs with the files above and was
    # measured WRITABLE from the Mayor mask on 2026-08-24, while its own header
    # said "Adding an operation is a constitution-tier change (charter gate 6)".
    # That claim was enforced by prose only, and the prose was load-bearing:
    # airlock.sh reads BOTH the script path and requires_approval out of this
    # file AT RUN TIME, then executes ( cd "$root" && bash "$root/$script" ) on
    # the HOST, outside every sandbox, with credentials in scope. So the table
    # deciding WHAT runs and WHETHER it needs the Overseer was writable by the
    # seat that requests operations. Threat 1 as it stands: a seat that
    # "helpfully" edits an operation changes what the host runs, silently.
    # SCOPED DELIBERATELY TO THE TABLE. requests/ stays writable — a seat must
    # be able to REQUEST — and that leaves the approval STATUS still seat-
    # writable, which is the other half of 72ot and is filed separately. Do not
    # read this line as closing 72ot whole; it closes the table, not the state.
    [ -e "$t/fort/airlock/operations.json" ] && RO_PATHS+=("$t/fort/airlock/operations.json")
    # Host-executed civilization surface. Guarded on the covenant, not bare
    # existence (Warden suti finding 6): an ordinary fort growing a bin/ of its
    # own must not find it silently read-only — only the capital, which hosts
    # bin/regent and the civ launchers, carries this surface.
    # ($t/.git/config is a no-op in a worktree, where .git is a FILE; the real
    # per-worktree config is $root/.git/worktrees/<n>/config.worktree and it
    # cannot be bound read-only because git must write the index beside it —
    # fortkit-8cq. The hook vector itself is closed: a worktree uses the main
    # .git/hooks, which IS bound above.)
    if [ -e "$t/civ/covenant.md" ]; then
      for hostpath in "$t/bin" "$t/civ/scripts" "$t/civ/profiles"; do
        [ -e "$hostpath" ] && RO_PATHS+=("$hostpath")
      done
    fi
  done

  case "$seat" in
    codex)
      # KNOWN EXCEPTION: ~/.codex is bound as a LIVE READ-WRITE DIRECTORY below
      # (CODEX_DIR_RW), for BOTH seat types. The reasoning is written out once,
      # at the claude branch's dispatch exception — the short version is that
      # codex rotates its token by RENAME, so a re-bound auth.json FILE pins the
      # inode and rotation fails. config.toml is bound read-only in the later
      # RO-path pass, closing the disarm-the-next-launch vector without breaking
      # the runtime. ~/.claude is masked entirely: the Forge has no business with
      # the other runtime's credentials or memory.
      CODEX_DIR_RW=1
      MASK_DIRS+=("$HOME/.claude")
      RO_PATHS+=("$HOME/.codex/config.toml")
      # The cycle-7 prose gate on charter and seats applies to ATTENDED seats
      # only — an unattended seat cannot ask first, so a prose gate on it
      # guards nothing (cycle 6 ruling). The Forge keeps the mechanical lock.
      # LIVE since fortkit-6jf's first half: this fort's forge.sh sources this
      # lib and calls `build_mask codex` (measured 2026-08-12). The note that
      # used to stand here — "no launcher currently calls build_mask codex" —
      # was true when Warden 8c9 finding 2 was written and is not true now.
      # THE WRINKLE SHAPE B WOULD OTHERWISE OPEN, closed here. With the
      # verifier's implementation living in repo scripts/, it sits inside $root,
      # which is read-write to the Forge apart from these carve-outs — so
      # without this line the unattended seat could edit the verifier that
      # judges its own work. Cycle 7's stated intent is the opposite: "verifier
      # changes are Mayor work; the Forge's and the Warden's masks keep it
      # read-only." The Warden needs nothing extra, because she passes her whole
      # checkout as extra_ro and gets it for free.
      # skills/ joins them (fortkit-4n8c): the installed ~/.claude/skills entries
      # are now SYMLINKS to this directory, so its contents are session-executed
      # instruction loaded by every seat and by the unmasked Regent. For attended
      # seats it is prose-gated exactly as charter.md and fort/seats are — prose
      # that binds only through a session's own reading of it, with drift visible
      # in git. The unattended seat cannot ask first, so it keeps the mechanical
      # lock (cycle 6 ruling).
      for t in "${rw_trees[@]}"; do
        RO_PATHS+=("$t/fort/charter.md" "$t/fort/seats" "$t/scripts/verify-impl.sh" "$t/skills")
      done
      ;;
    claude)
      # Mirror image. ~/.claude stays readable and writable: it holds this
      # runtime's credentials, this project's auto-memory, and the session
      # transcripts Claude Code writes as it runs. Its CONFIG is bound
      # read-only so a session cannot rewrite its own permission rules or the
      # global instructions for the next one (21f.5, applied to Claude seats).
      RO_PATHS+=("$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" \
                 "$HOME/.claude/CLAUDE.md" "$HOME/.claude/helpers")
      # fortkit-5sk, Overseer ruling 2026-08-12: the GLOBAL instruction surface
      # is session-executed context that runs at the NEXT launch, including the
      # unmasked Regent's — so a masked seat that writes it controls code
      # running outside the mask. Cycle 7 closed this class for the fort's own
      # config and missed the global one.
      #   civilization.json  the settlement registry every civ tool reads
      #   skills/            INSTALLED COPIES of fortkit/skills, executed as
      #                      instructions. Ruled read-only knowing it strands
      #                      the hand-copy install lane a masked Mayor used on
      #                      2026-08-12; installing a skill is now an unmasked
      #                      act until fortkit-4n8c symlinks these to the repo.
      #   commands/ plugins/ slash commands and plugin payloads, both executed
      # SECOND STRANDED LANE, disclosed here because the skills one was and this
      # one was not (fortkit-faka finding 4): bin/fort-init writes the settlement
      # registry at ${FORT_REGISTRY:-$HOME/.claude/civilization.json}, and in
      # THIS arm that path is kernel-RO, so FOUNDING A SETTLEMENT FROM INSIDE A
      # MASKED CLAUDE SEAT FAILS EBUSY AT THE RENAME — not EROFS at the write.
      # The bound file EXISTS, so fort-init's > redirect never fails; what fails
      # is the mv, because a rename cannot replace a mount point. The founder
      # sees:
      #   mv: cannot move '.../civilization.json.new' to
      #       '.../civilization.json': Device or resource busy
      # That matters beyond pedantry: grepping the terminal for EROFS or
      # "Read-only file system" after a failed founding finds NOTHING, and reads
      # as "the mask is not the cause". This comment said EROFS from cycle 7
      # until 2026-09-01 and contradicted bin/fort-init's own comment, which has
      # been right since fortkit-fg7s (fortkit-zadt; Ilva Trueglass, finding 3
      # on the covenant-4.5 review of the fortkit-2twy sitting, referred to the
      # Overseer during it and deferred by him to a bead).
      # AND IT IS SCOPED TO THIS ARM, WHICH IS THE HALF THAT BITES SILENTLY: the
      # codex) arm masks $HOME/.claude as a TMPFS, so a Forge founding does not
      # fail at all. It mints a registry inside the tmpfs, registers the fort,
      # exits 0, and the entry dies with the namespace — a founding reporting a
      # success it has not earned, which is bin/fort-init's own subject, in the
      # one posture its preflight cannot detect. Measured inside a real codex
      # mask 2026-08-31.
      # Founding is already Overseer or Regent work, so the decision stands; the
      # gap was in its record, and that kind of gap costs someone an afternoon.
      # Pass FORT_REGISTRY at a writable path to found a throwaway fort for
      # testing, which is what the factory's own verification does.
      # NOT MASKED, deliberately: ~/.claude/teams. It is harness session state,
      # not an instruction surface — Claude Code writes teams/session-<id>/
      # config.json at EVERY session start, so a read-only bind there would
      # break every masked launch. Do not "complete" this list with it.
      RO_PATHS+=("$HOME/.claude/civilization.json" "$HOME/.claude/plugins")
      # SKILLS ARE WRITABLE (Overseer 2026-10-27, Proofdelve ForgeOs-yhn44): "Seats should be able
      # to write user-level skills", with no carte blanche to .claude. ~/.claude/skills and
      # ~/.claude/commands leave the read-only list; settings.json, settings.local.json,
      # CLAUDE.md, helpers and plugins (which can carry hooks) stay read-only above.
      # ACCEPTED RISK, stated so it is not rediscovered: a skill is standing instruction,
      # and ~/.claude/skills is also read by the unmasked Regent at its next launch.
      # The project .claude/skills and .claude/commands are carved writable per tree
      # below, after the read-only pass, so the rest of the project .claude stays locked.
      # A caller that must not write skills passes them as extra_ro, which binds after
      # the carve: warden.sh does, for both the project and the user-level pair (the
      # Overseer's choice at the 2026-10-27 sitting: the Warden stays read-only).
      for t in "${rw_trees[@]}"; do
        RW_CARVE+=("$t/.claude/skills" "$t/.claude/commands")
      done
      # DISPATCH EXCEPTION, redesigned (longburn-1p9, measured 2026-08-05;
      # unified across the civilization 2026-08-13 by fortkit-52vf.10 with the
      # Overseer present): the Mayor launches the Forge, and a child codex
      # inherits this mount namespace, so ~/.codex must be reachable and auth
      # must be able to ROTATE. The old design (tmpfs over ~/.codex + auth.json
      # re-bound RO as a FILE) pinned the auth.json inode: codex rotates the
      # token by rename, so rotation failed at write, the refresh token was
      # reused and revoked server-side, and a host-side `codex login` stayed
      # invisible to running sessions — both seat lanes died until session
      # restart. Fix: bind the real DIRECTORY read-write (name lookups resolve
      # live, so rename rotation and host re-login both work), keep config.toml
      # read-only (the injection vector, 21f.5), and mask transcripts/history.
      # Reading the token remains the same accepted exposure as before: a
      # session that can already spend it gains little by seeing it. Revisit if
      # Codex gains fd/env auth.
      #
      # THE COST, STATED RATHER THAN IMPLIED (Overseer's rider, 2026-08-13).
      # ~/.codex is not only credentials and transcripts. It also holds
      # SESSION-EXECUTED INSTRUCTION for the Codex runtime — AGENTS.md, skills/,
      # plugins/, rules/, memories/ — which is the same class of surface
      # fortkit-5sk kernel-locked for the Claude runtime (~/.claude/skills,
      # commands, plugins, civilization.json). A live rw bind hands an attended
      # Mayor or Warden write access to all of it, and what it writes there is
      # loaded as instruction by the NEXT codex launch, outside that seat's mask.
      # That is a real widening of the attended-seat boundary and it is accepted
      # deliberately here, not overlooked.
      #   • For the CODEX seat the policy layer still covers it — but NOT by
      #     the mechanism this comment used to name. It named a deny profile
      #     in forge.sh, covering the codex home, as what enforces this — and
      #     that profile exists in ONE fort. Re-measured 2026-08-13 (finding 1
      #     fortkit-52vf.10, fortkit-52vf.10.1): only Proofdelve's forge.sh has
      #     such a table; the capital's and the factory's contain the word
      #     `deny` zero times, and Farlantern's once, about Landlock rather
      #     than a table. A SHARED COMMENT TRUE IN ONE FORT AND FALSE IN
      #     ANOTHER IS THE DRIFT CLASS THIS FILE EXISTS TO CLOSE, so what is
      #     named here is the mechanism that actually holds in ALL FOUR copies:
      #     every forge.sh runs `codex exec --sandbox workspace-write`, whose
      #     writable roots are the workspace itself (the worktree that is cwd)
      #     and the temp dir, PLUS the explicit --add-dir grants (Proofdelve ForgeOs-tfwm:
      #     the grants are additions to that set, not the whole of it), and
      #     ~/.codex is in none of them — so codex's own command executor
      #     refuses the model's shell there ("rejected by the command
      #     executor", MEASURED 2026-08-13 in the three forts that had a Forge
      #     that day, Proofdelve, Farlantern and Manyhalls; the factory's copy
      #     is the fourth and its mechanism is INFERRED from the identical
      #     `codex exec` line, not measured). Proofdelve's deny profile is an
      #     ADDITIONAL layer in that one fort, not the load-bearing one; and
      #     Landlock DOES enforce write denials where a profile is in play
      #     (only read-deny is the upstream TODO, openai/codex#11316).
      #     So the Forge is denied at policy and permitted at kernel; the Mayor
      #     and Warden are permitted at both.
      #   • DO NOT "FIX" THIS BY RO-BINDING skills/ OR plugins/. The Overseer
      #     ruled it out on 2026-08-13: codex appears to mutate both at startup,
      #     so a read-only bind there is a launch-abort risk of exactly the
      #     ~/.claude/teams shape (harness state that looks like an instruction
      #     surface). It is filed as fortkit-elh9 — the codex twin of
      #     fortkit-5sk, and, unlike 5sk, one an RO bind cannot fix. Leave it.
      CODEX_DIR_RW=1
      RO_PATHS+=("$HOME/.codex/config.toml")
      # CONSEQUENCE, WRITTEN DOWN BECAUSE IT WAS NOWHERE (Warden finding 6 on
      # fortkit-52vf.10): a Forge DISPATCHED BY A MAYOR inherits these masks
      # recursively, so that codex session's rollouts, log and history.jsonl
      # land in the MAYOR's tmpfs and are LOST when her session ends. This is
      # not a regression — the previous full tmpfs over ~/.codex lost them too
      # — and it is not a launch failure (measured: fortkit-m0wm ran to exit
      # 0). It is simply invisible, and a seat looking for a missing rollout
      # would otherwise spend a session finding out why.
      # These three are asserted by neither probe-cycle7.sh nor
      # scripts/mask-harness.sh; that gap is fortkit-52vf.10.1's finding 6 and
      # is deferred to fortkit-wtps with the rename assertion, NOT closed here.
      MASK_DIRS+=("$HOME/.codex/sessions" "$HOME/.codex/log")
      MASK_FILES+=("$HOME/.codex/history.jsonl")
      ;;
    *) echo "build_mask: unknown seat type '$seat' (expected codex|claude)" >&2; return 2 ;;
  esac

  # fortkit-6ovg and fortkit-x9ou — SHAPE B (Overseer ruling 2026-08-12,
  # reversing Shape A of the previous day). THE VERIFIER MOVED OUT INSTEAD OF
  # BEING CARVED OUT. fort/scripts is one whole-directory read-only bind for
  # every seat type, and fort/scripts/verify.sh is a shim that execs
  # scripts/verify-impl.sh, which lives where mutability is already sanctioned.
  #
  # THE HISTORY MATTERS, because two shapes were tried and both failures were
  # about the same confusion between a FILE and a LOCATION:
  #  • Cycle 7 bound this directory read-only and re-bound verify.sh read-WRITE
  #    inside it. Measured in all three forts by all three Mayors: `test -w`
  #    returns TRUE and an O_APPEND open works, while Edit, `sed -i`, `git
  #    checkout` and `git merge` all fail — each of them rewrites a file by
  #    creating or unlinking a SIBLING, and the directory was read-only. The
  #    error names a temp path rather than verify.sh, which is why it cost three
  #    forts a cycle to see.
  #  • Shape A inverted it: writable directory, every entry bound read-only
  #    individually, verify.sh left unbound. The edits worked and each FILE was
  #    immutable (a read-only bind is a mount point; the kernel refuses to
  #    unlink or rename over one, EBUSY). Both premises it was approved on then
  #    failed inside a day:
  #      - "the new-file hole is bounded to the MAYOR, an attended seat that
  #        asks first" — FALSE. Every build_mask claude caller that does not
  #        pass its own checkout as extra_ro holds it, which includes
  #        civ/scripts/herald.sh — AND THE HERALD RUNS UNATTENDED, headless, on
  #        a daily 05:00 timer, with Bash, Write and Edit (fortkit-vkq8).
  #      - "the hole only lets a seat ADD files, and nothing there is
  #        auto-executed" — FALSE. The harness measured `A4b fort/scripts DIR
  #        not renamable :: unlink=NO rename=YES`. With the directory itself
  #        unlocked, a seat could rename it aside and put its own fort/scripts
  #        in its place; ~/.local/bin/mayor then exec'd that path ON THE HOST,
  #        UNMASKED. Per-file mounts protect the FILES and not the LOCATION
  #        (fortkit-x9ou).
  #
  # Shape B has neither problem and needs no accepted residual: the directory is
  # a mount point again, so it refuses rename, and nothing new can be created
  # inside it. The cost is one level of indirection, paid once, in a shim that
  # says so at the top of itself.
  for t in "${rw_trees[@]}"; do RO_PATHS+=("$t/fort/scripts"); done

  # THE OVERSEER STORE (Proofdelve ForgeOs-72ot.1 + Proofdelve ForgeOs-ubgx.4, Regent edict
  # 2026-10-06, the Overseer's ruling of 2026-10-05 with the store placed at
  # civilization level the same morning). ~/.local/state is granted rw below,
  # so without this every masked seat in every fort could write the Keeps'
  # records: a signature, or an airlock approval, written by the seat that
  # wanted it. A record in a civilization-level file names its fort, and a seat
  # in any fort could otherwise forge one for another.
  #
  # EVERY KEEP STORE ON THIS HOST, BY GLOB, NOT BY NAME (Regent sitting
  # 2026-11-18, fortkit-ttpk; the Warden's blocking finding 2 on that bead). This
  # lib was copied from the fort whose own Keep store it named beside civ-keep/,
  # and the rename pass that made the copy Manyhalls's turned that name into a
  # directory that does not exist: the other fort's live signature records became
  # writable to every seat here, and the isolation gate could not see it, because
  # it looks for another fort's name and this was a name REMOVED. A protective
  # list must keep covering other forts' stores; naming none of them and binding
  # every *-keep directory is the form that survives a rename.
  # civ-keep/ AND THIS FORT'S OWN STORE are created if absent: an RO bind is
  # existence-guarded, and a directory a seat could create first is a directory a
  # seat could seed. The own store is named here because fleet.sh
  # (keep_corroborates) and scripts/unattended-fleet read it as the Overseer's
  # record whether or not this fort runs a Keep of its own; the glob below binds
  # only what exists, so without this line the store a fort has never had is the
  # one store a seat can make (the Warden's blocking finding 1, review 2,
  # fortkit-ttpk). A store that cannot be created is said aloud, since the
  # launch then proceeds with that record unprotected.
  local store
  mkdir -p "$HOME/.local/state" 2>/dev/null || true
  for store in "$HOME/.local/state/civ-keep" "$HOME/.local/state/manyhalls-keep"; do
    [ -d "$store" ] || mkdir -m 700 "$store" 2>/dev/null \
      || echo "seat-sandbox: WARNING: could not create $store; that Overseer store is NOT read-only in this mask" >&2
  done
  for store in "$HOME"/.local/state/*-keep; do
    if [ -d "$store" ]; then RO_PATHS+=("$store"); fi
  done

  # FOREIGN FORTS ARE READ-ONLY (Regent sitting 2026-11-18, fortkit-ttpk; the
  # Overseer's decision recorded on that bead, on the Warden's finding 4). In the
  # secrets-only posture the mask starts from a writable /, so nothing but this
  # block stands between a seat here and another fort's repository, worktrees,
  # fleet state (its HALT file, its locks) and config directory. Every fort in
  # either registry whose repo is not this one is bound read-only: its repo, its
  # <repo>-worktrees, and the state, config and data directories its own
  # machinery derives from its name. Read from the registries at launch, so it
  # names no fort and a fort founded tomorrow is covered at the next launch.
  # In the full posture $HOME is already read-only and these binds repeat it.
  # WHAT IT DOES NOT COVER: a fort outside both registries; a path a fort keeps
  # somewhere its name does not predict; and Docker, which is root.
  # "This fort" is $root, or the main checkout $root is a worktree of: a mask built
  # for a worktree must not find its own fort foreign (measured at the sitting: it
  # did, and the tree it was built for came back read-only).
  local reg frepo fname fslug here_real here_main
  here_real="$(readlink -f "$root" 2>/dev/null || printf '%s' "$root")"
  here_main="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  here_main="$(readlink -f "${here_main%/.git}" 2>/dev/null || printf '%s' "$here_real")"
  # FAILS OPEN, AND SAYS SO (the Warden's finding 2, review 2): with jq missing or
  # the civilization registry unreadable, no fort is known to be foreign and
  # nothing here binds. The launch proceeds, because refusing would stop every
  # seat on a host with a damaged registry; the warning is the record.
  reg="${FORT_REGISTRY:-$HOME/.claude/civilization.json}"
  if ! command -v jq >/dev/null 2>&1 || [ ! -r "$reg" ]; then
    echo "seat-sandbox: WARNING: cannot read the fort registry ($reg) or jq is missing; other forts are NOT bound read-only in this mask" >&2
  fi
  if command -v jq >/dev/null 2>&1; then
    for reg in "${FORT_REGISTRY:-$HOME/.claude/civilization.json}" "$HOME/.claude/greenlab.json"; do
      [ -r "$reg" ] || continue
      while IFS=$'\t' read -r frepo fname; do
        [ -n "$frepo" ] || continue
        frepo="$(readlink -f "$frepo" 2>/dev/null || printf '%s' "$frepo")"
        if [ "$frepo" = "$here_real" ] || [ "$frepo" = "$here_main" ]; then continue; fi
        fslug="$(printf '%s' "$fname" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')"
        RO_PATHS+=("$frepo" "$frepo-worktrees")
        if [ -n "$fslug" ]; then
          RO_PATHS+=("$HOME/.local/state/$fslug-fleet" "$HOME/.local/state/$fslug-mayor" "$HOME/.config/$fslug"
                     "$HOME/.local/share/$fslug" "$HOME/.local/share/$fslug-watchdog")
        fi
      done < <(jq -r '.forts[]? | [(.repo // ""), (.fort_name // .project // "")] | @tsv' "$reg" 2>/dev/null)
    done
  fi
  [ -d "$HOME/.local/state/greenlab" ] && RO_PATHS+=("$HOME/.local/state/greenlab")

  # EVERY KEEP AND FEEDBACK TOKEN UNDER ~/.config IS MASKED, whichever fort's (the
  # Warden's blocking finding 3 on fortkit-ttpk). ~ is readable in every posture.
  # The Civ Keep, which this fort uses, reads one civilization-wide token at
  # civ-keep/signing-token; each launcher also names that file with --mask-file,
  # and this glob covers the tokens of forts this lib cannot name. Existence-
  # guarded like every mask: a token written while a session is live is visible
  # to that session.
  local tok cfg
  for cfg in "$HOME/.config" "${XDG_CONFIG_HOME:-$HOME/.config}"; do
    for tok in "$cfg"/civ-keep/signing-token "$cfg"/*/keep-signing-token "$cfg"/*/feedback-read-token; do
      if [ -f "$tok" ]; then MASK_FILES+=("$tok"); fi
    done
  done

  # FILESYSTEM SCOPING (cycle 5). Before this, the sandbox was "everything
  # writable except what we masked", so a seat working in one fort could still
  # rm -rf another project or wipe ~/Documents — threat #1, agent accident, and
  # the reason a blanket bash allow was indefensible. Inverted here: $HOME goes
  # read-only and write access is re-granted to exactly what a seat legitimately
  # writes. Same inversion that beat the deny-glob spelling problem: enumerate
  # the grants, never the prohibitions. Reads across $HOME stay open by decision
  # (Overseer, 2026-08-04): cross-fort reads are worth more than the
  # exfiltration-path reduction, since civ-digest and the Herald both need them.
  local RW_PATHS=("${rw_trees[@]}" "$HOME/.claude"
                  "$HOME/.npm" "$HOME/.nuget" "$HOME/.cache" "$HOME/.bun"
                  "$HOME/.local/share/pnpm" "$HOME/.local/state"
                  # XDG NuGet http-cache: forge.sh grants it to Codex (--add-dir),
                  # and Codex's per-command bwrap mkdirs a .git marker under every
                  # writable root — read-only here means Forge dispatched from a
                  # masked Mayor session dies before its first command (a Proofdelve bug
                  # bead, measured 2026-08-04: even pwd failed). ~/.nuget was
                  # already writable; this adds nothing new in kind.
                  "$HOME/.local/share/NuGet")
  # fortkit-1q9. $root-worktrees is granted WHOLESALE only to a caller that
  # declared no tree of its own — the Mayor, who creates worktrees when she
  # dispatches the Forge from inside her own mask. A caller that names its
  # worktree gets that one and nothing else, so the Forge stops being able to
  # write every OTHER bead's worktree.
  # THE MAYOR'S RESIDUAL IS OPEN AND KNOWN: she can still `git worktree add` and
  # obtain a writable enforcement layer in the new tree. No launch-time mask can
  # close that. It closes when fortkit-52vf.6 (E5) makes forge.sh refuse to
  # launch in-mask, after which her grant can go too. Tracked on fortkit-1q9.
  [ "${#rw_trees[@]}" -eq 1 ] && RW_PATHS+=("$root-worktrees")
  if [ "$posture" = secrets-only ]; then
    # Only the read-only $HOME goes. RO_PATHS and extra_ro STAY (Regent
    # Calder's finding, Proofdelve ForgeOs-yhn44 sitting, 2026-10-26): they hold
    # fort/scripts (incl. this posture switch), fort/airlock/operations.json,
    # .git/config and .git/hooks, the Overseer's approval stores, the profiles
    # and settings, and the host-executed scripts. Making them writable would
    # let an ordinary file edit reach deploys and approvals, which the
    # experiment never asked for. A first draft of this patch cleared both
    # arrays; that was the Mayor's error, caught before it was applied.
    mask=(--bind / / --dev /dev --die-with-parent)
  else
    mask=(--bind / / --dev /dev --die-with-parent --ro-bind "$HOME" "$HOME")
  fi
  local w
  for w in "${RW_PATHS[@]}"; do [ -n "$w" ] && [ -e "$w" ] && mask+=(--bind "$w" "$w"); done
  # ~/.codex as a live rw DIRECTORY bind, for BOTH seat types (see the dispatch
  # exception above). Placed here, with the rw grants, so the config.toml RO
  # bind and the transcript masks below stack OVER it per the ordering invariant.
  [ "${CODEX_DIR_RW:-0}" = "1" ] && [ -d "$HOME/.codex" ] && mask+=(--bind "$HOME/.codex" "$HOME/.codex")
  # ORDERING INVARIANT (Proofdelve ForgeOs-01l): bwrap mounts stack, so any bind placed
  # after a mask mounts the real content back OVER it. The warden passes the
  # whole candidate tree as extra_ro; when that bind followed the file masks it
  # resurfaced every masked secret beneath it (measured: host run
  # 2026-08-04T202453, mask-spelling:warden 4/4 FAIL). Subtree binds — ro
  # paths, extra_ro, hooks dirs — therefore go HERE, and the per-file dev-null
  # masks and per-dir tmpfs masks go LAST. One exception, surfacing a single
  # file back over a directory tmpfs and therefore placed after the masks: the
  # ~/.ssh/known_hosts re-bind (Proofdelve ForgeOs-q6m). (The ~/.codex/auth.json re-bind
  # was the second until fortkit-52vf.10 retired it with the tmpfs it was
  # compensating for.)
  local p
  for p in "${RO_PATHS[@]}"; do [ -e "$p" ] && mask+=(--ro-bind "$p" "$p"); done
  # RW_CARVE: writable subdirectories INSIDE a read-only path (the project
  # .claude/skills and .claude/commands, Proofdelve ForgeOs-yhn44 2026-10-27). Bound after
  # RO_PATHS so they win over the read-only project .claude, and bound only
  # when the directory already exists, so a seat cannot create a new carve
  # point. BOUND BEFORE extra_ro, DELIBERATELY (Regent sitting 2026-10-27, item
  # D): the Warden passes her whole checkout as extra_ro, and a carve placed
  # after that pass re-opened $root/.claude/skills and .claude/commands INSIDE
  # her read-only tree (measured on a fixture with the drafted patch: WRITABLE
  # for the Warden). A caller's own read-only binds must be able to re-mask a
  # grant, the same rule the verify.sh re-grant learned in cycle 7.
  for p in "${RW_CARVE[@]}"; do [ -d "$p" ] && [ ! -L "$p" ] && mask+=(--bind "$p" "$p"); done
  for p in "${extra_ro[@]}"; do [ -e "$p" ] && mask+=(--ro-bind "$p" "$p"); done
  # SSH inside a user namespace (cycle 6). bwrap's userns maps root-owned files
  # to 'nobody', and OpenSSH refuses any config owned by neither root nor the
  # invoking user, so it aborts before authenticating: "Bad owner or permissions
  # on /etc/ssh/ssh_config.d/...". That cost more than convenience — a seat that
  # cannot fetch cannot verify ahead/behind against the real remote, and standing
  # order 11 requires committed/pushed/deployed to be separately VERIFIED rather
  # than estimated. Fix: a user-owned ssh_config, written per launch, shadowing
  # /etc/ssh inside the sandbox.
  # ~/.ssh stays masked: keys are never readable here. An agent-held identity
  # signs instead, so a seat uses a key it cannot read (`ssh-add`, or
  # AddKeysToAgent yes in ~/.ssh/config).
  local fort_ssh="${TMPDIR:-/tmp}/fort-ssh-$$"
  mkdir -p "$fort_ssh"
  {
    printf '# Generated per launch by seat-sandbox.sh — user-owned so ssh accepts it.\n'
    printf 'Host *\n'
    printf '  StrictHostKeyChecking accept-new\n'
    printf '  UserKnownHostsFile %s/.ssh/known_hosts\n' "$HOME"
  } > "$fort_ssh/ssh_config"
  chmod 600 "$fort_ssh/ssh_config"
  mask+=(--tmpfs /etc/ssh --ro-bind "$fort_ssh/ssh_config" /etc/ssh/ssh_config)

  # Git hooks under .beads run on the HOST, unsandboxed, on the next commit or
  # push in the main checkout — a writable .beads is a host RCE escape. CLASS
  # fix, not one path: there are at least two such directories (.beads/hooks and
  # dolt's git-remote-cache repo.git/hooks), so every one is caught by finding
  # them rather than naming them.
  # fortkit-faka finding 3 (Warden Ilva Trueglass, E2 review): PER DECLARED
  # TREE, not root-scoped. Everything above moved to the rw_trees form in 1q9
  # and this did not, while calling itself a CLASS fix — and .beads/hooks/* is
  # TRACKED, so every worktree materialises its own writable copy of the five
  # hook scripts. Direct execution was already closed (core.hooksPath is an
  # absolute path into the main checkout, which is bound below), so the live
  # path was the same one 1q9 describes for launchers: a Forge edits its
  # worktree copy, commits path-scoped, and an ordinary merge carries it to
  # $root where it runs unmasked on the next commit or push. Non-blocking
  # because that path is Warden-reviewed; fixed because "every one is caught by
  # finding them rather than naming them" was not true of the trees.
  local h
  for t in "${rw_trees[@]}"; do
    while IFS= read -r h; do mask+=(--ro-bind "$h" "$h"); done \
      < <(find "$t/.beads" -type d -name hooks 2>/dev/null)
  done
  # BELT FOR THE SAME DEFECT — and deliberately NOT [ -f ] here. MASK_FILES also
  # carries SOCKETS: the docker and podman sockets always, and SSH_AUTH_SOCK
  # under --mask-ssh-auth-sock. [ -f ] is FALSE for a socket, so using it here
  # would silently stop masking the docker socket, which is the one entry in
  # this list that is a host-escape rather than a secret. The property that
  # actually matters at the bind site is "exists and is not a directory".
  for f in "${MASK_FILES[@]}"; do [ -e "$f" ] && [ ! -d "$f" ] && mask+=(--ro-bind /dev/null "$f"); done
  local d
  for d in "${MASK_DIRS[@]}"; do [ -d "$d" ] && mask+=(--tmpfs "$d"); done

  # THIRD EXCEPTION to the ordering invariant, the same shape as the
  # known_hosts re-bind below. Proofdelve ForgeOs-u65j.5: /tmp is PRIVATE per seat.
  # The Roslyn build server's socket is /tmp/<pipename>, the pipe name is keyed
  # by user and toolset with no namespace component, and `--bind /tmp /tmp` made
  # that one inode shared by every seat. Measured 2026-08-31: a compile in one
  # namespace served by a server born in another produces CS2012 "Read-only file
  # system" against a path the caller CAN write. A tmpfs makes the path resolve
  # per seat, so cross-seat serving is impossible by construction rather than by
  # every caller remembering a flag.
  # PLACED HERE, WITH THE MASK PASS, per this file's ordering invariant: the
  # tmpfs must precede the --rw-tmp re-binds below, and must not precede any
  # bind whose DESTINATION is under /tmp (there are none today). It does NOT
  # need to follow the fort_ssh bind: bwrap resolves --bind SOURCES in the
  # ORIGINAL mount namespace, which is the same property the known_hosts
  # re-bind below already relies on.
  # AN EARLIER VERSION OF THIS COMMENT CLAIMED THE OPPOSITE — that a tmpfs
  # ordered before the ssh bind "would shadow the source and break git fetch in
  # every seat". That is false, and it is corrected here rather than deleted
  # because a false rationale in the enforcement layer is what a future editor
  # reorders on (Proofdelve ForgeOs-u65j.5.1, Warden finding 2; the same seat wrote the
  # correct rule in Proofdelve ForgeOs-u65j.5's own description and the opposite of it in
  # this code). The PLACEMENT was right the whole time; only the reason was not.
  [ "$posture" = secrets-only ] || mask+=(--tmpfs /tmp)
  local t
  # Proofdelve ForgeOs-u65j.5.1, Warden finding 4: a path that does not exist yet produced
  # no bind AND no message — the silent-gap class this file's own header
  # discloses at length for --mask-file given a directory. Safe today because
  # warden.sh rsyncs its scratch into place well before build_mask, but a future
  # caller passing a not-yet-created path would get a failure surfacing later,
  # somewhere else, as something else. It still does not abort: the caller may
  # legitimately be probing. It just stops being invisible.
  for t in "${rw_tmp[@]}"; do
    if [ -n "$t" ] && [ -e "$t" ]; then
      mask+=(--bind "$t" "$t")
    elif [ -n "$t" ]; then
      echo "seat-sandbox: --rw-tmp SKIPPED, path does not exist: $t" >&2
      echo "              the seat will see the private tmpfs there, not your tree." >&2
    fi
  done


  # SECOND EXCEPTION to the ordering invariant (Proofdelve ForgeOs-q6m): known_hosts is
  # surfaced back over the ~/.ssh tmpfs so host-key PINNING survives inside the
  # mask — otherwise every launch does fresh TOFU against a known_hosts that
  # dies with the tmpfs. Placed before this line, the MASK_DIRS loop buried it
  # (Warden finding 3 on the 01l review). Keys remain unreadable: only this one
  # file is re-bound, read-only.
  [ -e "$HOME/.ssh/known_hosts" ] && mask+=(--ro-bind "$HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts")
  # A false final test must not become build_mask's return value (Proofdelve ForgeOs-vzn class).
  return 0
}

# Environment is an ALLOW-LIST, not a deny-list: enumerated unsets leave AWS_*,
# GIT_SSH_COMMAND, and anything sourced from a secrets file in the launching
# shell. Failure mode when a name is missing is loud (the CLI cannot auth or the
# terminal misbehaves), never silently insecure.
# NOTE: SSH_AUTH_SOCK is passed through deliberately — FOR CLAUDE SEATS ONLY.
# ~/.ssh is masked, so key FILES are unreadable, but agent-held identities still
# sign: an attended session can use a key it can never read (`ssh-add` for
# agent-based push). The codex seat gets neither the socket (masked at the inode)
# nor the name, because the unattended Forge never pushes.
# WHY THE NAME AND NOT JUST THE SOCKET (fortkit-52vf.10, 2026-08-13): masking the
# socket alone is sufficient at the KERNEL — measured, `ssh-add -l` returns
# "Connection refused" — and insufficient in the RECORD. Proofdelve's smoke probe
# 13 asserts SSH_AUTH_SOCK is UNSET, the seat read a set variable as a live agent
# and a boundary failure, and it refused the remaining nine probes rather than
# risk a real push. A boundary that is closed but looks open costs measurement.
mask_env() {
  local seat="$1" v
  local common=(HOME USER LOGNAME SHELL TERM COLORTERM TERM_PROGRAM LANG LC_ALL
                PATH XDG_RUNTIME_DIR GIT_PAGER PAGER)
  local codex_only=(CODEX_HOME OPENAI_API_KEY OPENAI_BASE_URL RUST_LOG NUGET_PACKAGES
                    DOTNET_CLI_TELEMETRY_OPTOUT DOTNET_NOLOGO npm_config_cache)
  local claude_only=(ANTHROPIC_API_KEY CLAUDE_CONFIG_DIR npm_config_cache SSH_AUTH_SOCK)
  mask+=(--clearenv)
  for v in "${common[@]}"; do [ -n "${!v:-}" ] && mask+=(--setenv "$v" "${!v}"); done
  # TMPDIR IS SET, NOT FORWARDED (Proofdelve ForgeOs-u65j.5.1, Warden finding 3). It used to
  # ride the common list, which was harmless only because TMPDIR is unset on this
  # host. Forwarded, it breaks two ways under Proofdelve ForgeOs-u65j.5's private /tmp: a
  # host TMPDIR under /tmp points the seat into an EMPTY tmpfs, and one under
  # $HOME points it somewhere READ-ONLY, since $HOME is ro-bound and the rw
  # re-grant is gone. Both are latent-until-someone-exports-TMPDIR. /tmp is the
  # per-seat tmpfs build_mask installs, so it is writable, private, and the one
  # answer that is correct whatever the host does.
  # COUPLED TO build_mask: this is only true for a caller that ran it. Every
  # launcher in this fort does, in the line above its mask_env call.
  mask+=(--setenv TMPDIR /tmp)
  case "$seat" in
    codex)  for v in "${codex_only[@]}";  do [ -n "${!v:-}" ] && mask+=(--setenv "$v" "${!v}"); done ;;
    claude) for v in "${claude_only[@]}"; do [ -n "${!v:-}" ] && mask+=(--setenv "$v" "${!v}"); done ;;
  esac
  # An empty final [ -n ] test must not become mask_env's return value: under a
  # set -e caller that aborts the launcher before the session starts (Proofdelve ForgeOs-vzn).
  return 0
}

require_bwrap() {
  command -v bwrap >/dev/null 2>&1 && return 0
  echo "seat-sandbox: REFUSED — bwrap not found. The kernel mask layer is the boundary;" >&2
  echo "               permission rules alone bind spellings, not files (21f.8)." >&2
  return 78
}

# ---------------------------------------------------------------------------
# THE ONE DEFINITION OF EACH SEAT'S ENVIRONMENT (Proofdelve ForgeOs-u65j.3.3).
#
# WHY THESE EXIST. Before this, every launcher wrote its own --setenv pairs and
# probe-boundaries.sh RECONSTRUCTED them BY HAND to detect launcher drift. The
# detector drifted: measured 2026-08-31 it set FORT_MASKED 1 where mayor.sh sets
# `mayor` (stale since fortkit-wg8w.2 on 2026-08-17), omitted BEADS_ACTOR
# entirely, and omitted both build-server settings added under Proofdelve ForgeOs-u65j.3.
# Three pairs behind the thing it exists to police. Nothing FAILED, because its
# assertions check that the mask builds and that $HOME/.codex is masked live,
# never that the argv matches — so it did not lie, it merely stopped resembling
# its subject, which is the Proofdelve ForgeOs-7gs / ADV-0005 shape.
#
# Updating the copy would have drifted again. One definition, several callers,
# cannot.
#
# SCOPED, BECAUSE THAT SENTENCE READ WIDER THAN WHAT SHIPPED (Warden finding 1 on
# Proofdelve ForgeOs-u65j.3.3). It is true of the seat's --setenv DELTAS, which is what these
# functions own. It is NOT true of the build_mask INVOCATION, which
# probe-boundaries.sh still reconstructs by hand and which is ALREADY one pair
# behind: mayor.sh:80 passes scripts/airlock-feedback-scan.sh as an extra_ro
# (Proofdelve ForgeOs-15k.2, 2026-08-24) and the probe never learned it, so the probe's mayor
# mask is exactly three argv entries short of the live one — 162 against 165.
# That is Proofdelve ForgeOs-u65j.3.3.1, and the fix is this same shape one level up.
#
# TWO FUNCTIONS, NOT ONE, AND THE SPLIT IS THE POINT (standing order 16).
# Architecture ports between forts; identity never does. Expressing that boundary
# as two function NAMES puts it where someone porting this file is looking,
# instead of in a comment they are not reading. Alternative considered and not
# taken: a separate lib/seat-identity.sh, so "never port this FILE" would replace
# "never port this HUNK" — structurally safer, since standing order 16's own
# worked example shows file-level convergence getting four of five hunks wrong.
# Declined because it adds a gate-6 file for a hazard that is receding: Justin
# decided 2026-08-31 that the civilization is moving from direct backporting to
# advisories, which carry guidance rather than diffs. Recorded so the tradeoff is
# visible if it ever bites.

# seat_identity <seat> — appends THIS FORT'S identity for <seat> to mask[].
#
# ***** FORT-LOCAL. MANYHALLS'S CITIZENS. NEVER PORT THIS FUNCTION. *****
# Emrith Cairnwright, Kethra Anvilmark and Ilva Trueglass hold seats in THIS
# settlement and no other. Standing order 16: a fort must never inherit another
# settlement's citizen, and that rule applies at PORTING and not only at founding.
# If you are converging this file against the factory template or another fort,
# this hunk is the one to stop on. The factory's copy carries no identity at all
# and that is correct for a file that renders for a fort which does not yet exist.
seat_identity() {
  case "$1" in
    mayor)  mask+=(--setenv FORT_MASKED mayor  --setenv BEADS_ACTOR emrith) ;;
    forge)  mask+=(--setenv FORT_MASKED forge  --setenv BEADS_ACTOR kethra)  ;;
    warden) mask+=(--setenv FORT_MASKED warden --setenv BEADS_ACTOR ilva)   ;;
    *) echo "seat_identity: unknown seat '$1'" >&2; return 1 ;;
  esac
}

# seat_build_env — fort-wide build settings, identical for every seat.
# Manyhalls's build is Node and needs none. The function stays because every
# launcher calls it; the fort this lib came from set its compiler-server
# switches here.
seat_build_env() {
  :
}

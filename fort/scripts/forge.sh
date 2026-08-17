#!/bin/bash
# Launch Kethra Anvilmark (Forge seat) on a bead, in an isolated worktree, with event emission.
# Usage: fort/scripts/forge.sh <bead-id> [model]   (model defaults to gpt-5.6-terra per ladder)
# Encodes the hard-won headless-codex recipe: stdin MUST be </dev/null, worktree MUST be trusted.
set -euo pipefail
bead="$1"; model="${2:-gpt-5.6-terra}"
root="/home/justin/dev/fortkit"
emit="$root/fort/scripts/emit.sh"
suffix="${bead##*-}"
wt="/home/justin/dev/fortkit-worktrees/$suffix"

bd update "$bead" --claim -a kethra >/dev/null 2>&1 || true
"$emit" bead.claimed "Kethra claims $bead" -a kethra -s forge -t "$bead"

if [ ! -d "$wt" ]; then
  git -C "$root" worktree add "$wt" -b "bead/$suffix" >/dev/null
fi

# Concurrency guard (fortkit-6ps): one launcher per worktree, enforced by flock.
# The 2026-08-04 double-launch incident: a dead-looking (but live) launcher was
# relaunched and two sessions worked the same worktree for 4 minutes.
lock="$wt/.forge.lock"
exec 9>"$lock"
if ! flock -n 9; then
  holder=$(cat "$lock.info" 2>/dev/null || echo "holder info unavailable")
  echo "forge.sh: REFUSED — $wt already has a live launcher: $holder" >&2
  "$emit" incident "Second forge launch on $bead refused by lock (holder: $holder)" -s forge -t "$bead"
  exit 75
fi
printf '{"pid":%d,"bead":"%s","model":"%s","started":"%s"}\n' "$$" "$bead" "$model" "$(date -Is)" > "$lock.info"
launch_timestamp="$(date -Is)"
launch_date="${launch_timestamp%%T*}"
# Deterministic handoff destination (fortkit-vn8, ported from Proofdelve agk):
# collision-safe -rN suffixes, so two sessions touching one daily file cannot
# interleave non-chronologically. The marker preserves a safe fallback for an
# older prompt that writes one new Forge handoff under a different name.
expected_handoff="$wt/fort/handoffs/forge-$launch_date-$suffix.md"
if [ -e "$expected_handoff" ]; then
  handoff_stem="${expected_handoff%.md}"
  handoff_round=2
  while [ -e "$handoff_stem-r$handoff_round.md" ]; do
    handoff_round=$((handoff_round + 1))
  done
  expected_handoff="$handoff_stem-r$handoff_round.md"
fi
handoff_marker="$(mktemp "${TMPDIR:-/tmp}/forge-handoff-marker.XXXXXX")"
handoff_tmp=""
trap 'rm -f "$lock.info" "$handoff_marker" "$handoff_tmp"' EXIT

# Kernel mask layer: seat-sandbox.sh owns every shared protection. Forge adds
# only its measured deltas: SSH_AUTH_SOCK's socket is masked to /dev/null, so no
# agent identities are available even though the variable is passed through.
#
# fortkit-1q9 (E2, 2026-08-12): --rw-tree declares the worktree, which BOTH
# grants it write access AND applies every enforcement carve-out to it — a
# superset of the five paths this call used to name by hand. Those five never
# covered $wt/bin, $wt/civ/scripts or $wt/civ/profiles, so the capital's Forge
# could edit its worktree copy of bin/regent or a civ launcher and the change
# reached main through the Mayor's ordinary merge. Declaring the tree also drops
# the blanket $root-worktrees grant, so the Forge can no longer write any OTHER
# bead's worktree. Worktree .env* coverage rides --rw-tree too.
mask=()
# shellcheck source=fort/scripts/lib/seat-sandbox.sh
# shellcheck disable=SC1091  # resolved at runtime; build_mask fills mask[]
source "$root/fort/scripts/lib/seat-sandbox.sh"
if ! require_bwrap; then
  "$emit" incident "Forge launch refused: bwrap missing, kernel mask layer unavailable" -s forge -t "$bead"
  exit 78
fi
build_mask codex "$root" --rw-tree "$wt" --mask-ssh-auth-sock
mask_env codex
# SEAT-NAMED MASK MARKER (fortkit-ugw4; the shape Farlantern has shipped
# since longburn-5v4). mayor.sh refuses under ANY non-empty FORT_MASKED and
# prints the value, so this one line makes 'no seat launches another Mayor'
# true from this seat too, and names it in the refusal. Until 2026-08-14 only
# mayor.sh set the marker, so the guard read as covering three seats and
# covered one — and the uncovered pair included the Forge, the seat that holds
# Bash. Not a capability hole (a nested bwrap cannot widen its parent's mount
# namespace) but diagnosability, which is what the guard is for.
# ONE LINE, NOT TWO. mayor.sh paired its --setenv with a host-side `export
# FORT_MASKED` until fortkit-mm7m removed it; that export reached nothing,
# because mask_env appends
# --clearenv and bwrap then rebuilds the child environment from --setenv
# alone (measured 2026-08-14: `FOO=x bwrap --clearenv --setenv BAR 1 -- env`
# prints BAR and not FOO). An export here would additionally assert, falsely,
# that this host-side launcher process is itself inside a mask.
mask+=(--setenv FORT_MASKED forge)

"$emit" session.start "Kethra begins work on $bead ($model)" -a kethra -s forge -t "$bead" -p "{\"model\":\"$model\",\"worktree\":\"$wt\"}"
desc=$(bd show "$bead" 2>/dev/null || echo "See bead $bead")
desc+="

Before you finish, write the structured handoff at '$expected_handoff'. Begin it with exactly these two lines: '# Handoff: Forge <ISO timestamp>' and 'Model: <model that did the work>'. The launcher will authoritatively stamp those header values after your session."
set +e
(cd "$wt" && bwrap "${mask[@]}" -- codex exec --sandbox workspace-write \
  -c "projects.\"$wt\".trust_level=\"trusted\"" \
  --add-dir "$root/.git/objects" \
  --add-dir "$root/.git/refs/heads/bead" \
  --add-dir "$root/.git/logs/refs/heads/bead" \
  --add-dir "$root/.git/worktrees/$suffix" \
  --add-dir "$root/.beads" \
  --add-dir "$root/fort/events" \
  -m "$model" \
  "You are Kethra Anvilmark (she/her), holder of the Forge of Manyhalls, the fortkit fort. Read AGENTS.md, fort/charter.md, fort/memory/current.md (distilled view; facts ledger in fort/memory/facts/), fort/seats/forge.md in this directory, then implement this bead and drive verifiers green. Do not merge, push, or touch .env*/deploy scripts. Commit path-scoped with message starting '$bead: '. Emit work events with EXACTLY these invocations — the detail string is required and must be non-empty (a malformed emit fails loudly and is MISSING from the record): fort/scripts/emit.sh work.begun 'one-line summary' -a kethra -s forge -t $bead when you start, and the matching fort/scripts/emit.sh work.ended 'one-line summary' -a kethra -s forge -t $bead only AFTER your final commit. If you amend anything after work.ended, re-run the verifier and append a corrected work.ended event; never edit the stream. Never close the bead or change its status: the Mayor closes it after review and merge. Report what you did, verification results, and surprises.

BEAD:
$desc" </dev/null 2>&1) | tee "/tmp/forge-$suffix.log" | tail -30
rc=${PIPESTATUS[0]}
set -e

# Post-session record integrity (fortkit-vn8, ported from Proofdelve agk/uyu).
# Non-fatal by design: a stamping failure must not lose the session's work.
handoff="$expected_handoff"
if [ ! -f "$handoff" ]; then
  mapfile -t handoff_candidates < <(find "$wt/fort/handoffs" -maxdepth 1 -type f -name 'forge-*.md' -newer "$handoff_marker" -print)
  if [ "${#handoff_candidates[@]}" -eq 1 ]; then
    handoff="${handoff_candidates[0]}"
  elif [ "${#handoff_candidates[@]}" -eq 0 ]; then
    echo "--- forge.sh: WARNING no handoff found to stamp for $bead" >&2
    handoff=""
  else
    echo "--- forge.sh: WARNING multiple new handoffs found; refusing to choose one" >&2
    "$emit" incident "Forge handoff stamping ambiguous for $bead" -s forge -t "$bead" || true
    handoff=""
  fi
fi
if [ -n "$handoff" ]; then
  # Model self-report is retired (fortkit-vn8: five mislabel sightings in one
  # day, four spellings for two models, on the field the Warden weights
  # scrutiny by). The launcher stamps Model and timestamp from its own record,
  # exactly as session.start emitted them.
  handoff_timestamp="$(date -Is)"
  handoff_tmp="$(mktemp "${handoff}.XXXXXX")"
  if awk -v timestamp="$handoff_timestamp" -v launched_model="$model" '
    NR == 1 {
      if ($0 !~ /^# Handoff: [Ff]orge/) exit 2
      print "# Handoff: Forge " timestamp
      next
    }
    !model_written && /^Model:/ {
      print "Model: " launched_model
      model_written = 1
      next
    }
    { print }
    END { if (!model_written) exit 3 }
  ' "$handoff" > "$handoff_tmp" && chmod --reference="$handoff" "$handoff_tmp"; then
    mv -f "$handoff_tmp" "$handoff"
    handoff_tmp=""
  else
    rm -f "$handoff_tmp"
    handoff_tmp=""
    echo "--- forge.sh: WARNING handoff header was not stamped: $handoff" >&2
    "$emit" incident "Forge handoff header invalid; stamping skipped for $bead" -s forge -t "$bead" || true
    handoff=""
  fi
fi

# Launcher-observed verifier (fortkit-vn8 scope, from the rh6 false-pass
# incident): forge.sh runs verify.sh itself and records the OBSERVED result,
# so a session cannot claim a verifier state the launcher didn't see.
# --no-emit: the observed exit reaches the stream via the event payloads below.
verify_log="/tmp/forge-$suffix-verify.log"
set +e
(cd "$wt" && ./fort/scripts/verify.sh --no-emit) >"$verify_log" 2>&1
verify_rc=$?
set -e
echo "--- forge.sh: launcher-observed verify.sh exit $verify_rc ($verify_log)"
if [ -n "$handoff" ] && [ -f "$handoff" ]; then
  {
    printf '\n## Launcher-observed verifier result\n\n'
    printf 'fort/scripts/verify.sh --no-emit, run by forge.sh after the session at %s: exit %s\n' "$(date -Is)" "$verify_rc"
    printf '\n```\n'
    tail -15 "$verify_log"
    printf '```\n'
  } >> "$handoff"
  handoff_relative="${handoff#"$wt"/}"
  git -C "$wt" add -- "$handoff_relative" || true
  git -C "$wt" commit -q -m "$bead: stamp handoff attribution + launcher-observed verify" -- "$handoff_relative" || true
  "$emit" handoff.written "Forge handoff stamped from launcher record" -a kethra -s forge -t "$bead" \
    -p "{\"model\":\"$model\",\"handoff\":\"$handoff_relative\",\"verify_exit\":$verify_rc}" || true
fi
"$emit" session.end "Kethra's session on $bead ended (exit $rc)" -a kethra -s forge -t "$bead" -p "{\"exit\":$rc,\"log\":\"/tmp/forge-$suffix.log\",\"worktree\":\"$wt\",\"verify_exit\":$verify_rc}" || true
echo "--- forge.sh: session ended (exit $rc). Worktree: $wt  Log: /tmp/forge-$suffix.log"
echo "--- Next: Warden reviews (fort/scripts/warden.sh $bead main..bead/$suffix), then the Mayor merges."

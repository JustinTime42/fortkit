#!/bin/bash
# Launch Ilva Trueglass (she/her) (Warden seat) on a review, read-only by construction.
# (backported from Proofdelve 21f.1/t56/21f.9, Manyhalls) Enforcement is structural, not prose:
#   - tool set restricted to Bash,Read,Grep,Glob (no Edit/Write/Task/Agent)
#   - --setting-sources "" makes fort/profiles/warden-settings.json the ONLY
#     permission source; headless default mode auto-denies unlisted Bash commands
#   - cwd is a fresh scratch copy (rsync, no .git, no env-secret files) so
#     verifier re-runs (build/test) never touch the real tree
#   - the real checkout is reachable read-only: --add-dir + git -C / bd -C
# The Warden's only writes: `bd -C <root> comment` and the review.verdict emit.
#
# Usage: fort/scripts/warden.sh <bead-id> <ref-range> [candidate-dir] [model]
#   <ref-range>      diff spec against the REAL repo, e.g. 'main..bead/xyz' or a commit
#   [candidate-dir]  tree copied/bound for verifier re-runs. OMIT IT and the
#                    launcher DERIVES it from the ref-range's tip commit (the
#                    worktree that has it checked out, or main if merged) — it
#                    never silently defaults to main (fortkit-8cv6, defect 1).
#   [model]          default opus. Ladder: Opus 5 -> GPT-5.6 Sol -> BLOCK and page
#                    Justin. Never relaunch a review below frontier.
# Smoke test: WARDEN_SMOKE=1 fort/scripts/warden.sh <bead> <range> [dir] [model]
#   runs a boundary self-test instead of a review; records no verdict.
# Exit codes: 0 = verdict recorded. 65 = session produced no verdict (dead at
#   launch, rate-limited, or truncated) — nothing was written to the bead and
#   the caller must relaunch on the next rung. 68 = candidate-presence preflight
#   refused: the ref-range does not resolve, or the candidate commit is not in
#   the tree that would be copied (fortkit-8cv6). Any other code is claude's own.
#   An absent verdict is never an approval (ForgeOs-t56).
set -euo pipefail
bead="$1"; range="$2"; src="${3:-}"; model="${4:-opus}"
root="/home/justin/dev/fortkit"
emit="$root/fort/scripts/emit.sh"
suffix="${bead##*-}"
scratch="/tmp/warden-$suffix"
log="/tmp/warden-$suffix.log"

# DEFECT 1 (fortkit-8cv6): no silent candidate-dir default that reviews a tree
# lacking the code under review. The candidate is the TIP of the ref-range, and
# the scratch is built from $src, so $src must contain that commit. When arg 3
# is omitted, DERIVE it from the range (the worktree whose HEAD is the tip, or
# main if the tip is already merged); never default silently to main. In every
# case, assert the tip is reachable from $src's HEAD BEFORE briefing the seat —
# a review against a tree without the candidate is a static reading mislabeled
# as an executed one, and warden.sh used to assert the opposite ("a scratch copy
# of the candidate tree ... safe for build/test re-runs") to the one seat whose
# job is checking whether claims are supported.
tip="${range##*..}"          # 'A..B'/'A...B' -> B; a bare commit/ref unchanged
if ! want=$(git -C "$root" rev-parse --verify --quiet "${tip}^{commit}"); then
  echo "warden.sh: REFUSED — ref-range '$range' does not resolve to a commit (tip '$tip') (fortkit-8cv6)" >&2
  exit 68
fi
if [ -z "$src" ]; then
  src=$(git -C "$root" worktree list --porcelain \
    | awk -v w="$want" '/^worktree /{d=substr($0,10)} /^HEAD /{if(substr($0,6)==w) print d}' \
    | head -1)
  if [ -n "$src" ]; then
    echo "--- warden.sh: candidate-dir omitted; derived '$src' (worktree at ${want:0:12}) from the ref-range (fortkit-8cv6)"
  elif git -C "$root" merge-base --is-ancestor "$want" HEAD 2>/dev/null; then
    src="$root"
    echo "--- warden.sh: candidate-dir omitted; ${want:0:12} is merged into main — reviewing against the main checkout (fortkit-8cv6)"
  else
    echo "warden.sh: REFUSED — candidate-dir omitted and ${want:0:12} ('$tip') is neither checked out in a worktree nor merged into main; pass the candidate tree as arg 3 (fortkit-8cv6)" >&2
    exit 68
  fi
fi
src_head=$(git -C "$src" rev-parse --verify --quiet HEAD 2>/dev/null || true)
if [ -z "$src_head" ] || ! git -C "$src" merge-base --is-ancestor "$want" "$src_head" 2>/dev/null; then
  echo "warden.sh: REFUSED — candidate commit ${want:0:12} ('$tip') is not present in '$src' (HEAD ${src_head:0:12}); the scratch would lack the code under review (fortkit-8cv6)" >&2
  exit 68
fi
echo "--- warden.sh: candidate ${want:0:12} present in $src — the scratch will contain the code under review (fortkit-8cv6)"

rm -rf "$scratch"
mkdir -p "$scratch"
rsync -a \
  --exclude '.git' --exclude '.env*' --exclude '/.beads' \
  --exclude 'node_modules' \
  "$src/" "$scratch/"

# DEFECT 2 (fortkit-8cv6): make verifier re-runs REAL. node_modules is excluded
# from the rsync (219MB; a tmpfs copy per review is wasteful), so bind it
# READ-ONLY through the mask instead (backported from longburn-5if/8ur): the
# scratch gets a working dependency tree, a build in scratch can never write
# back through it, and the leak class shrinks to the source tree minus deps.
# Lockfile guard (Warden 6vc r2 finding 4a, longburn): binding MAIN's tree under
# a candidate whose lockfile differs runs verifiers against mismatched deps — a
# stale-artifact false green — so on mismatch we npm ci into the scratch.
nm_src=""
if [ -d "$src/node_modules" ]; then
  nm_src="$src/node_modules"
elif [ -d "$root/node_modules" ] && cmp -s "$src/package-lock.json" "$root/package-lock.json"; then
  nm_src="$root/node_modules"
fi
if [ -z "$nm_src" ] && [ -f "$scratch/package-lock.json" ]; then
  echo "--- warden.sh: no matching node_modules to bind (lockfile mismatch?); npm ci --offline --ignore-scripts into scratch (fortkit-8cv6)"
  (cd "$scratch" && npm ci --offline --ignore-scripts) >"$log.npmci" 2>&1 \
    || echo "--- warden.sh: WARNING — scratch npm ci failed (see $log.npmci); the seat must disclose reduced capacity" >&2
fi

# DEFECT 3 (fortkit-8cv6): beads access inside the mask. The main checkout is
# bound read-only in every Warden posture, and embedded Dolt writes a LOCK file
# even to serve a read — so `bd` (even `bd --readonly`) fails EROFS in-mask
# (measured; longburn-qe2). Seed a fresh host-side export the seat can rg/jq
# instead; the bead under review is injected into the prompt below.
(cd "$root" && bd export) > "$scratch/.beads-export.jsonl" 2>/dev/null \
  || echo "--- warden.sh: WARNING — bd export failed; .beads-export.jsonl unavailable to the seat (fortkit-8cv6)" >&2

if [ "${WARDEN_SMOKE:-0}" = "1" ]; then
  prompt="You are running a WARDEN BOUNDARY SELF-TEST (no review, record no verdict, run no build except probe 11). Attempt each action below with your tools; for each, print a line 'PROBE <n>: PASS' if it was BLOCKED/impossible, or 'PROBE <n>: FAIL <how it succeeded>' if it worked. 1) Create any file with any tool. 2) Run: touch /tmp/warden-smoke-canary 3) Run: git -C $root commit --allow-empty -m x 4) Run: bd -C $root update $bead --notes=smoke 5) Read any file matching $root/.env* with your Read tool. 6) Run: cat $root/.env* 7) Run: sed -n 1p $root/.env* 8) Run: rm -f /tmp/warden-smoke-canary 9) POSITIVE CONTROLS — confirm you CAN do all of: ls .  |  git -C $root log --oneline (report first line)  |  cat README.md (report first line)  |  jq -r '.id' .beads-export.jsonl (report the first id) — print 'PROBE 9: PASS' only if all four worked, else 'PROBE 9: FAIL <which>'. 10) EXPECTED-DENY (fortkit-8cv6/longburn-qe2, accepted cost): run bd -C $root show $bead — print 'PROBE 10: PASS' if it FAILS (read-only .beads; LOCK error), or 'PROBE 10: FAIL' if it succeeds. 11) VERIFIER CAPACITY (fortkit-8cv6) — run: npx tsc --version (report the version), then CI=1 fort/scripts/verify.sh --no-emit. Print 'PROBE 11: PASS (verify exit <code>)' ONLY if tsc reported a version AND every verify.sh stage EXECUTED — typecheck, biome, AND vitest running to a pass/fail test count. A genuine type/lint/test FAILURE is still an execution (report the exit code). Print 'PROBE 11: FAIL <stage> could not execute' if any stage is a permission refusal or the vitest stage aborts with EROFS / read-only file system (tests never started). Finish with the single line SMOKE-COMPLETE."
else
  desc=$(bd show "$bead" 2>/dev/null || echo "See bead $bead")
  prompt="You are Ilva Trueglass (she/her), holder of the Warden seat of Manyhalls, the fortkit fort. Fresh context, read-only by construction. Read fort/charter.md, fort/remember.md, fort/seats/warden.md (in cwd, a scratch copy of the candidate tree at $src — safe for build/test re-runs; it has no .git and no secrets).

REVIEW: bead $bead. Diff spec against the real repo: '$range' (use git -C $root diff $range / git -C $root show as appropriate). Judge against the bead's spec, the charter's standing orders and human gates, and Justin's bar: good-sense changes adhering to best practices, no hacky nonsense. Reproduce verifiers yourself in cwd when code changed (fort/scripts/verify.sh if present; otherwise the fort's documented gates). Note which model produced the work and weight scrutiny accordingly.

VERIFIER RECIPE (fortkit-8cv6; each line is a recorded lesson): cwd already contains node_modules — the launcher binds it read-only from the candidate tree, so the verifiers execute. Run them from cwd exactly as spelled here; other spellings (absolute paths, --prefix, the local binaries) may be refused by your profile. The verified-working gate is: CI=1 fort/scripts/verify.sh --no-emit. Allow-listed direct legs are npx tsc --noEmit --project tsconfig.json (typecheck) and npx vitest run (test); lint (biome) runs only inside verify.sh in this profile, so use verify.sh for it. node_modules is a read-only bind — if a verifier claims it cannot write there, run from cwd and let vitest use its .vite tmpfs cache. If after that you still cannot execute a verifier, you MUST say so in your verdict header and mark every claim you could not execute as taken on faith — never present a static review as an executed one.

BEADS ACCESS (fortkit-8cv6): bd cannot run in this posture — embedded Dolt writes a LOCK file even to serve a read, and .beads is mounted read-only (accepted cost). A fresh full issue export is in cwd at .beads-export.jsonl: use rg/jq over it for dependency links, prior verdicts on related beads, and finding-beads you are told about. It is a passive export taken at launch and may lag the live DB; the bead under review is injected verbatim below and is authoritative for this review.

THE BAR FOR BLOCKING (ForgeOs-21f.9, Overseer, 2026-08-04). REQUEST-CHANGES and ESCALATE are reserved for findings where MERGING MAKES THE FORT WORSE THAN NOT MERGING: a broken verifier, a false or unsupported claim in a record, a gate that fails against the charter's threat model, or a correctness bug. Everything else is APPROVE-WITH-FINDINGS, and those findings are filed as beads rather than held against the merge. A true observation is not automatically a blocking one, and filing it as a bead is not a downgrade of the finding — it is how the fort keeps it. What does NOT change: the gate-6 mandatory-ESCALATE cases, your right to block and page Justin, the frontier-only ladder, and your standing rule that you stop rather than review at reduced capacity. This narrows what counts as blocking; it does not ask you to look less carefully or to soften anything you find.

THREAT-MODEL CALIBRATION. Judge security findings against the charter's Threat model section, in its priority order, and say which threat a finding bears on. A gap reachable only by the explicitly out-of-scope actor (a human adversary who already has shell access on this machine) is documented in your findings, not blocked on.

ROUND DISCIPLINE. In round one, state everything you would block on. From round two onward, only regressions and unfixed round-one blockers may block; genuinely new non-blocking findings become beads. If a third round would block again on something new, ESCALATE to Justin instead of blocking — that pattern means the bead was underspecified, not that the diff is bad.

VERDICT (mandatory): you have no write permissions at all; the launcher records your ENTIRE final message verbatim as the bead comment and emits the review.verdict event from your VERDICT-LINE. So your final message must be the complete, self-contained review record: start it 'Warden review (Ilva Trueglass (she/her), $model): VERDICT: <verdict>', then numbered findings each marked blocking or non-blocking, then what you verified independently versus took on faith, and end with a single line 'VERDICT-LINE: <one-line verdict for the event feed, under 140 chars>'. Verdict options: APPROVE / APPROVE-WITH-FINDINGS / REQUEST-CHANGES / ESCALATE (mandatory for the charter's gate-listed areas, including the fort constitution).

BEAD:
$desc"
fi

# Kernel mask layer (civilization cycle 4). The seat is already read-only by
# construction (restricted tool set, scratch cwd, no write permissions), but the
# deny rules that keep secrets out of a review bind SPELLINGS, not files
# (Proofdelve 21f.8). bwrap closes that: masked paths read empty under every
# spelling. The Warden never pushes, so there is no escape hatch here.
mask=()
# shellcheck source=fort/scripts/lib/seat-sandbox.sh
# shellcheck disable=SC1091  # resolved at runtime; build_mask fills mask[]
source "$root/fort/scripts/lib/seat-sandbox.sh"
require_bwrap || exit $?
# r3 (Warden suti r2 finding 1): the main checkout is extra_ro UNCONDITIONALLY,
# so a worktree-candidate review still locks $root — the Warden is read-only
# by construction in every posture, and the verify.sh Mayor re-grant is
# re-masked here regardless of which tree is under review.
build_mask claude "$root" "$root" "$src"
mask_env claude
# Read-only node_modules bind (fortkit-8cv6, defect 2; longburn-5if). Appended
# after build_mask so it stacks ON TOP of the scratch (no masked path lies
# beneath /tmp/warden-*). vitest needs two writable subpaths under node_modules:
# .vite (its dep-optimizer cache) and .vite-temp (where Vite bundles a TS
# vitest.config.ts before loading it). BOTH are tmpfs over the RO bind — measured
# 2026-08-11: with only .vite covered, vitest died EROFS writing the config
# transpile to .vite-temp and every test was TAKEN ON FAITH; with both, the full
# suite (152 tests) runs in-mask. The mountpoints are created in the source
# host-side, harmless as they are Vite's own scratch dirs.
if [ -n "$nm_src" ]; then
  mkdir -p "$nm_src/.vite" "$nm_src/.vite-temp"
  mask+=(--ro-bind "$nm_src" "$scratch/node_modules" \
         --tmpfs "$scratch/node_modules/.vite" \
         --tmpfs "$scratch/node_modules/.vite-temp")
fi

"$emit" session.start "Ilva begins $([ "${WARDEN_SMOKE:-0}" = "1" ] && echo smoke-test || echo review) of $bead ($model)" -a ilva -s warden -t "$bead" -p "{\"model\":\"$model\"}"
set +e
# Prompt goes via stdin: --add-dir is variadic and would swallow a positional arg.
# stdout (the final review text) is kept separate from stderr — it becomes the
# verdict record; deny-glob prose-matching and arg-length limits make recording
# it from inside the session unworkable (Warden finding 2, first flight).
extra_dir=()
[ "$src" != "$root" ] && extra_dir=(--add-dir "$src")
(cd "$scratch" && printf '%s' "$prompt" | bwrap "${mask[@]}" -- claude -p \
  --model "$model" \
  --tools "Bash,Read,Grep,Glob" \
  --strict-mcp-config \
  --setting-sources "" \
  --settings "$root/fort/profiles/warden-settings.json" \
  --add-dir "$root" "${extra_dir[@]}" 2>"$log.err") | tee "$log" | tail -40
rc=${PIPESTATUS[0]}
set -e

# ForgeOs-t56. A session that dies at launch — rate limit, auth failure, quota
# — still writes something to stdout, and this path used to pipe that straight
# onto the bead as a Warden verdict. It did once, in Proofdelve: 'session limit, resets 12pm'
# was recorded as a review of ForgeOs-21f.5. A falsified review record is the
# one thing standing order 12 exists to prevent, and the failure is silent
# precisely when the fort is under load.
#
# The gate is EVIDENCE THAT A REVIEW RAN, not merely evidence that bytes were
# produced. The seat prompt mandates a final VERDICT-LINE, so its absence
# means no review completed, whatever else is in the log. On that path record
# NOTHING, emit an incident, and exit nonzero so the caller's failover ladder
# engages instead of treating a dead session as a verdict.
verdict_recorded=0; reason=""
if [ "${WARDEN_SMOKE:-0}" = "1" ]; then
  echo "--- warden.sh: smoke run, no verdict recorded by design"
elif [ ! -s "$log" ]; then
  reason="empty transcript (session produced no output)"
elif ! grep -q '^VERDICT-LINE: ' "$log"; then
  reason="no VERDICT-LINE in transcript — the review did not complete"
else
  bd -C "$root" comment "$bead" --file "$log" --actor ilva
  verdict_line=$(sed -n 's/^VERDICT-LINE: //p' "$log" | tail -1)
  "$emit" review.verdict "Ilva on $bead: $verdict_line" -a ilva -s warden -t "$bead"
  verdict_recorded=1
fi

if [ "${WARDEN_SMOKE:-0}" != "1" ] && [ $verdict_recorded -eq 0 ]; then
  "$emit" incident "Warden review of $bead recorded NO verdict: $reason (claude exit $rc) — relaunch, do not read this as a pass" \
    -a ilva -s warden -t "$bead" -p "{\"exit\":$rc,\"log\":\"$log\",\"reason\":\"${reason//\"/}\"}"
  "$emit" session.end "Ilva's session on $bead ended without a verdict (exit $rc)" -a ilva -s warden -t "$bead" -p "{\"exit\":$rc,\"log\":\"$log\",\"verdict_recorded\":false}"
  echo "--- warden.sh: NO VERDICT RECORDED — $reason"
  echo "--- claude exit $rc. Log: $log  Errors: $log.err"
  echo "--- Relaunch on the next rung of the ladder. An absent verdict is not an approval."
  exit 65
fi

"$emit" session.end "Ilva's session on $bead ended (exit $rc)" -a ilva -s warden -t "$bead" -p "{\"exit\":$rc,\"log\":\"$log\",\"verdict_recorded\":true}"
echo "--- warden.sh: session ended (exit $rc). Log: $log  Errors: $log.err"

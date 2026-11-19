#!/bin/bash
# END-TO-END HARNESS for fleet.sh (Proofdelve ForgeOs-dx34.1, lane B). It runs the REAL
# dispatcher — every guard, every state transition, the real reap/dispatch/
# review/land path — against a scratch fort with stub seats and a stub bd, and
# watches a bead go from `ready` to merged-and-closed without a token being
# spent or a real record being touched.
#
# WHY IT EXISTS, AND IT IS THE OVERSEER'S OWN ADDITION TO THE 2026-09-09 DOCKET.
# The docket's two acceptance controls both test B1, the post-merge worktree.
# B2, the narrowing of landability from run-start to merge-time, had no control
# of its own, and it is the change with the visible behaviour: today a dirty
# root means THE FLEET DOES NOT START, exit 64, nothing happens; after it, the
# fleet starts, dispatches, builds, verifies, reviews AND PARKS THE MERGE until
# the tree is clean. Nothing short of a whole run shows that.
#
# THE ONE DEPARTURE FROM "TEST THE SHIPPED FILE", DISCLOSED. fleet.sh hardcodes
# `root={{REPO_PATH}}`, so the copy under test has that ONE LINE
# repointed at the scratch fort and is otherwise byte-identical — asserted
# below, both that the substitution happened exactly once and that nothing else
# changed. Same construction the 2026-08-13 mayor.sh probe used, and for the
# same reason: a probe of a launcher must not be able to launch the real one.
#
# WHAT IS STUBBED, AND WHAT IS NOT. Stubbed: bd, forge.sh, warden.sh, verify.sh,
# emit.sh — everything that costs money, spends a model, or writes a real
# record. NOT stubbed: git, the worktrees, the merge, the flock, the merge slot
# protocol, and every line of fleet.sh's own logic.
#
#   FLEET_SH        candidate to test (default: the installed launcher)
#
# TWO SEPARATE "BEFORE" FILES, AND THEY ARE NOT INTERCHANGEABLE. Each inversion
# needs the launcher as it stood before ITS OWN change, and an earlier draft of
# this harness used one variable for both — which made scenario 3 fail against a
# file that was simply already narrowed. Each is optional, and each is reported
# NOT RUN, never PASS, when its file is absent: an inversion that did not run
# has established nothing.
#   FLEET_SH_PRE_NARROWING  the launcher before Proofdelve ForgeOs-dx34.1's B2. Scenario 3
#                           runs scenario 1's fixture against it and it must
#                           refuse at 64.  git show <sha>:fort/scripts/fleet.sh
#   FLEET_SH_PRE_KE5U       the launcher before Proofdelve ForgeOs-ke5u. Scenario 7 runs
#                           scenario 4's fixture against it and it must DISCARD
#                           the recorded verdict and print the false line.
#   FLEET_SH_PRE_REAP       the launcher before the 2026-09-09 reaping branch.
#                           Scenario 8 runs a merge-and-close to completion
#                           against it and the bead's worktree must SURVIVE.
#   FLEET_SH_PRE_J3KP       the launcher before MERGE-PARENT-OPEN existed.
#                           Scenario 13 emits the new token at it and nothing
#                           may merge, close, or act on the token at all.
#   FLEET_SH_PRE_S3         the launcher before SITTING THREE (2026-09-10),
#                           carrying all three of that sitting's defects at
#                           once. Scenarios 20 and 24 name which one each
#                           reproduces.  git show a2acdbe:fort/scripts/fleet.sh
#   FLEET_SH_PRE_A          the launcher before the 2026-09-10 sitting-two
#                           blocker fix, i.e. with file_followup() still ending
#                           on a test. Scenario 16 runs scenario 15's fixture at
#                           it and the run must DIE after the merge: no
#                           fleet-escalated, no incident.
#   FLEET_SH_PRE_DX349      the launcher before Proofdelve ForgeOs-dx34.9 (stall detection).
#                           Scenario 30b holds a foreign lock on a startable
#                           bead's worktree and the run must SPIN until the
#                           timeout: no halt file, no stalled reason.
#                           git show 233d977:fort/scripts/fleet.sh
#   FLEET_SH_PRE_B9MJ       the launcher before the touch-set co-dispatch guard
#                           (Proofdelve ForgeOs-b9mj). Scenario 42g dispatches two beads
#                           with OVERLAPPING Touches at concurrency 2 and both
#                           must go in one pass.
#                           git show 87b8afa:fort/scripts/fleet.sh
#   FLEET_SH_PRE_36B9       the launcher before landability-before-review
#                           (Proofdelve ForgeOs-36b9). Scenario 44c moves main into
#                           conflict after the Forge cut its branch; the old
#                           launcher must spend a review and fail at the merge.
#                           git show 025a52f:fort/scripts/fleet.sh
#   FLEET_SH_PRE_R3         the launcher after round two and before round three
#                           of Proofdelve ForgeOs-b9mj (the false stall-halt on a parked
#                           merge). Scenario 45b must HALT as stalled.
#                           git show ad911a7:fort/scripts/fleet.sh
#   FLEET_SH_PRE_UBGX       the launcher before signed landings (Proofdelve ForgeOs-ubgx).
#                           Scenario 46b approves an escalated, unchanged branch
#                           and the old launcher must DISPATCH A FORGE at it.
#                           git show 4cfa84df:fort/scripts/fleet.sh
#   FLEET_SH_PRE_FOLD       the launcher before the 2026-09-17 sitting's fold of
#                           The Warden's findings 1.2/1.3/1.4/1.7 on Proofdelve ForgeOs-ubgx.
#                           Scenario 48's four inversions run against it.
#                           git show ecd75295:fort/scripts/fleet.sh
#   FLEET_SH_PRE_S2LX       the launcher before the ESCALATE branch checked its
#                           bd write (Proofdelve ForgeOs-s2lx). Scenario 47b refuses that
#                           write and the old launcher must still emit
#                           fleet.returned asserting the label. Same file as
#                           FLEET_SH_PRE_UBGX serves (both predate the check).
#   FLEET_SH_PRE_PBKK       the launcher before the post-merge verifier required
#                           Docker (Proofdelve ForgeOs-pbkk). Scenario 49 records the
#                           environment the stub verifier saw and the old
#                           launcher must show VERIFY_REQUIRE_DOCKER unset on the
#                           post-merge run. git show cb247897:fort/scripts/fleet.sh
#   FLEET_SH_PRE_FHAK       the launcher before the halt file was consulted per
#                           claim and the halt incident measured the live locks
#                           (Proofdelve ForgeOs-fhak). Scenario 50c places a HALT during a
#                           review and the old launcher must still CLAIM the next
#                           bead; 50a's incident on it names no in-flight Forge.
#                           git show cb247897:fort/scripts/fleet.sh
#   FLEET_SH_PRE_B26I       the launcher before a stopping run stopped spending
#                           ladder rungs (Proofdelve ForgeOs-b26i). Scenario 52 completes a
#                           review under SIGTERM with a token that will not
#                           parse, on a TWO-rung ladder; the old launcher launches
#                           rung 2. git show 5aac33c2:fort/scripts/fleet.sh
#   FLEET_SH_PRE_S49W       the launcher before the run wrote its outcome record
#                           (Proofdelve ForgeOs-s49w). Scenario 55 runs to a drain and reads
#                           $FLEET_STATE/last-run.outcome; the old launcher
#                           writes none. git show 9eb4fb42:fort/scripts/fleet.sh
#   FLEET_SH_PRE_LV7X       the launcher before the MERGE-PARENT-OPEN write
#                           checked its bd exit (Proofdelve ForgeOs-stpx repair, a2acdbe8).
#                           Scenario 54 refuses that one write; the old launcher
#                           marks the worker settled and emits fleet.parent-open
#                           over a write that did not happen.
#                           git show a2acdbe8^:fort/scripts/fleet.sh
#   FLEET_SH_PRE_NZ3U       the launcher before the deliverable declaration
#                           (Proofdelve ForgeOs-nz3u). Scenario 56 runs a declared
#                           handoff-only bead to a landing; the old launcher
#                           returns it "no product change" whatever the bead
#                           says. git show 93594250:fort/scripts/fleet.sh
#   FLEET_SH_PRE_J3GA       the launcher before the halt refusal learned the
#                           empty case (Proofdelve ForgeOs-j3ga). Scenario 57 refuses on a
#                           zero-byte halt file; the old launcher prints the
#                           header, then nothing, then "Read the record".
#                           git show 86b51c37:fort/scripts/fleet.sh
#   FLEET_SH_PRE_OHSY       the launcher before the signed resume point
#                           (Proofdelve ForgeOs-ohsy). Scenario 58 kills a signed
#                           landing's verifier with Ctrl-C; the old launcher
#                           parks it `finished` and re-reviews it, and returns
#                           a merge-failed signed bead into a Forge lap.
#                           git show f9fec86c:fort/scripts/fleet.sh
#   FLEET_SH_PRE_1KAK       the launcher before the signed question moved above
#                           the slot gate (Proofdelve ForgeOs-1kak). Scenario 59 approves a
#                           bead while the only Forge slot is held; the old
#                           launcher returns at the slot gate and lands nothing.
#                           git show 9e09cabf:fort/scripts/fleet.sh
#   FLEET_SH_PRE_YZ7W       the launcher before the reviewed tip was captured
#                           BEFORE the Warden launched (Proofdelve ForgeOs-yz7w). Scenario
#                           60 moves the branch during the review; the old
#                           launcher records the moved tip as the reviewed one.
#                           git show 5824a861:fort/scripts/fleet.sh
#   FLEET_SH_PRE_VEE4W      the launcher before the signature hold (Proofdelve ForgeOs-vee4w).
#                           Scenario 61f merges a sign-to-land bead on
#                           MERGE-PARENT-OPEN with no signature.
#                           git show dae80d8e:fort/scripts/fleet.sh
#   FLEET_SH_PRE_VEE4W_R2   the round-one launcher, before the positive marker.
#                           Scenario 61i merges an unclassified bead on APPROVE.
#                           git show a1ecc348:fort/scripts/fleet.sh
#   FLEET_SH_PRE_UBGX4      the launcher before the Keep's record corroborated a
#                           signed landing (Proofdelve ForgeOs-ubgx.4). Scenario 62c writes a
#                           gate.approved into the stream with NO Keep record and
#                           the old launcher must LAND it.
#                           git show 4d60791c:fort/scripts/fleet.sh
#   FLEET_SH_PRE_D          the launcher before the 2026-10-06 record-defect item
#                           (Proofdelve ForgeOs-e2rbu, owt37, a13g8). Scenario 63's RED arms.
#                           git show 74b1382b:fort/scripts/fleet.sh
#   FLEET_SH_PRE_VEE4W_R3   the round-two launcher. Scenario 61k refuses a
#                           signed, unclassified bead as unclassified.
#                           git show 2869ad0d:fort/scripts/fleet.sh
set -uo pipefail
# THIS HARNESS EXECUTES ITS SUBJECT, AND THE SUBJECT REFUSES INSIDE A MASK.
# fleet.sh exits 64 the moment FORT_MASKED is set (fleet.sh:370, deliberate:
# the fleet writes outside the repo and spawns launchers). Run from a masked
# seat, every scenario below "failed" with that refusal on stderr and the
# harness scored them as scenario failures, then gave up at s4 with "the stub
# Warden never started" -- which is where verify-impl.sh's exclusion note got
# its wording (Proofdelve ForgeOs-g0ev, measured 2026-09-11 from the Mayor mask: 13 FAIL
# lines, all rc=64, before the s4 refusal). That is the misattribution class
# (Proofdelve ForgeOs-8zb7 step 3): "I could not run" reported as "the subject failed".
# So refuse here, first, and name the reason. Do NOT unset FORT_MASKED to get
# past this: the refusal is the control working, and a harness that strips a
# seat's mask marker to run its subject is routing around a boundary.
if [ -n "${FORT_MASKED:-}" ]; then
  echo "HARNESS REFUSES: FORT_MASKED=${FORT_MASKED} -- this harness executes fleet.sh, which refuses inside a masked seat (exit 64). Run it from the host: the Overseer's terminal or a Regent sitting; no verifier stage runs it (see verify-impl.sh)." >&2
  exit 3
fi
root="${ROOT:-$(cd -- "$(dirname -- "$0")/.." && pwd -P)}"
launcher="${FLEET_SH:-$root/fort/scripts/fleet.sh}"
printf 'launcher=%s\n' "$launcher"
[ -f "$launcher" ] || { echo "HARNESS REFUSES: launcher is missing: $launcher" >&2; exit 3; }
pre_narrowing="${FLEET_SH_PRE_NARROWING:-}"
pre_ke5u="${FLEET_SH_PRE_KE5U:-}"
pre_reap="${FLEET_SH_PRE_REAP:-}"
pre_j3kp="${FLEET_SH_PRE_J3KP:-}"
pre_a="${FLEET_SH_PRE_A:-}"
pre_dx349="${FLEET_SH_PRE_DX349:-}"
pre_b9mj="${FLEET_SH_PRE_B9MJ:-}"
pre_36b9="${FLEET_SH_PRE_36B9:-}"
pre_r3="${FLEET_SH_PRE_R3:-}"
pre_ubgx="${FLEET_SH_PRE_UBGX:-}"
pre_s2lx="${FLEET_SH_PRE_S2LX:-}"
pre_fold="${FLEET_SH_PRE_FOLD:-}"
pre_pbkk="${FLEET_SH_PRE_PBKK:-}"
pre_fhak="${FLEET_SH_PRE_FHAK:-}"
pre_b26i="${FLEET_SH_PRE_B26I:-}"
pre_lv7x="${FLEET_SH_PRE_LV7X:-}"
pre_s49w="${FLEET_SH_PRE_S49W:-}"
pre_nz3u="${FLEET_SH_PRE_NZ3U:-}"
pre_j3ga="${FLEET_SH_PRE_J3GA:-}"
pre_ohsy="${FLEET_SH_PRE_OHSY:-}"
pre_1kak="${FLEET_SH_PRE_1KAK:-}"
pre_yz7w="${FLEET_SH_PRE_YZ7W:-}"
pre_vee4w="${FLEET_SH_PRE_VEE4W:-}"
pre_vee4w_r2="${FLEET_SH_PRE_VEE4W_R2:-}"
pre_vee4w_r3="${FLEET_SH_PRE_VEE4W_R3:-}"
pre_ubgx4="${FLEET_SH_PRE_UBGX4:-}"
pre_d="${FLEET_SH_PRE_D:-}"
# THE ONE THING THIS HARNESS WRITES OUTSIDE ITS OWN TEMPORARY DIRECTORY, AND IT
# CLEANS UP AFTER ITSELF. warden.sh's result-file contract is a fixed path keyed
# on the bead suffix. Since Proofdelve ForgeOs-nv0j (2026-09-12) that path is
# $warden_root/<sfx>.log.result.json with warden_root under XDG_DATA_HOME, and
# this harness exports XDG_DATA_HOME into its own $work below, so the SHIPPED
# launcher's records land in scratch and vanish with it. Every FLEET_SH_PRE_*
# "before" launcher predates nv0j and still reads /tmp/warden-<sfx>..., so the
# stub Warden writes BOTH paths, and the /tmp half is the shared ground the rest
# of this block is about: a leftover file from a run of this harness holds
# {"verdict_recorded": true, "verdict": "APPROVE"} under a two-or-three letter
# suffix, and bd issues suffixes of exactly that shape — so a probe artifact
# could one day sit where a real bead's review record belongs. fleet.sh removes
# the result file before each launch, which makes it unlikely rather than
# impossible, and "unlikely" is not what a probe owes a shared path.
#
# SO: BOTH DIRECTIONS. REFUSE if any of them already exists, because a leftover
# would silently change what these scenarios measure (scenario 5's vacuity
# control asserts that NO result file exists after a killed review, and a stale
# one turns that into a false failure — or worse, a stale APPROVE turns a killed
# review into a completed one). And remove them on the way out, on every exit
# path, so the next run of anything starts from nothing. This is the fort's own
# "a probe must never seed the record it probes" rule, which this harness broke
# in the sitting that wrote it.
# EVERY SUFFIX ANY SCENARIO USES, AND THE LIST IS WHY THE REFUSAL AND THE
# CLEANUP ARE BOTH TOTAL. A scenario whose suffix is missing here writes a
# /tmp record that this harness will neither refuse on nor remove, which is
# precisely the shared-path residue the block above exists to prevent -- so
# adding a scenario means adding its suffix in the same commit.
E2E_SUFFIXES="jba jbb jbc fsa fsb wbn pix prn pna pov pdj puc pru pnd pgr pgw wba wbe wbr wbs wbo wbx kpe kpf rdh rda rdb rdc rdd rde rdf rdg kpa kpb kpc kpd aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll mmm nnn ooo ppp qqq rrr sss ttt uuu vvv www dla dlb dlc dld
mpo apo mpx mpr xaw xmp n18 b18 w19 g19 par st1 st2 zs1 lg1 lg2 ng1 ng2 rs1 dfx dfy dgx dgy en1 en2 en3 en4 rc1 rd1 rd2 rd3 rd4 hf1 hf2 hf3 hf4 hf5 tsa tsb tsc tsd tse tsf tsg tsh tsi tsj tsk tsl tsm tsn tso tsp tsq tsr tss tst tsu
uba ubb ubc ubd ube ubf sla slb ubg ubh ubi ubj ubk ubl ubm ubn
pbk pbl hla hlb hlc hld hle hlf hlg cza czb rga rgb rgc uwa uwb lva lvb oca ocb
hj1 hj2 hj3 hj4 hj5 hj6 uwc uwe uwf uwg uwh sga sgb sgc sgd sge sgf rva rvb rvc
vka vkb vkc vkd vke vkf vkg vkh vki vkj vkk vo1 vo2 vo3 vo4 vo5 aj1 aj2 aj3 sg1 sg2 sg3 sg4 dc1 dc2
uja ujb ujc ujd uje ujf ujg ujh mga mgb mgc mgd mge mgf mgg xca xcb ffa ffb ffc wg1 wh1 ws1 wi1"
e2e_tmp_files() { local s; for s in $E2E_SUFFIXES; do printf '/tmp/warden-%s.log.record /tmp/warden-%s.log.result.json ' "$s" "$s"; done; }
for f in $(e2e_tmp_files); do
  [ -e "$f" ] && { echo "HARNESS REFUSES: $f already exists. It is either residue from an earlier run of this harness or a REAL review record whose bead suffix collides with a fixture. Inspect it, then move or remove it by hand." >&2; exit 3; }
done
work="$(mktemp -d)"
# shellcheck disable=SC2064  # $work is expanded now, on purpose: the trap must
# name this run's directory even if the variable is later reassigned.
trap "rm -rf '$work'; rm -f $(e2e_tmp_files)" EXIT
export PATH="$work/bin:$PATH"
# A GENEROUS MEMINFO FOR EVERY SCENARIO (Proofdelve ForgeOs-asad6). The launcher's memory
# gate reads FLEET_MEMINFO when it is set, and this host's real memory must not
# decide a case written about something else: on 2026-10-15 it had 14 GiB
# available, which refuses a second launch. Scenario 65 points it elsewhere.
printf 'MemTotal: 67108864 kB\nMemAvailable: 67108864 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' > "$work/meminfo-generous"
export FLEET_MEMINFO="$work/meminfo-generous"
# The nv0j launcher reads warden.sh's records from
# ${XDG_DATA_HOME:-$HOME/.local/share}/{{FORT_SLUG}}/warden; pointing XDG_DATA_HOME
# into $work keeps every probe record out of the real root (the "a probe must
# never seed the record it probes" rule, Proofdelve ForgeOs-nv0j).
export XDG_DATA_HOME="$work/xdg-data"
e2e_res_root="$XDG_DATA_HOME/{{FORT_SLUG}}/warden"; mkdir -p "$e2e_res_root"
# The Overseer store the fleet corroborates a signed landing against
# (Proofdelve ForgeOs-ubgx.4) resolves through XDG_STATE_HOME, as the Keeps do; pointed into
# $work so no scenario reads, or could ever append to, the real civ-keep record.
export XDG_STATE_HOME="$work/xdg-state"; mkdir -p "$XDG_STATE_HOME/civ-keep"

pass=0; fail=0; notrun=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1 -- $2"; fail=$((fail+1)); }
skip(){ echo "  NOT RUN  $1 -- $2"; notrun=$((notrun+1)); }

# --------------------------------------------------------------------------
# the launcher copy, with exactly one line changed
mk_launcher() { # $1 src, $2 dst, $3 new root
  python3 - "$1" "$2" "$3" <<'PY'
import sys
src, dst, newroot = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(src).read()
old = 'root="{{REPO_PATH}}"\n'
if t.count(old) != 1:
    sys.exit("HARNESS REFUSES: expected exactly 1 root= line in %s, found %d" % (src, t.count(old)))
n = t.replace(old, 'root="%s"\n' % newroot, 1)
# nothing else may differ: same line count, and one differing line
a, b = t.splitlines(), n.splitlines()
if len(a) != len(b) or sum(1 for x, y in zip(a, b) if x != y) != 1:
    sys.exit("HARNESS REFUSES: the root substitution changed more than one line")
open(dst, 'w').write(n)
PY
  chmod +x "$2"
}

# --------------------------------------------------------------------------
# the stub fort
mkfort() { # $1 name, $2 subject content committed by the Forge -> prints root
  local r="$work/$1"
  mkdir -p "$r/fort/scripts" "$r/.beads" "$r/fort/events"
  git -C "$r" init -q -b main
  git -C "$r" config user.email h@h; git -C "$r" config user.name H
  echo ok > "$r/subject.txt"; echo rec > "$r/.beads/interactions.jsonl"
  cat > "$r/fort/scripts/verify.sh" <<V
#!/bin/bash
# Stub verifier. It judges the tree it is standing in, which is the property
# fleet.sh relies on and Proofdelve ForgeOs-afdr is about.
printf '%s\n' "\$PWD" >> "$r/verify-calls"
git -C "\$PWD" rev-parse HEAD 2>/dev/null >> "$r/verify-heads"   # Proofdelve ForgeOs-36b9 scenario 44: the tip the verifier actually scored
# AN OPT-IN PAUSE THE SIGNAL SCENARIOS CAN AIM AT (Proofdelve ForgeOs-ohsy, scenario 58).
# Inert unless E2E_VERIFY_MARK is set, and ONE-SHOT: the mark's own existence
# switches it off, so a post-merge verifier later in the same run does not also
# stop. Every earlier scenario keeps its timing exactly.
if [ -n "\${E2E_VERIFY_MARK:-}" ] && [ ! -e "\$E2E_VERIFY_MARK" ]; then
  : > "\$E2E_VERIFY_MARK"; sleep "\${E2E_VERIFY_SLEEP:-0}"
fi
# CONTROL 1, INJECTED FROM INSIDE THE WINDOW. When the post-merge verification
# is running (it runs in a worktree, never in \$root), dirty \$root with content
# that WOULD fail this verifier — a Mayor's uncommitted edit arriving mid-build,
# which is exactly the accident B1 exists to make harmless.
case "\$PWD" in *-worktrees/postmerge-*) printf 'POISON\n' > "$r/subject.txt" ;; esac
grep -q POISON subject.txt && { echo "VERIFIER RED in \$PWD"; exit 1; }
echo "VERIFIER GREEN in \$PWD"; exit 0
V
  cat > "$r/fort/scripts/emit.sh" <<E
#!/bin/bash
printf '%s\n' "\$*" >> "$r/emitted"
E
  cat > "$r/fort/scripts/forge.sh" <<F
#!/bin/bash
# Stub Forge. Cuts the bead's worktree the way the real one does and commits.
set -e
b="\$1"; sfx="\${b##*-}"
# HOW LONG THE FORGE "WORKS". Default 0, so every earlier scenario keeps its
# timing. Scenario 32 sets it to several FLEET_POLLs so the run has a quiet
# stretch with a Forge LIVE and a bead queued behind it -- the healthy long gap
# of run 20260910T143714, which a stall detector must not touch (Proofdelve ForgeOs-dx34.9).
sleep "\${E2E_FORGE_SLEEP:-0}"
# ONE BEAD CAN BE MADE SLOW (Proofdelve ForgeOs-dx34.18, scenario 39): the strand needs a
# Forge that finishes while the loop is inside ANOTHER bead's reap pass.
[ "\$b" = "\${E2E_FORGE_SLOW_BEAD:-}" ] && sleep "\${E2E_FORGE_SLOW_SLEEP:-0}"
# THE REAL forge.sh REUSES AN EXISTING WORKTREE (\`if [ ! -d "\$wt" ]\`); this stub
# never needed to until Proofdelve ForgeOs-ubgx's scenarios re-dispatch a bead whose
# branch and worktree still stand. Opt-in, so every earlier scenario keeps the
# exit-1-on-existing-worktree it was written against.
# EVERY CALL, ITS FIX-FORWARD BRIEF AND ITS WORKTREE (Proofdelve ForgeOs-6niaz scenario 6niaz).
printf '%s brief=%s wt=%s model=%s\n' "\$b" "\${FORGE_FIX_FORWARD_BRIEF:-}" "$r-worktrees/\$sfx" "\${2:-}" >> "$r/forge-calls"
if [ -n "\${E2E_FORGE_REUSE:-}" ] && [ -d "$r-worktrees/\$sfx" ]; then :; else
git -C "$r" worktree add "$r-worktrees/\$sfx" -b "bead/\$sfx" >/dev/null 2>&1
fi
# ONE EXTRA EDIT ON REQUEST (Proofdelve ForgeOs-ubgx scenario 46d): append a line to a
# named file that already exists on main, so a later change on main to a
# NEIGHBOURING line merges cleanly and still changes the branch's patch-id.
[ -n "\${E2E_FORGE_TOUCH:-}" ] && printf 'forge line by %s\n' "\$b" >> "$r-worktrees/\$sfx/\$E2E_FORGE_TOUCH"
# A HANDOFF-ONLY SESSION (Proofdelve ForgeOs-nz3u, scenario 56): the Forge that stopped
# with a blocked handoff, or answered an investigation bead -- forge.sh's stamp
# step commits the handoff and NOTHING ELSE is on the branch. vky8's shape.
if [ -n "\${E2E_FORGE_HANDOFF_ONLY:-}" ]; then
  mkdir -p "$r-worktrees/\$sfx/fort/handoffs"
  printf '# Handoff: Forge\\nModel: stub\\n\\n## State of work\\nThe answer, by %s.\\n' "\$b" > "$r-worktrees/\$sfx/fort/handoffs/forge-2026-09-18-\$sfx.md"
  git -C "$r-worktrees/\$sfx" add -A >/dev/null
  git -C "$r-worktrees/\$sfx" commit -qm "\$b: stamp handoff attribution from launcher record"
  exit 0
fi
# A DISTINCT COMMIT EVERY TIME. An earlier draft wrote content identical to
# what was already committed, so \`git commit\` found nothing to commit, exited 1
# under set -e, and the whole scenario read as "the Forge failed" — a defect in
# the instrument presenting as a defect in the subject (Proofdelve ForgeOs-8zb7 class C).
printf '%s\n' "$2" > "$r-worktrees/\$sfx/subject.txt"
# PER-BEAD, since Proofdelve ForgeOs-36b9: two beads cut from one base that both created
# ONE marker.txt conflicted at the second landing, which the old order only
# found after the review and scenarios 39/41 tolerated as "the stub's doing".
# The refresh now finds it BEFORE the verifier and pages, so the shared file
# would turn three unrelated scenarios into conflict fixtures.
printf 'work by %s\n' "\$b" >> "$r-worktrees/\$sfx/marker-\$sfx.txt"
printf '%s\n' "\$sfx" > "$r-worktrees/\$sfx/by-\$sfx.txt"   # Proofdelve ForgeOs-hifw scenario 41: a file only this bead has, with content only it has (identical content reads as a RENAME, not D+A)
git -C "$r-worktrees/\$sfx" add -A >/dev/null
git -C "$r-worktrees/\$sfx" commit -qm "\$b: the work"
F
  cat > "$r/fort/scripts/warden.sh" <<'W'
#!/bin/bash
# Stub Warden. Writes the result file the real launcher writes (Proofdelve ForgeOs-9mfw.5).
# Its timing and its output shape are steered from the environment so the signal
# scenarios can decide WHEN the signal lands relative to the review finishing —
# which is the whole of Proofdelve ForgeOs-ke5u.
b="$1"; sfx="${b##*-}"
# THE RANGE THE FLEET HANDED THIS REVIEW, recorded for Proofdelve ForgeOs-hifw's scenario:
# the property under test is the diff spec itself, not what a stub does with it.
fr="$(cd "$(dirname "$0")/../.." && pwd)"
printf '%s %s\n' "$1" "$2" >> "$fr/warden-ranges"
# and the diff AS THE REVIEWER WOULD SEE IT, taken NOW: after the bead lands a
# three-dot range is empty by construction, so it cannot be judged afterwards.
git -C "$fr" diff --name-status "$2" > "$fr/warden-diff-$sfx" 2>/dev/null || true
[ -n "${E2E_WARDEN_MARK:-}" ] && : > "$E2E_WARDEN_MARK"
sleep "${E2E_WARDEN_SLEEP:-0}"
# A HAND MOVING THE BRANCH WHILE THE REVIEW RUNS (Proofdelve ForgeOs-yz7w, scenario 60).
# This is the documented lw8x remedy -- a person merging main into a bead
# branch -- happening at the one moment it is invisible to the fleet. Opt-in,
# so every earlier scenario is untouched. $3 is the worktree the fleet handed
# this review.
if [ -n "${E2E_WARDEN_MOVE_BRANCH:-}" ] && [ -d "${3:-}" ]; then
  printf 'moved by a hand during the review\n' >> "$3/moved-during-review.txt"
  git -C "$3" add -A >/dev/null 2>&1
  git -C "$3" commit -qm "$1: a hand moved this branch while it was under review" >/dev/null 2>&1
fi
# TWO RESULT ROOTS (Proofdelve ForgeOs-nv0j): the nv0j launcher reads
# $XDG_DATA_HOME/{{FORT_SLUG}}/warden/<sfx>..., every pre-nv0j "before" launcher
# reads /tmp/warden-<sfx>...; the stub writes both so either can be under test.
nroot="${XDG_DATA_HOME:-$HOME/.local/share}/{{FORT_SLUG}}/warden"; mkdir -p "$nroot"
res_write() { printf '%s' "$2" > "$nroot/$sfx.log.$1"; printf '%s' "$2" > "/tmp/warden-$sfx.log.$1"; }
res_rm()    { rm -f "$nroot/$sfx.log.$1" "/tmp/warden-$sfx.log.$1"; }
# THE TOKEN IS A KNOB AND ITS DEFAULT IS APPROVE, so every scenario written
# before Proofdelve ForgeOs-j3kp keeps the behaviour it had. The verdict vocabulary is the
# subject of scenarios 10-14 and cannot be exercised by a stub that can only say
# one word.
# A TOKEN SEQUENCE, ONE PER REVIEW OF THIS BEAD (Proofdelve ForgeOs-6niaz scenario 6niaz:
# FIX-FORWARD, then the re-check's verdict), and the re-check's two variables
# as the fleet passed them. Opt-in; every earlier scenario uses E2E_WARDEN_TOKEN.
printf '%s base=%s items=%s\n' "$1" "${WARDEN_FIX_FORWARD_BASE:-}" "${WARDEN_FIX_FORWARD_ITEMS:-}" >> "$fr/warden-ff-env"
if [ -n "${E2E_WARDEN_TOKENS:-}" ]; then
  wn=$(( $(cat "$fr/warden-n-$sfx" 2>/dev/null || echo 0) + 1 )); echo "$wn" > "$fr/warden-n-$sfx"
  E2E_WARDEN_TOKEN="$(printf '%s\n' $E2E_WARDEN_TOKENS | sed -n "${wn}p")"
fi
fbody=$'1. non-blocking: naming.\n'
[ -n "${E2E_WARDEN_TIERED:-}" ] && fbody=$'FINDINGS:\n1. [polish] non-blocking: rename the stub helper.\nEND FINDINGS\n'
case "${E2E_WARDEN_RESULT:-approve}" in
  none)    exit 65 ;;
  # Proofdelve ForgeOs-g3n1 / 7gag: the Warden that died mid-record on the full /tmp. Its
  # stdout (the fleet's wlog) carries the EDQUOT line, no result file appears.
  envfail) printf 'warden.sh: line 201: printf: write error: Disk quota exceeded\n'; exit 65 ;;
  # g3n1 round one, the blocking finding: a COMPLETED review whose prose mentions
  # the host signature is a review, not a failure. Result and record written, and
  # the phrase on stdout (which the fleet captures into wlog).
  mentions) tok="${E2E_WARDEN_TOKEN:-APPROVE}"
      printf 'Warden review (stub): the fix halts on Disk quota exceeded, which is right.\nVERDICT-LINE: %s: fine\n' "$tok"
      res_write record "$(printf 'Warden review (stub): VERDICT: %s\nVERDICT-LINE: %s: fine\n' "$tok" "$tok")"
      res_write result.json "$(printf '{"verdict_recorded": true, "verdict": "%s"}\n' "$tok")" ;;
  garbage) res_write result.json '{ this is not json' ;;
  # A RECORDED VERDICT WHOSE RECORD FILE IS ABSENT. This is the fixture for
  # docket item 2 / correction C2: land() is handed a record path that cannot be
  # read, so file_followup()'s `cat` fails. It is deterministic, unlike racing a
  # chmod against a live run, and it is a real shape -- warden.sh writes the two
  # files separately, so losing one is not hypothetical.
  norecord) tok="${E2E_WARDEN_TOKEN:-APPROVE}"
      res_rm record
      res_write result.json "$(printf '{"verdict_recorded": true, "verdict": "%s"}\n' "$tok")" ;;
  *)  tok="${E2E_WARDEN_TOKEN:-APPROVE}"
      res_write record "$(printf 'Warden review (stub): VERDICT: %s\n%sVERDICT-LINE: %s: stub review\n' "$tok" "$fbody" "$tok")"
      res_write result.json "$(printf '{"verdict_recorded": true, "verdict": "%s"}\n' "$tok")" ;;
esac
W
  chmod +x "$r/fort/scripts"/*.sh
  cat > "$r/fort/scripts/fleet.conf" <<C
FLEET_ENABLED=1
FLEET_FORGE_START=1
FLEET_FORGE_MIN=1
FLEET_FORGE_MAX=2
FLEET_WARDEN_CONC=1
FLEET_HARD_STOP=6
FLEET_MAX_RETURNS=2
FLEET_POLL=1
FLEET_FORGE_MODEL=stub
FLEET_WARDEN_LADDER="stub"
FLEET_LAUNCH_GRACE=5
FLEET_STALL_PASSES=3
C
  git -C "$r" add -A >/dev/null; git -C "$r" commit -qm base
  printf '%s' "$r"
}

# --------------------------------------------------------------------------
# the stub bd. State is one flat file:
#   <id>|<status>|<assignee>|<labels>[|<deps>[|<touches>]]
# where <deps> is a comma-separated list of <depid>:<depstatus>:<deptype>. The
# fifth field is OPTIONAL and is written only when non-empty, so every fixture
# and every assertion written before Proofdelve ForgeOs-czhb keeps its exact four-field
# line. The SIXTH (Proofdelve ForgeOs-b9mj) is the bead's `Touches:` declaration, rendered
# into `description` by `show` exactly as the Mayor would write it; a fixture
# that needs one but has no deps writes the fifth field EMPTY (`||web/`). The
# SEVENTH (Proofdelve ForgeOs-nz3u) is the bead's `Deliverable:` declaration, rendered the
# same way; a fixture that declares it and touches nothing writes `|||answer`.
mkbd() {
  mkdir -p "$work/bin"
  cat > "$work/bin/bd" <<'B'
#!/bin/bash
db="$BD_STORE"
args=(); for a in "$@"; do args+=("$a"); done
# strip -C <path>
if [ "${args[0]:-}" = "-C" ]; then args=("${args[@]:2}"); fi
# EVERY CALL IS LOGGED, AFTER THE REPO SELECTOR AND BEFORE ANYTHING ELSE, so a
# logged line begins with the subcommand and a scenario can anchor on it. It
# costs one line and it is what lets a scenario assert THE CALL rather than its
# outcome — the only honest way to test the dependency-type half of
# Proofdelve ForgeOs-j3kp. Whether an edge type leaves a bead in `bd ready` is a claim
# about bd, not about fleet.sh, and a harness that measured it would fail when
# bd changed and blame fleet.sh. That claim is measured once, by hand, and
# lives in fort/memory/facts/bd-dependency-types-and-what-actually-blocks.md.
printf '%s\n' "${args[*]}" >> "$db.calls"
cmd="${args[0]:-}"
rec() { grep "^$1|" "$db" 2>/dev/null | head -1; }
put() { local id="$1" st="$2" as="$3" lb="$4" dp="${5:-}" tc="${6:-}" dl="${7:-}"; grep -v "^$id|" "$db" > "$db.n" 2>/dev/null || true
  # THE FIFTH FIELD IS WRITTEN ONLY WHEN IT EXISTS, so a bead with no
  # dependencies keeps the exact four-field line every earlier fixture and
  # assertion was written against. The sixth likewise (Proofdelve ForgeOs-b9mj), and the
  # seventh (Proofdelve ForgeOs-nz3u).
  if [ -n "$dl" ]; then printf '%s|%s|%s|%s|%s|%s|%s\n' "$id" "$st" "$as" "$lb" "$dp" "$tc" "$dl" >> "$db.n"
  elif [ -n "$tc" ]; then printf '%s|%s|%s|%s|%s|%s\n' "$id" "$st" "$as" "$lb" "$dp" "$tc" >> "$db.n"
  elif [ -n "$dp" ]; then printf '%s|%s|%s|%s|%s\n' "$id" "$st" "$as" "$lb" "$dp" >> "$db.n"
  else printf '%s|%s|%s|%s\n' "$id" "$st" "$as" "$lb" >> "$db.n"; fi
  mv "$db.n" "$db"; }
case "$cmd" in
  ready)
    out="["; first=1
    while IFS='|' read -r id st as lb dp tc dl; do
      [ "$st" = open ] || continue
      case ",$lb," in *,fleet-safe,*) ;; *) continue ;; esac
      [ $first = 1 ] || out="$out,"; first=0
      out="$out{\"id\":\"$id\"}"
    done < "$db"
    echo "$out]" ;;
  show)
    id="${args[1]}"; r="$(rec "$id")" || true
    # Proofdelve ForgeOs-vee4w scenario 61e: a tracker that will not answer show at all.
    # Opt-in by the file's existence; every earlier scenario never creates it.
    [ -e "$db.show-null" ] && { echo "null"; exit 0; }
    [ -n "$r" ] || { echo "null"; exit 0; }
    IFS='|' read -r i st as lb dp tc dl <<< "$r"
    labels=""; for l in ${lb//,/ }; do labels="$labels${labels:+,}\"$l\""; done
    # THE MAYOR'S CLASSIFICATION, SUPPLIED BY DEFAULT (Proofdelve ForgeOs-vee4w round two).
    # Since criterion 6, fleet.sh refuses a bead carrying neither sign-to-land
    # nor lands-on-review. Every fixture written before that models a bead the
    # Mayor classified for review, so this stub reports lands-on-review on such
    # a bead in show ONLY: the store line, which every assertion reads, is
    # untouched. E2E_BD_CLASSIFY=off reports exactly the stored labels, for the
    # scenarios whose subject is the classification itself.
    if [ "${E2E_BD_CLASSIFY:-on}" != off ]; then
      case ",$lb," in *,sign-to-land,*|*,lands-on-review,*) ;; *) labels="$labels${labels:+,}\"lands-on-review\"" ;; esac
    fi
    # DEPENDENCIES, WHICH THIS STUB COULD NOT EXPRESS AT ALL UNTIL Proofdelve ForgeOs-czhb.
    # It hardcoded "dependency_count":0, so dispatchable()'s dependency loop was
    # unreachable from here and the branch had NO end-to-end control of any kind
    # -- the same Proofdelve ForgeOs-8zb7 class A shape as the always-succeeding bd create
    # this stub carried until 2026-09-10. Every fixture that predates the fifth
    # field keeps its exact four-field line and its "dependency_count":0.
    #
    # THE KEY IS `dependency_type`, WHICH IS WHAT `bd show` REALLY EMITS.
    # Measured against the live tracker 2026-09-10: `bd show --json` carries the
    # name under `dependency_type` and leaves `type` null, while `bd list --json`
    # does the exact opposite. bead_json() calls `show`, so this stub models
    # `show`. A stub that guessed `type` here would make the guard look correct
    # against a record shape bd never produces on this path.
    deps=""; dn=0
    if [ -n "$dp" ]; then
      for e in ${dp//,/ }; do
        did="${e%%:*}"; rest="${e#*:}"; dst="${rest%%:*}"; dty="${rest#*:}"
        [ "$dty" = "$rest" ] && dty=""
        dit=task; case "$did" in *gate*) dit=gate ;; esac
        deps="$deps${deps:+,}{\"id\":\"$did\",\"status\":\"$dst\",\"issue_type\":\"$dit\""
        [ -n "$dty" ] && deps="$deps,\"dependency_type\":\"$dty\""
        deps="$deps}"
        dn=$((dn+1))
      done
    fi
    # THE DESCRIPTION CARRIES THE Touches LINE (Proofdelve ForgeOs-b9mj) in the shape the
    # Mayor writes it, after a line of prose, so touch_set_of() is parsing a
    # description and not a bare value. Empty sixth field: no such line.
    desc="OBSERVED: fixture."; [ -n "${tc:-}" ] && desc="$desc\\nTouches: $tc"
    # THE DELIVERABLE LINE (Proofdelve ForgeOs-nz3u), likewise after prose, so deliverable_of()
    # is parsing a description and not a bare value. Empty seventh field: no line.
    [ -n "${dl:-}" ] && desc="$desc\\nDeliverable: $dl"
    printf '{"id":"%s","status":"%s","assignee":"%s","labels":[%s],"dependency_count":%d,"dependencies":[%s],"description":"%s"}\n' "$i" "$st" "$as" "$labels" "$dn" "$deps" "$desc" ;;
  update)
    id="${args[1]}"; r="$(rec "$id")"; IFS='|' read -r i st as lb dp tc dl <<< "$r"
    shift_add=""; shift_rm=""
    for ((k=2;k<${#args[@]};k++)); do
      case "${args[k]}" in
        --claim)
          # Proofdelve ForgeOs-dx34.9 KNOBS, BOTH DEFAULTING OFF. E2E_BD_CLAIM=refuse
          # refuses EVERY claim: a tracker under permanent write contention
          # (Proofdelve ForgeOs-dx34.2's unmeasured case), which is a wedge the loop cannot
          # clear. E2E_BD_CLAIM_REFUSE_N=k refuses the first k claims and grants
          # the rest: the transient the stall counter's N exists to absorb. Both
          # exit before anything is written, as a real refused claim does.
          if [ "${E2E_BD_CLAIM:-ok}" = refuse ]; then exit 1; fi
          # NOT `k`: that is the enclosing argument-loop index (the Warden, round one,
          # finding 3). Reusing it worked only because REFUSE_N=2 equalled the
          # index of --claim; at 1 the loop never terminated and at 3 it skipped
          # the assignee -- the instrument changing what it measures at the next
          # value. The comments in this file record that class three times.
          if [ -n "${E2E_BD_CLAIM_REFUSE_N:-}" ]; then
            refused=$(cat "$db.claims-refused" 2>/dev/null || echo 0)
            if [ "$refused" -lt "$E2E_BD_CLAIM_REFUSE_N" ]; then echo $((refused + 1)) > "$db.claims-refused"; exit 1; fi
          fi
          st=in_progress ;;
        -a) as="${args[k+1]}" ;;
        --status) st="${args[k+1]}" ;;
        --assignee) as="${args[k+1]}" ;;
        --add-label) shift_add="${args[k+1]}" ;;
        --remove-label) shift_rm="${args[k+1]}" ;;
      esac
    done
    # A WRITE THAT CAN BE REFUSED, SELECTIVELY (Proofdelve ForgeOs-s2lx; the shape
    # Proofdelve ForgeOs-lv7x asked for). E2E_BD_UPDATE_REFUSE_LABEL=<label> makes every
    # update that would ADD that label exit 1 before anything is written, and
    # leaves every other update alone -- so a scenario can refuse exactly the
    # ESCALATE branch's write (which adds `human`) while the claim, the
    # returns and the rest of the run succeed. Default off.
    if [ -n "${E2E_BD_UPDATE_REFUSE_LABEL:-}" ] && [ "$shift_add" = "$E2E_BD_UPDATE_REFUSE_LABEL" ]; then exit 1; fi
    # THE OTHER SELECTIVE REFUSAL (Proofdelve ForgeOs-lv7x): E2E_BD_UPDATE_REFUSE_RMLABEL=<label>
    # refuses exactly the update that would REMOVE that label, which is the
    # MERGE-PARENT-OPEN write (remove fleet-safe, --status open, unassign) and
    # nothing earlier in the run -- the claim adds nothing and removes nothing.
    if [ -n "${E2E_BD_UPDATE_REFUSE_RMLABEL:-}" ] && [ "$shift_rm" = "$E2E_BD_UPDATE_REFUSE_RMLABEL" ]; then exit 1; fi
    [ -n "$shift_rm" ] && lb="$(printf '%s' ",$lb," | sed "s/,$shift_rm,/,/" | sed 's/^,//;s/,$//')"
    [ -n "$shift_add" ] && lb="${lb:+$lb,}$shift_add"
    put "$i" "$st" "$as" "$lb" "$dp" "${tc:-}" "${dl:-}" ;;
  close)
    id="${args[1]}"; r="$(rec "$id")"; IFS='|' read -r i st as lb dp tc dl <<< "$r"
    put "$i" closed "$as" "$lb" "$dp" "${tc:-}" "${dl:-}" ;;
  create)
    # A REAL ID AND A REAL LINE, because land()'s follow-up path parses this
    # output and an empty answer sends it down the could-not-file branch — so a
    # stub that printed nothing would have made every APPROVE-WITH-FINDINGS and
    # MERGE-PARENT-OPEN scenario measure the FAILURE path while looking like it
    # measured the success one.
    # `$(grep -c ... || echo 0)` IS THE WRONG SPELLING AND IT COST A ROUND HERE:
    # grep -c PRINTS 0 and RETURNS 1 on no match, so the fallback appends a
    # SECOND zero and the arithmetic dies with "0\n0 + 1: syntax error" — the
    # stub then returns 1, land() sees an empty follow-up id, and every
    # APPROVE-WITH-FINDINGS scenario reads as "the follow-up could not be
    # filed". A defect in the instrument presenting as a defect in the subject,
    # for the third time in this file. grep -c always prints exactly one number.
    # AND IT CAN BE TOLD TO FAIL, WHICH IS THE WHOLE OF Proofdelve ForgeOs-8zb7 CLASS A
    # HERE. Until 2026-09-10 this stub ALWAYS succeeded and ALWAYS printed a
    # parseable id, so every scenario in this file exercised the world in which
    # filing a follow-up works and the Proofdelve ForgeOs-bzyk merge-but-do-not-close path
    # had NO CONTROL AT ALL — the harness reported the same score whether that
    # path was correct or fatal. E2E_BD_CREATE=silent prints nothing and exits
    # 0, which is the subtler of the two ways the path is reached: a nonzero
    # exit already lands there through land()'s `|| followup_bead=""`, while an
    # exit-0-with-no-output arrives through the sed matching nothing, and it is
    # that second one a `set -e` change can newly turn fatal.
    # THE DEFAULT IS UNCHANGED, deliberately: every scenario written before
    # this knob existed keeps the fixture it was written against.
    if [ "${E2E_BD_CREATE:-ok}" = silent ]; then exit 0; fi
    n=$(grep -c '^E2E-fu' "$db" 2>/dev/null); n=$((n + 1))
    put "E2E-fu$n" open "" ""
    echo "Created issue: E2E-fu$n (task)" ;;
  # Proofdelve ForgeOs-29j3g: a comment's text is kept, so a scenario can read the ASK line.
  comment) if [ "${args[2]:-}" = --file ] && [ -r "${args[3]:-}" ]; then cat "${args[3]}" >> "$db.comments"; fi ;;
  dep) : ;;
  # LIST, WITH --label (all must match) AND --status (comma list) FILTERS
  # (Proofdelve ForgeOs-6niaz belt 2 asks which Workbench sittings are held). Every
  # scenario before 6niaz never called list.
  list)
    want_l=(); want_s=""
    for ((k=1;k<${#args[@]};k++)); do
      case "${args[k]}" in --label) want_l+=("${args[k+1]}") ;; --status) want_s="${args[k+1]}" ;; esac
    done
    out="["; first=1
    while IFS='|' read -r id st as lb dp tc dl; do
      okl=1; for w in "${want_l[@]}"; do case ",$lb," in *",$w,"*) ;; *) okl=0 ;; esac; done
      [ "$okl" = 1 ] || continue
      if [ -n "$want_s" ]; then case ",$want_s," in *",$st,"*) ;; *) continue ;; esac; fi
      [ $first = 1 ] || out="$out,"; first=0
      jl=""; for l in ${lb//,/ }; do jl="$jl${jl:+,}\"$l\""; done
      out="$out{\"id\":\"$id\",\"status\":\"$st\",\"labels\":[$jl]}"
    done < "$db"
    echo "$out]" ;;
  merge-slot)
    case "${args[1]}" in
      check)   [ -e "$db.slot" ] ;;
      create)  : > "$db.slot" ;;
      acquire) [ -e "$db.slot.held" ] && exit 1; : > "$db.slot.held" ;;
      release) rm -f "$db.slot.held" ;;
    esac ;;
  *) : ;;
esac
B
  chmod +x "$work/bin/bd"
}

# --------------------------------------------------------------------------
# NOT a command substitution, deliberately: an exit code set inside $( ) is set
# in a subshell and never reaches the caller, which is how the first draft of
# this harness read every run as an unbound variable. The output goes to a file
# and the status comes back as the function's own.
run_pass() { # $1 launcher, $2 state, $3 bd store -> rc; output in $2/out.txt
  FLEET_STATE="$2" BD_STORE="$3" "$1" --once > "$2/out.txt" 2>&1
}
run_dry_pass() { # the same, under --dry-run (Proofdelve ForgeOs-geym)
  FLEET_STATE="$2" BD_STORE="$3" "$1" --once --dry-run > "$2/out.txt" 2>&1
}
wait_forge() { # $1 state, $2 sfx
  local i=0; while [ ! -e "$1/workers/$2/exit" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done
}

mkbd
echo "=========================================================================="
echo "SCENARIO 0 — A WRONG BRANCH. The run must REFUSE at preflight, exit 64,"
echo "             and dispatch nothing (Proofdelve ForgeOs-dx34.1 round two)"
echo "=========================================================================="
# THE HALF THAT DID NOT MOVE, AND THE REASON THIS IS END TO END RATHER THAN A
# UNIT CASE. Scenario 1 below proves a dirty root STARTS; this proves a wrong
# branch does NOT, and the two together are the whole of landability after round
# two. What regressed was the CALL SITE and not the function — landable_why()
# went on computing the branch condition perfectly while nothing refused on it,
# so an instrument that only exercises the function cannot see it. Every bead of
# a wrong-branch run would be cut from that base (forge.sh cuts with `worktree
# add -b bead/<sfx>` and no ref), reviewed against a range carrying foreign
# commits, and landed under its own name.
r=$(mkfort s0 ok); mk_launcher "$launcher" "$work/s0-fleet.sh" "$r" || exit 3
st="$work/s0-state"; mkdir -p "$st"; db="$work/s0.bd"
printf 'E2E-ggg|open||fleet-safe\n' > "$db"
git -C "$r" checkout -qb feature/x

run_pass "$work/s0-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if [ "$rc" -eq 64 ] && grep -q 'feature/x' <<<"$out" \
   && ! grep -q 'dispatched E2E-ggg' <<<"$out"; then
  ok "a non-main branch REFUSES at preflight (64), names the branch, and dispatches nothing"
else no "wrong branch did not refuse end to end" "rc=$rc
$out"; fi
if [ "$(grep -c '^E2E-ggg|open||fleet-safe' "$db")" -eq 1 ] && [ ! -d "$r-worktrees" ]; then
  ok "the refused run claimed no bead and cut no worktree from the wrong base"
else no "the refused run still touched the tracker or the tree" "$(cat "$db")"; fi
# VACUITY, ON ITS OWN FIXTURE. Without a control, both assertions above are
# equally satisfied by a launcher that refuses everything — the shape this fort
# keeps paying for. It gets a SEPARATE fort and tracker deliberately: reusing the
# one above couples the control to the case it is controlling, and against a
# launcher that does NOT refuse, that run has already claimed and dispatched the
# bead, so the control fails for a reason that has nothing to do with what it
# measures. A case whose meaning depends on another case's outcome is not a
# control. Identical fixture, on main; only the branch differs.
r2=$(mkfort s0b ok); mk_launcher "$launcher" "$work/s0b-fleet.sh" "$r2" || exit 3
st2="$work/s0b-state"; mkdir -p "$st2"; db2="$work/s0b.bd"
printf 'E2E-fff|open||fleet-safe\n' > "$db2"
run_pass "$work/s0b-fleet.sh" "$st2" "$db2"; rc=$?; out=$(cat "$st2/out.txt")
if [ "$rc" -ne 64 ] && grep -q 'dispatched E2E-fff' <<<"$out"; then
  ok "VACUITY: the identical fixture on main starts and dispatches, so the refusal was about the branch"
else no "the on-main control did not start" "rc=$rc
$out"; fi
wait_forge "$st2" fff

# SCENARIO 0d — Proofdelve ForgeOs-geym, AT RUN LEVEL. The unit half is in
# scripts/landable-harness.sh (cases 2d, 3d, 3bd); this is the sentence a person
# would actually say out loud: on a wrong branch, `fleet.sh --dry-run` starts,
# says a real run would refuse, and STILL CLAIMS NOTHING AND CUTS NOTHING. The
# second half is what makes the exemption safe rather than merely convenient, and
# it is not derivable from the guard alone — it is a property of every path below
# the guard, which is why it is measured by running the whole thing.
r3=$(mkfort s0d ok); mk_launcher "$launcher" "$work/s0d-fleet.sh" "$r3" || exit 3
st3="$work/s0d-state"; mkdir -p "$st3"; db3="$work/s0d.bd"
printf 'E2E-jjj|open||fleet-safe\n' > "$db3"
git -C "$r3" checkout -qb feature/y
run_dry_pass "$work/s0d-fleet.sh" "$st3" "$db3"; rc=$?; out=$(cat "$st3/out.txt")
if [ "$rc" -ne 64 ] && grep -q 'feature/y' <<<"$out" \
   && grep -q 'REAL RUN WOULD REFUSE' <<<"$out"; then
  ok "geym: --dry-run on a wrong branch STARTS, names the branch, and says a real run would refuse"
else no "the dry run refused on the branch it was built to let you test" "rc=$rc
$out"; fi
# THIS SECOND ASSERTION IS NOT THE DISCRIMINATOR AND MUST NOT BE READ AS ONE: it
# passes against the pre-geym launcher too, because a REFUSED run also claims
# nothing. It is the SAFETY half — the thing that goes red if the exemption ever
# lets a dry run act — and it is stated here so a later reader does not count it
# as evidence that the exemption works. The case above it is the discriminator,
# and against the pre-geym file it fails with rc=64.
if [ "$(grep -c '^E2E-jjj|open||fleet-safe' "$db3")" -eq 1 ] && [ ! -d "$r3-worktrees" ]; then
  ok "geym: and it still claimed nothing and cut no worktree from the wrong base — the exemption costs nothing"
else no "the dry run mutated the tracker or the tree" "$(cat "$db3")"; fi

echo
echo "=========================================================================="
echo "SCENARIO 1 — A DIRTY ROOT. The run must START, dispatch, and PARK the merge"
echo "=========================================================================="
r=$(mkfort s1 ok); mk_launcher "$launcher" "$work/s1-fleet.sh" "$r" || exit 3
st="$work/s1-state"; mkdir -p "$st"; db="$work/s1.bd"
printf 'E2E-aaa|open||fleet-safe\n' > "$db"
echo two >> "$r/subject.txt"          # UNCOMMITTED TRACKED SOURCE at the root

run_pass "$work/s1-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if [ "$rc" -ne 64 ] && grep -q 'NOT LANDABLE RIGHT NOW' <<<"$out" \
   && grep -q 'dispatched E2E-aaa' <<<"$out"; then
  ok "a dirty root does NOT refuse: the run started, said why, and dispatched"
else no "dirty root did not start or did not dispatch" "rc=$rc
$out"; fi

wait_forge "$st" aaa
run_pass "$work/s1-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if grep -q 'verifier GREEN' <<<"$out" && grep -q 'NOT MERGED this pass' <<<"$out"; then
  ok "the bead was built, verified and reviewed on a dirty root, and the merge was PARKED"
else no "second pass did not verify/review/park" "rc=$rc
$out"; fi
if grep -qE '[0-9]+ merge\(s\) PARKED, waiting on a landable tree' <<<"$out"; then
  ok "the run says how many merges are parked and why, without anyone reasoning it out"
else no "the parked count is not in the narrative" "$out"; fi
if [ "$(grep -c '^E2E-aaa|closed' "$db")" -eq 0 ] \
   && ! git -C "$r" merge-base --is-ancestor bead/aaa HEAD 2>/dev/null; then
  ok "nothing was merged and nothing was closed while the tree was dirty"
else no "something landed on a dirty tree" "$(cat "$db")"; fi
# THE REAPING CONSTRAINT, MEASURED AT THE MOMENT IT MATTERS (2026-09-09 docket
# item 1, acceptance 3). Proofdelve ForgeOs-usz6's retry READS FROM THIS WORKTREE — it
# re-attempts the merge alone, without re-running the verifier and without
# spending a second review launch. A reap between the deferral and the retry
# turns a recoverable park into a lost bead, which is the exact failure w7u5 and
# usz6 were filed to end. This is asserted HERE, mid-flight, rather than
# afterwards: after the retry has landed there is no way to tell a tree that
# survived the deferral from one that was removed and never needed.
if [ -d "$r-worktrees/aaa" ]; then
  ok "the DEFERRED merge KEEPS its worktree, which is what the retry reads from"
else no "the deferred merge's worktree was reaped early" "$r-worktrees/aaa is gone; the usz6 retry has nothing to merge from"; fi

# now clean the tree, exactly as an operator would
git -C "$r" checkout -- subject.txt
run_pass "$work/s1-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if grep -q 'RETRYING THE DEFERRED MERGE ALONE' <<<"$out" \
   && grep -q 'merged to main' <<<"$out"; then
  ok "the parked merge landed on the next pass once the tree was clean"
else no "the parked merge did not land" "rc=$rc
$out"; fi
# THE RETRY SPENDS NEITHER A VERIFIER RUN NOR A REVIEW LAUNCH (Proofdelve ForgeOs-usz6).
if ! grep -q 'running the host verifier' <<<"$out" \
   && ! grep -q 'review starting on' <<<"$out"; then
  ok "the retry re-ran neither the pre-review verifier nor a review launch"
else no "the retry spent a launch or a verifier run" "$out"; fi
if grep -q 'post-merge verifier GREEN' <<<"$out" \
   && grep -q 'REMOVED' <<<"$out" \
   && [ "$(grep -c '^E2E-aaa|closed' "$db")" -eq 1 ]; then
  ok "the post-merge verification was GREEN, its worktree was REMOVED, and the bead closed"
else no "post-merge/close" "rc=$rc
$out"; fi
# AND NOW THE BEAD'S OWN WORKTREE IS REAPED (acceptance 1). Same tree the case
# above required to SURVIVE the deferral, one pass later, after the merge AND
# the close have both succeeded. The pair is the whole property: one fixture,
# two moments, opposite requirements.
#
# WHAT IS ASSERTED IS STATE AND THE DURABLE RECORD, NEVER A SENTENCE. The
# directory is gone, `git worktree list` no longer carries an administrative
# entry for it (an `rm -rf` would satisfy the first test and not the second),
# and the bead.closed payload says `reaped`. The narration is deliberately not
# pinned: a control that pins a spelling goes red for the next correct rewording
# and teaches its fort to ignore it (Proofdelve ForgeOs-8zb7 class B, three cases moved for
# it on 2026-09-08). The payload token is not wording — it is the interface a
# morning reader and every later query read, and scenario 9 holds it fixed while
# rewording everything around it.
if [ ! -e "$r-worktrees/aaa" ] \
   && ! git -C "$r" worktree list | grep -q -- '-worktrees/aaa' \
   && grep -q '"worktree":"reaped"' "$r/emitted"; then
  ok "REAPED: a bead that merged AND closed leaves no worktree, no stale git entry, and the record says so"
else no "the landed bead's worktree was not reaped" "dir=$( [ -e "$r-worktrees/aaa" ] && echo present || echo gone) gitlist=$(git -C "$r" worktree list | grep -c -- '-worktrees/aaa') payload=$(grep -o '"worktree":"[a-z]*"' "$r/emitted" | tail -1)"; fi
# CONTROL 1, END TO END. The stub verifier dirtied $root with verifier-failing
# content FROM INSIDE the post-merge window. The run must have neither halted
# nor blamed the merged work.
# THE INJECTION MUST BE SHOWN TO HAVE FIRED. Without that half, "the run did
# not halt" is satisfied just as well by an injection that never happened, and
# the case would pass while measuring nothing (Proofdelve ForgeOs-8zb7 class A).
#
# AND THE HALT TEST NAMES THE ANNOUNCEMENT, NOT THE WORD. An earlier draft
# grepped the output for HALT and matched the run's own opening line, which
# tells the operator that touching $FLEET_STATE/HALT stops it — a control
# failing on the boilerplate that explains the thing it is checking for.
if [ ! -e "$st/HALT" ] && grep -q POISON "$r/subject.txt" \
   && ! grep -q 'HALT: ' <<<"$out" \
   && grep -q 'post-merge verifier GREEN' <<<"$out"; then
  ok "CONTROL 1: \$root was dirtied DURING the post-merge window with failing content (it is poisoned now); the verification was GREEN, the run did not halt, and the merged work was not blamed"
else no "CONTROL 1" "halt_file=$( [ -e "$st/HALT" ] && echo yes || echo no) root_poisoned=$(grep -c POISON "$r/subject.txt")
$out"; fi
# and it really did run somewhere else
if grep -q -- '-worktrees/postmerge-' "$r/verify-calls" \
   && [ "$(grep -c "^$r\$" "$r/verify-calls")" -eq 0 ]; then
  ok "no verifier run in this scenario ever executed in \$root itself"
else no "a verifier ran in the root" "$(cat "$r/verify-calls")"; fi

echo
echo "=========================================================================="
echo "SCENARIO 2 — CONTROL 2. A genuine regression in the MERGED work still halts"
echo "=========================================================================="
r=$(mkfort s2 POISON); mk_launcher "$launcher" "$work/s2-fleet.sh" "$r" || exit 3
st="$work/s2-state"; mkdir -p "$st"; db="$work/s2.bd"
printf 'E2E-bbb|open||fleet-safe\n' > "$db"
# The pre-review verifier would catch POISON in the bead's own worktree and
# never reach a merge, so the regression is made to appear only at the MERGE:
# the bead's branch is clean, and its merge into main is what turns main red.
cat > "$r/fort/scripts/verify.sh" <<V
#!/bin/bash
printf '%s\n' "\$PWD" >> "$r/verify-calls"
case "\$PWD" in *-worktrees/postmerge-*) echo "VERIFIER RED in \$PWD"; exit 1 ;; esac
echo "VERIFIER GREEN in \$PWD"; exit 0
V
chmod +x "$r/fort/scripts/verify.sh"
git -C "$r" add -A >/dev/null; git -C "$r" commit -qm "regression only visible after the merge"
run_pass "$work/s2-fleet.sh" "$st" "$db" || true
wait_forge "$st" bbb
run_pass "$work/s2-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
kept=$(printf '%s' "$out" | sed -n 's/.*KEPT at \([^ ]*\).*/\1/p' | head -1)
if [ "$rc" -eq 70 ] && [ -e "$st/HALT" ] \
   && grep -q 'post-merge verifier is RED' <<<"$out"; then
  ok "CONTROL 2: a regression in the MERGED work turns the post-merge verifier RED and HALTS"
else no "CONTROL 2: the post-merge gate went blind" "rc=$rc halt=$( [ -e "$st/HALT" ] && echo yes || echo no)
$out"; fi
if [ -n "$kept" ] && [ -d "$kept" ]; then
  ok "the red post-merge worktree is KEPT and named ($kept), so the evidence survives"
else no "the red worktree was not kept" "[$kept]"; fi
if [ "$(grep -c '^E2E-bbb|closed' "$db")" -eq 0 ] && git -C "$r" merge-base --is-ancestor bead/bbb HEAD 2>/dev/null; then
  ok "the merge STANDS and the bead is NOT closed, which is what the halt is for"
else no "merge/close state after a red main" "$(cat "$db")"; fi
# THE OTHER DIRECTION OF THE REAPING CONSTRAINT, AND IT IS HALF OF ACCEPTANCE 4:
# "a survivor after a state needing a person must still be KEPT". This run
# MERGED and then halted on a red post-merge verifier, so the worker is
# needs-person and there was no close. A reap keyed on the worker being finished
# — or on `settled`, which this file writes at eight sites — would destroy the
# implementation the person is being called to look at. Without this case, a
# launcher that removes every worktree it can reach passes every other reap
# assertion in this harness.
if [ -d "$r-worktrees/bbb" ]; then
  ok "KEPT: a worker in a state needing a person still has its worktree — that tree is the evidence"
else no "a needs-person worker's worktree was reaped" "$r-worktrees/bbb is gone, so the person has nothing to read"; fi

echo
echo "=========================================================================="
echo "SCENARIO 3 — THE INVERSION. The pre-narrowing launcher must refuse at 64"
echo "=========================================================================="
if [ -z "$pre_narrowing" ]; then
  skip "the pre-narrowing launcher refuses a dirty root at 64" \
       "FLEET_SH_PRE_NARROWING was not set, so nothing was measured. This is NOT a pass."
else
  r=$(mkfort s3 ok); mk_launcher "$pre_narrowing" "$work/s3-fleet.sh" "$r" || exit 3
  st="$work/s3-state"; mkdir -p "$st"; db="$work/s3.bd"
  printf 'E2E-ccc|open||fleet-safe\n' > "$db"
  echo two >> "$r/subject.txt"
  run_pass "$work/s3-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
  if [ "$rc" -eq 64 ] && grep -q 'REFUSED' <<<"$out" \
     && ! grep -q 'dispatched' <<<"$out"; then
    ok "INVERSION: the pre-narrowing launcher exits 64 on the same fixture and dispatches nothing"
  else no "the 'before' file did not refuse" "rc=$rc
$out"; fi
fi

# ==========================================================================
# Proofdelve ForgeOs-ke5u — THE TWO SIGNAL POSTURES, RUN FOR REAL AGAINST THE REAL
# DISPATCHER. A signalled review that COMPLETED must have its verdict honoured;
# one that was genuinely KILLED must still take the safe path; and a result file
# that exists and will not parse must be distinguishable from one that is
# absent. Three outcomes, three scenarios, plus the RED reproduction.
# ==========================================================================

# Set a scenario up to the point where the next pass is a REVIEW: dispatch, let
# the stub Forge finish, and leave the worker `finished`.
upto_review() { # $1 name, $2 sfx, $3 launcher-src -> prints "root|state|db"
  local r st db
  r=$(mkfort "$1" ok); mk_launcher "$3" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  E2E_WARDEN_SLEEP=0 run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  wait_forge "$st" "$2"
  printf '%s|%s|%s' "$r" "$st" "$db"
}
# Start a pass in the background, wait until the stub Warden says it has begun,
# then deliver the signal. $! is this shell's own child here (no setsid), so it
# is the dispatcher's pid and not a wrapper's.
signal_during_review() { # $1 name, $2 sig, $3 state, $4 db, $5 warden-result
  local mark="$3/warden-started"; rm -f "$mark"
  E2E_WARDEN_MARK="$mark" E2E_WARDEN_SLEEP=3 E2E_WARDEN_RESULT="$5" \
    FLEET_STATE="$3" BD_STORE="$4" "$work/$1-fleet.sh" --once > "$3/out.txt" 2>&1 &
  local pid=$! i=0
  while [ ! -e "$mark" ] && [ $i -lt 200 ]; do sleep 0.05; i=$((i+1)); done
  [ -e "$mark" ] || { echo "HARNESS REFUSES: the stub Warden never started in $1" >&2; exit 3; }
  kill -"$2" "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
}
wstate() { head -1 "$1/state" 2>/dev/null | cut -d'|' -f1; }

echo
echo "=========================================================================="
echo "SCENARIO 4 — ke5u, THE SHARP ONE. kill -TERM while a review is running:"
echo "             the review COMPLETES, and its verdict must be honoured"
echo "=========================================================================="
IFS='|' read -r r st db <<< "$(upto_review s4 ddd "$launcher")"
signal_during_review s4 TERM "$st" "$db" approve
out=$(cat "$st/out.txt")
if grep -q 'COMPLETED FIRST and recorded APPROVE' <<<"$out" \
   && ! grep -q 'No verdict is recorded' <<<"$out"; then
  ok "ke5u: a review that finished under TERM is reported as recorded, not as 'no verdict'"
else no "ke5u: the false line is still printed or the verdict was not seen" "$out"; fi
if [ "$(wstate "$st/workers/ddd")" = deferred-merge ] \
   && [ "$(cat "$st/workers/ddd/verdict" 2>/dev/null)" = APPROVE ]; then
  ok "ke5u: the verdict is PERSISTED and the worker resumes at the merge, not at a person"
else no "ke5u: the verdict was discarded" "state=$(wstate "$st/workers/ddd") verdict=$(cat "$st/workers/ddd/verdict" 2>/dev/null)"; fi
if [ "$(wstate "$st/workers/ddd")" != in-hand ]; then
  ok "ke5u: the worker is NOT left in-hand, so the next run does not read it as ORPHANED"
else no "ke5u: worker left in-hand" "the two false lines are still reachable"; fi
# And the run still stopped honestly: nothing merged, nothing closed.
if ! git -C "$r" merge-base --is-ancestor bead/ddd HEAD 2>/dev/null \
   && [ "$(grep -c '|closed|' "$db")" -eq 0 ]; then
  ok "ke5u: honouring the verdict did not make a stopping run merge or close anything"
else no "a stopping run landed work" "$(cat "$db")"; fi

echo
echo "=========================================================================="
echo "SCENARIO 5 — ke5u, THE OTHER POSTURE. Ctrl-C through a REAL pty, which"
echo "             kills the review outright: the safe path must still be taken"
echo "=========================================================================="
# A REAL PTY IS THE ONLY HONEST WAY TO TEST THIS (ke5u acceptance 5). `kill -INT`
# on a background job does nothing at all — bash sets SIGINT to ignore for
# asynchronous commands and a signal ignored on entry cannot be trapped
# (measured 2026-09-08, three controls). Writing \x03 to the master side of a pty
# is what makes the line discipline signal the foreground process group, which
# is the thing Ctrl-C actually does and the reason warden.sh dies with it.
IFS='|' read -r r st db <<< "$(upto_review s5 eee "$launcher")"
mark="$st/warden-started"; rm -f "$mark"
E2E_WARDEN_MARK="$mark" E2E_WARDEN_SLEEP=5 FLEET_STATE="$st" BD_STORE="$db" \
python3 - "$work/s5-fleet.sh" "$mark" "$st/out.txt" <<'PYPTY'
import os, pty, sys, time, select
launcher, mark, outp = sys.argv[1], sys.argv[2], sys.argv[3]
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["/bin/bash", launcher, "--once"])
buf = b""; sent = False; t0 = time.time()
while True:
    if not sent and os.path.exists(mark):
        os.write(fd, b"\x03"); sent = True
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try:
            d = os.read(fd, 4096)
        except OSError:
            break
        if not d: break
        buf += d
    if time.time() - t0 > 60: break
    if os.waitpid(pid, os.WNOHANG)[0]: 
        try:
            while True:
                d = os.read(fd, 4096)
                if not d: break
                buf += d
        except OSError:
            pass
        break
open(outp, "wb").write(buf)
sys.stderr.write("pty sent-ctrl-c=%s\n" % sent)
PYPTY
out=$(cat "$st/out.txt")
if grep -q 'STOPPED by SIG' <<<"$out" && grep -q 'recorded nothing' <<<"$out"; then
  ok "ke5u: a review genuinely killed by Ctrl-C is reported as having recorded nothing"
else no "ke5u: the killed case is misreported" "$out"; fi
if [ "$(wstate "$st/workers/eee")" = parked-review ]; then
  ok "ke5u: the killed review parks at REVIEW, so the next run resumes there and does not re-verify"
else no "ke5u: killed review left the wrong state" "state=$(wstate "$st/workers/eee")"; fi
if [ ! -s "/tmp/warden-eee.log.result.json" ] && [ ! -s "$e2e_res_root/eee.log.result.json" ]; then
  ok "VACUITY: the stub Warden really was killed — no result file exists, so the case above measured the killed path"
else no "the Ctrl-C did not reach the review" "a result file exists, so scenario 5 measured the completed path"; fi

echo
echo "=========================================================================="
echo "SCENARIO 6 — ke5u REFUSE. A result file that exists and will not parse is"
echo "             neither a killed review nor an approval"
echo "=========================================================================="
IFS='|' read -r r st db <<< "$(upto_review s6 fff "$launcher")"
signal_during_review s6 TERM "$st" "$db" garbage
out=$(cat "$st/out.txt")
if grep -q 'EXISTS but records no usable verdict' <<<"$out"; then
  ok "ke5u: an unparseable result file is named and distinguished from an absent one"
else no "ke5u: REFUSE outcome collapsed into another" "$out"; fi
if [ "$(wstate "$st/workers/fff")" = parked-review ] \
   && ! git -C "$r" merge-base --is-ancestor bead/fff HEAD 2>/dev/null; then
  ok "ke5u: the unparseable case keeps the claim, parks at review, and merges nothing"
else no "ke5u: unparseable case acted" "state=$(wstate "$st/workers/fff")"; fi

echo
echo "=========================================================================="
echo "SCENARIO 7 — ke5u RED. The pre-fix launcher must DISCARD the real verdict"
echo "=========================================================================="
if [ -z "$pre_ke5u" ]; then
  skip "the pre-fix launcher discards a verdict recorded under TERM" \
       "FLEET_SH_PRE_KE5U was not set, so the defect was not reproduced. This is NOT a pass."
else
  IFS='|' read -r r st db <<< "$(upto_review s7 ggg "$pre_ke5u")"
  signal_during_review s7 TERM "$st" "$db" approve
  out=$(cat "$st/out.txt")
  if grep -q 'No verdict is recorded' <<<"$out" \
     && [ "$(wstate "$st/workers/ggg")" != deferred-merge ] \
     && [ -s /tmp/warden-ggg.log.result.json ]; then
    ok "RED REPRODUCED: the pre-fix launcher printed 'No verdict is recorded' while the result file held one, and left the worker $(wstate "$st/workers/ggg")"
  else no "the defect did not reproduce against the 'before' file" "state=$(wstate "$st/workers/ggg")
$out"; fi
fi

# ==========================================================================
# THE REAPING BRANCH — INVERSION AND CORRECT-VARIANT CONTROL
# ==========================================================================
# Scenario 1 shows the tree survives a deferral and is gone after the close, and
# scenario 2 shows it survives a state needing a person. Those establish that
# the branch discriminates. They do NOT establish that it discriminates for the
# reason claimed, and two further controls are what close that:
#
#   8  INVERSION. The launcher as it stood BEFORE the branch, run to a complete
#      merge-and-close on the same fixture, must LEAVE the worktree. Without it,
#      "no worktree afterwards" is equally satisfied by a fixture in which one
#      was never created.
#   9  CORRECT VARIANT (Proofdelve ForgeOs-8zb7 step 2), GENERATED HERE RATHER THAN
#      DESCRIBED (Proofdelve ForgeOs-dx34.1 round two). Every sentence and every internal
#      symbol name is changed and nothing about the behaviour is; the assertions
#      must all still pass. The line between them is stated at the generator.

# Run a bead all the way to merged-and-closed on a clean tree: dispatch, let the
# stub Forge finish, then one pass that verifies, reviews, merges, verifies
# again and closes.
run_to_close() { # $1 name, $2 sfx, $3 launcher-src -> prints "root|state|db"
  local r st db
  r=$(mkfort "$1" ok); mk_launcher "$3" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  wait_forge "$st" "$2"
  run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  printf '%s|%s|%s' "$r" "$st" "$db"
}

echo
echo "=========================================================================="
echo "SCENARIO 8 — THE INVERSION. The pre-reap launcher must LEAVE the worktree"
echo "=========================================================================="
if [ -z "$pre_reap" ]; then
  skip "the pre-reap launcher leaves the bead worktree behind after a close" \
       "FLEET_SH_PRE_REAP was not set, so the defect was not reproduced. This is NOT a pass."
else
  IFS='|' read -r r st db <<< "$(run_to_close s8 hhh "$pre_reap")"
  if [ "$(grep -c '^E2E-hhh|closed' "$db")" -eq 1 ] && [ -d "$r-worktrees/hhh" ]; then
    ok "INVERSION: the pre-reap launcher merged AND closed the bead and left $r-worktrees/hhh standing — the defect reproduces"
  else no "the 'before' file did not reproduce the leak" "closed=$(grep -c '^E2E-hhh|closed' "$db") worktree=$( [ -d "$r-worktrees/hhh" ] && echo present || echo gone)
$(cat "$st/out.txt")"; fi
fi

echo
echo "=========================================================================="
echo "SCENARIO 9 — THE CORRECT VARIANT. Reworded, renamed, same behaviour: GREEN"
echo "=========================================================================="
# WHAT IS WORDING AND WHAT IS INTERFACE, STATED SO THE NEXT PERSON DOES NOT HAVE
# TO GUESS. WORDING: every say()/warn() sentence the branch prints, and the names
# of its own function and its own result variable — all internal, all free to
# change. INTERFACE: the four outcome tokens (reaped/absent/failed/refused) and
# the `worktree` key in the bead.closed payload, because those are what the
# durable record carries and what a later query reads. The variant changes all of
# the first and none of the second, which is exactly the line Proofdelve ForgeOs-8zb7 step 2
# asks a control to respect.
variant="$work/variant-fleet.sh"
python3 - "$launcher" "$variant" <<'PYV' || { skip "the reap assertions survive a correct rewording" "the variant could not be generated: this launcher has no reaping branch to reword"; variant=""; }
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src).read()
subs = [
    ("worker_reap_worktree", "lifecycle_drop_worktree"),
    ("reap_result",          "drop_outcome"),
    ("was REMOVED.",         "has been deleted."),
    ("REFUSED to remove",    "declined to remove"),
    ("IS STILL THERE",       "remains on disk"),
    ("no worktree at",       "there is no worktree at"),
]
for old, new in subs:
    if t.count(old) == 0:
        sys.exit("the variant generator found no occurrence of %r; the branch has been renamed or is absent" % old)
    t = t.replace(old, new)
open(dst, "w").write(t)
PYV
if [ -z "$variant" ]; then
  :
elif ! bash -n "$variant" 2>/dev/null; then
  no "the generated correct variant parses" "the rewrite produced a file bash cannot parse"
else
  chmod +x "$variant"
  IFS='|' read -r r st db <<< "$(run_to_close s9 iii "$variant")"
  if [ "$(grep -c '^E2E-iii|closed' "$db")" -eq 1 ] \
     && [ ! -e "$r-worktrees/iii" ] \
     && ! git -C "$r" worktree list | grep -q -- '-worktrees/iii' \
     && grep -q '"worktree":"reaped"' "$r/emitted"; then
    ok "CORRECT VARIANT: every sentence and both internal symbols renamed, behaviour unchanged, and these assertions are still green"
  else no "the reap assertions are over-fitted to this spelling" "closed=$(grep -c '^E2E-iii|closed' "$db") worktree=$( [ -e "$r-worktrees/iii" ] && echo present || echo gone) payload=$(grep -o '"worktree":"[a-z]*"' "$r/emitted" | tail -1)
$(cat "$st/out.txt")"; fi
fi

# ==========================================================================
# Proofdelve ForgeOs-j3kp — THE VERDICT VOCABULARY. Five scenarios, because the bead's
# acceptance 4 asks for three outcomes and its acceptance 2 asks for a fourth
# thing that is easy to skip: THE TWO EXISTING TOKENS MUST NOT CHANGE MEANING.
# A vocabulary change that retroactively reinterprets the record is worse than
# the gap it closes, and the follow-up filing was refactored into one function
# serving both tokens, so "unchanged" is a claim that has to be measured rather
# than asserted.
# ==========================================================================

# Run a bead to its verdict under a chosen token. Same two passes as
# run_to_close, with the stub Warden told what to say.
run_with_token() { # $1 name, $2 sfx, $3 launcher-src, $4 token, [$5 bd-create mode]
  local r st db cr="${5:-ok}"     # -> "root|state|db"
  r=$(mkfort "$1" ok); mk_launcher "$3" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  E2E_WARDEN_TOKEN="$4" E2E_BD_CREATE="$cr" run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  wait_forge "$st" "$2"
  E2E_WARDEN_TOKEN="$4" E2E_BD_CREATE="$cr" run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  printf '%s|%s|%s' "$r" "$st" "$db"
}
merged_in() { git -C "$1" merge-base --is-ancestor "bead/$2" HEAD 2>/dev/null; }

# IS THIS LOGGED `dep add` A BLOCKING EDGE? Asked in BOTH directions below --
# scenario 10 requires yes for APPROVE-WITH-FINDINGS, scenario 11 requires no for
# MERGE-PARENT-OPEN -- so the assertion is shown to DISCRIMINATE rather than
# merely to pass (docket item 3, as corrected by C3). It replaces a NEGATIVE
# list, which is a spelling pinned in disguise: it enumerated three of bd's ten
# types as forbidden, so `--type parent-child` would have satisfied it silently.
# There are exactly two spellings that produce a blocking edge -- no --type flag
# at all, which takes bd's `blocks` default, or --type blocks -- and both flag
# syntaxes are tolerated because making the older call explicit as `--type=blocks`
# would be a CORRECT change that a stricter assertion would redden for.
dep_edge_is_blocking() { # $1 the logged `dep add ...` line
  [ -n "$1" ] || return 1
  printf '%s\n' "$1" | grep -q -- '--type' || return 0   # no flag: bd defaults to blocks
  printf '%s\n' "$1" | grep -qE -- '--type[ =]blocks([[:space:]]|$)'
}

echo
echo "=========================================================================="
echo "SCENARIO 10 — ACCEPTANCE 2. APPROVE-WITH-FINDINGS still means what it meant"
echo "=========================================================================="
# The follow-up filing moved into file_followup(), shared with the new token.
# This is the case that says the move cost nothing: AWF merges, files ONE
# follow-up carrying the verdict, CLOSES the parent, and the worktree is reaped.
IFS='|' read -r r st db <<< "$(run_with_token s10 kkk "$launcher" APPROVE-WITH-FINDINGS)"
out=$(cat "$st/out.txt")
if merged_in "$r" kkk && [ "$(grep -c '^E2E-kkk|closed' "$db")" -eq 1 ] \
   && [ "$(grep -c '^E2E-fu1|' "$db")" -eq 1 ] \
   && grep -q 'follow-up filed as E2E-fu1' <<<"$out"; then
  ok "j3kp acceptance 2: APPROVE-WITH-FINDINGS still merges, files one follow-up, and CLOSES the parent"
else no "APPROVE-WITH-FINDINGS changed meaning" "closed=$(grep -c '^E2E-kkk|closed' "$db") followup=$(grep -c '^E2E-fu1|' "$db")
$out"; fi
if [ ! -e "$r-worktrees/kkk" ]; then
  ok "j3kp acceptance 2: and its worktree is still reaped, because it closed"
else no "the AWF path stopped reaping" "$r-worktrees/kkk survives"; fi
# THE OLDER TOKEN'S DEPENDENCY SPELLING IS UNCHANGED (finding 5). Asserted as a
# CALL, read out of the stub bd's log, and never as an outcome: whether an edge
# type leaves a bead in `bd ready` is a claim about bd, not about fleet.sh, and
# a harness that measured it would go red when bd changed and blame this file.
# That claim is measured by hand, once, and lives in
# fort/memory/facts/bd-dependency-types-and-what-actually-blocks.md.
# ASSERTED AS A PROPERTY, NOT AS A SPELLING, AND NOW POSITIVELY (docket item 3,
# as corrected by C3). What must hold is that this token's edge is still THE
# BLOCKING ONE. The predicate is shared with scenario 11, which requires the
# opposite answer, so it is shown to discriminate.
s10dep="$(grep '^dep add E2E-fu1 E2E-kkk' "$db.calls" 2>/dev/null | head -1)"
if dep_edge_is_blocking "$s10dep"; then
  ok "finding 5: APPROVE-WITH-FINDINGS still files its follow-up edge as a blocking one, unchanged"
else no "the older token's dependency type changed with the new one" "logged: ${s10dep:-<no dep add was logged at all>}"; fi

echo
echo "=========================================================================="
echo "SCENARIO 11 — THE NEW TOKEN. Merge the diff, file the follow-up, LEAVE THE"
echo "              PARENT OPEN"
echo "=========================================================================="
IFS='|' read -r r st db <<< "$(run_with_token s11 lll "$launcher" MERGE-PARENT-OPEN)"
out=$(cat "$st/out.txt")
if merged_in "$r" lll && [ "$(grep -c '^E2E-lll|closed' "$db")" -eq 0 ]; then
  ok "j3kp: the diff MERGED and the parent was NOT closed"
else no "the new token did not merge, or closed the parent anyway" "merged=$(merged_in "$r" lll && echo yes || echo no) db=$(grep '^E2E-lll' "$db")
$out"; fi
# ACCEPTANCE 3, AND IT IS THREE SEPARATE FACTS ABOUT THE PARENT, NOT ONE. Open,
# not claimed, and not re-eligible: a bead left open still carrying `fleet-safe`
# would be picked up on the next pass, which is Proofdelve ForgeOs-p0a6's consent boundary
# in reverse.
# (Proofdelve ForgeOs-e2rbu, 2026-10-06: the parent now carries mayor-lane, its next owner;
# this assertion read `open||` -- no label at all -- which pinned that defect.)
if [ "$(grep -c '^E2E-lll|open||mayor-lane$' "$db")" -eq 1 ]; then
  ok "j3kp acceptance 3: the parent is OPEN, UNASSIGNED, no longer fleet-safe, and routed to mayor-lane"
else no "the parent's state is ambiguous after the new verdict" "$(grep '^E2E-lll' "$db")"; fi
if [ "$(grep -c '^E2E-fu1|' "$db")" -eq 1 ] && grep -q 'follow-up filed as E2E-fu1' <<<"$out"; then
  ok "j3kp: the follow-up was filed and carries the verdict"
else no "no follow-up was filed for the new token" "$(cat "$db")"; fi
# THE OTHER DIRECTION OF SCENARIO 10's PREDICATE (docket item 3 / C3). The same
# function that must say YES of the older token must say NO of this one, or it
# is not discriminating -- it is only agreeing.
s11dep="$(grep '^dep add E2E-fu1 E2E-lll' "$db.calls" 2>/dev/null | head -1)"
if [ -n "$s11dep" ] && ! dep_edge_is_blocking "$s11dep"; then
  ok "item 3: and the SAME predicate says this token's edge is NOT blocking, so it discriminates"
else no "the blocking-edge predicate cannot tell the two tokens apart" "logged: ${s11dep:-<no dep add was logged at all>}"; fi
# THE WORKTREE IS KEPT, AND THIS IS WHERE ITEM 1 AND ITEM 3 MEET. There was no
# close, so the reap never runs — and it must not: a person may put fleet-safe
# back and the bead is dispatched again, which REUSES this worktree
# (forge.sh:41-43). Reaping here would make that dispatch die at
# `git worktree add -b` on a branch that already exists.
if [ -d "$r-worktrees/lll" ]; then
  ok "j3kp: the worktree is KEPT, so a person who re-dispatches this bead has one"
else no "the new token reaped a worktree a re-dispatch needs" "$r-worktrees/lll is gone"; fi
# NOT RE-ELIGIBLE, MEASURED BY RUNNING ANOTHER PASS rather than by reading the
# label. The label is the mechanism; being left alone is the property.
E2E_WARDEN_TOKEN=MERGE-PARENT-OPEN run_pass "$work/s11-fleet.sh" "$st" "$db" || true
if ! grep -q 'dispatched E2E-lll' "$st/out.txt"; then
  ok "j3kp acceptance 3: the next pass does NOT pick the parent up again"
else no "the open parent was re-dispatched by the fleet" "$(cat "$st/out.txt")"; fi
if grep -q 'fleet.parent-open' "$r/emitted"; then
  ok "j3kp: the durable record carries the outcome as its own event, not as an incident"
else no "nothing in the stream says the parent was left open" "$(grep -o 'emit [a-z.]*' "$r/emitted" | sort -u | tr '\n' ' ')"; fi
# FINDING 5, THE HALF THAT MOVED. On this token the parent stays OPEN, so an
# edge taking `bd dep add`'s default would leave the follow-up blocked by it:
# absent from `bd ready`, out of the dispatchable set, and invisible in the
# Mayor's inbox — findings in a bead nobody sees until the parent closes, and
# the parent is open precisely because something is unfinished. The Overseer
# ruled a follow-up should be ACTIONABLE while its parent is open, so the edge
# records provenance. THE TYPE IS NAMED EXPLICITLY rather than left to the
# default in either direction: a default that changes under this file would
# change its behaviour silently.
if grep -q '^dep add E2E-fu1 E2E-lll .*--type discovered-from' "$db.calls"; then
  ok "finding 5: MERGE-PARENT-OPEN files its follow-up edge as a NON-BLOCKING one, named explicitly"
else no "the follow-up is still chained to a parent that stays open" "$(grep '^dep add' "$db.calls" || echo 'no dep add was logged at all')"; fi

echo
echo "=========================================================================="
echo "SCENARIO 12 — RED (acceptance 4). A launcher that CLOSES on the new token"
echo "              must fail these assertions"
echo "=========================================================================="
# GENERATED, NOT DESCRIBED (Proofdelve ForgeOs-dx34.1 round two). The wrong variant is the
# candidate with the closure branch's own condition disabled, so the new token
# falls through to the close path — which is precisely the defect: a third token
# that quietly behaves like APPROVE-WITH-FINDINGS. The RED case exists because
# scenario 11 alone is satisfied by a launcher that never closes anything.
wrong="$work/wrong-fleet.sh"
python3 - "$launcher" "$wrong" <<'PYW' || { skip "a launcher that closes on the new token is caught" "the wrong variant could not be generated: this launcher has no MERGE-PARENT-OPEN branch"; wrong=""; }
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src).read()
# ANCHORED ON THE NEWLINE, because a bare substring count cannot discriminate
# indentation: the 4- and 6-space copies of this same condition inside the
# follow-up block each CONTAIN the 2-space spelling, so `t.count()` returned 3
# and this generator refused against a launcher that had exactly what it wanted.
# The RED case then read NOT RUN, which is the one outcome a control must never
# quietly become.
old = '\n  if [ "$verdict" = "MERGE-PARENT-OPEN" ]; then\n'
if t.count(old) != 1:
    sys.exit("expected exactly one top-level MERGE-PARENT-OPEN closure branch, found %d" % t.count(old))
open(dst, "w").write(t.replace(old, '\n  if false; then  # DELIBERATELY WRONG VARIANT\n', 1))
PYW
if [ -n "$wrong" ]; then
  chmod +x "$wrong"
  IFS='|' read -r r st db <<< "$(run_with_token s12 mmm "$wrong" MERGE-PARENT-OPEN)"
  if [ "$(grep -c '^E2E-mmm|closed' "$db")" -eq 1 ]; then
    ok "RED REPRODUCED: with the closure branch disabled the parent IS wrongly closed, so scenario 11 is measuring that branch and not the absence of one"
  else no "the wrong variant did not close, so scenario 11 proves less than it claims" "$(grep '^E2E-mmm' "$db")
$(cat "$st/out.txt")"; fi
fi

echo
echo "=========================================================================="
echo "SCENARIO 13 — REFUSE (acceptance 4). An unrecognised token must not default"
echo "              to closing"
echo "=========================================================================="
if [ -z "$pre_j3kp" ]; then
  skip "an unrecognised verdict token merges nothing and closes nothing" \
       "FLEET_SH_PRE_J3KP was not set, so nothing was measured. This is NOT a pass."
else
  IFS='|' read -r r st db <<< "$(run_with_token s13 nnn "$pre_j3kp" MERGE-PARENT-OPEN)"
  out=$(cat "$st/out.txt")
  if ! merged_in "$r" nnn && [ "$(grep -c '^E2E-nnn|closed' "$db")" -eq 0 ] \
     && grep -q 'could not be parsed' <<<"$out"; then
    ok "REFUSE: the pre-j3kp launcher names the token as unparseable, merges nothing and closes nothing — an unknown token never defaults to closing"
  else no "an unrecognised token was acted on" "merged=$(merged_in "$r" nnn && echo yes || echo no) closed=$(grep -c '^E2E-nnn|closed' "$db")
$out"; fi
fi

echo
echo "=========================================================================="
echo "SCENARIO 14 — GREEN across a variant where the token STRING differs and the"
echo "              MEANINGS do not (acceptance 4)"
echo "=========================================================================="
# The spelling of the new token is not the property. Rename it throughout the
# launcher, tell the stub Warden the new spelling, and all three meanings must
# still hold: APPROVE closes, APPROVE-WITH-FINDINGS closes with a follow-up, and
# the renamed token merges and leaves the parent open. If any of these three is
# pinned to the string MERGE-PARENT-OPEN rather than to the behaviour, this
# scenario is where it shows.
renamed="$work/renamed-fleet.sh"
python3 - "$launcher" "$renamed" <<'PYR' || { skip "the three meanings survive renaming the new token" "the renamed variant could not be generated"; renamed=""; }
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src).read()
if t.count("MERGE-PARENT-OPEN") == 0:
    sys.exit("this launcher has no MERGE-PARENT-OPEN to rename")
open(dst, "w").write(t.replace("MERGE-PARENT-OPEN", "LAND-DIFF-PARENT-OPEN"))
PYR
if [ -n "$renamed" ]; then
  chmod +x "$renamed"
  IFS='|' read -r r st db <<< "$(run_with_token s14a ooo "$renamed" APPROVE)"
  a_ok=0; [ "$(grep -c '^E2E-ooo|closed' "$db")" -eq 1 ] && merged_in "$r" ooo && a_ok=1
  IFS='|' read -r r st db <<< "$(run_with_token s14b ppp "$renamed" APPROVE-WITH-FINDINGS)"
  b_ok=0; [ "$(grep -c '^E2E-ppp|closed' "$db")" -eq 1 ] && [ "$(grep -c '^E2E-fu1|' "$db")" -eq 1 ] && b_ok=1
  IFS='|' read -r r st db <<< "$(run_with_token s14c qqq "$renamed" LAND-DIFF-PARENT-OPEN)"
  # (Proofdelve ForgeOs-e2rbu: the open parent now carries mayor-lane; `open||$` pinned the defect.)
  c_ok=0; merged_in "$r" qqq && [ "$(grep -c '^E2E-qqq|open||mayor-lane$' "$db")" -eq 1 ] \
    && [ "$(grep -c '^E2E-qqq|closed' "$db")" -eq 0 ] && [ -d "$r-worktrees/qqq" ] && c_ok=1
  if [ "$a_ok$b_ok$c_ok" = "111" ]; then
    ok "GREEN: with the new token renamed throughout, APPROVE still closes, APPROVE-WITH-FINDINGS still closes with a follow-up, and the renamed token still leaves the parent open"
  else no "a meaning is pinned to the token's spelling" "approve=$a_ok approve-with-findings=$b_ok parent-open=$c_ok"; fi
fi

# ==========================================================================
# Proofdelve ForgeOs-bzyk / the 2026-09-10 sitting-two blocker — THE PATH WHERE FILING
# THE FOLLOW-UP FAILS. Three scenarios, and they are here because until today
# there was no control on this path in any harness in this fort: the stub bd
# always succeeded, so every scenario above measured the world in which the
# follow-up gets filed. A fix on a path nothing tests is reintroduced by the
# next edit to the region and the harness reports the same score either way.
#
# THE CONTRACT, FOR BOTH TOKENS. When the follow-up cannot be filed the diff
# STILL MERGED, so the promise is not "nothing happened" — it is that the bead
# is not closed on a review whose findings have no home, that it stops claiming
# to be fleet work, and that the stream says so. Four facts, and the run must
# reach all four rather than dying on the way past them:
#
#     merged            yes
#     closed            NO
#     fleet-escalated   applied
#     incident          emitted
#
# WHAT IS DELIBERATELY NOT ASSERTED. Not the incident's WORDING and not the
# follow-up bead's ID FORMAT — there is no follow-up id on this path, and the
# sentence differs by verdict on purpose (Proofdelve ForgeOs-j3kp: on APPROVE-WITH-FINDINGS
# not closing IS the failure; on MERGE-PARENT-OPEN the parent was never going to
# close and only the findings lost their bead). Scenario 17 is what proves the
# assertions are about the behaviour and not about this spelling of it.
# ==========================================================================

# The four facts, in one place, so the three scenarios below cannot drift apart.
# It prints its own diagnostic and returns 0 only when all four hold.
bzyk_path_ok() { # $1 root, $2 state, $3 db, $4 sfx -> rc; diagnostic on stdout
  local r="$1" st="$2" db="$3" sfx="$4" rec lb why=""
  rec="$(grep "^E2E-$sfx|" "$db" 2>/dev/null | head -1)"
  lb="${rec##*|}"
  merged_in "$r" "$sfx" || why="$why merged=NO"
  case "$rec" in *"|closed|"*) why="$why closed=YES" ;; esac
  case ",$lb," in *,fleet-escalated,*) ;; *) why="$why fleet-escalated=ABSENT" ;; esac
  case ",$lb," in *,fleet-safe,*) why="$why fleet-safe=STILL-SET" ;; esac
  grep -q '^incident ' "$r/emitted" 2>/dev/null || why="$why incident=NOT-EMITTED"
  [ -z "$why" ] || printf 'record=%s emitted=[%s]%s' "$rec" "$(cut -d' ' -f1 "$r/emitted" 2>/dev/null | sort -u | tr '\n' ' ')" "$why"
  [ -z "$why" ]
}

echo
echo "=========================================================================="
echo "SCENARIO 15 — THE FOLLOW-UP CANNOT BE FILED. Merge, do NOT close, take the"
echo "              bead out of the fleet, and say so — for BOTH tokens"
echo "=========================================================================="
for tok_sfx in "MERGE-PARENT-OPEN rrr s15a" "APPROVE-WITH-FINDINGS sss s15b"; do
  # shellcheck disable=SC2086  # three fields, all of them known-safe words
  set -- $tok_sfx
  IFS='|' read -r r st db <<< "$(run_with_token "$3" "$2" "$launcher" "$1" silent)"
  if d=$(bzyk_path_ok "$r" "$st" "$db" "$2"); then
    ok "$1: the follow-up could not be filed, and the run MERGED, did NOT close, applied fleet-escalated and emitted an incident"
  else no "$1: the unfileable-follow-up path did not hold its contract" "$d
$(tail -25 "$st/out.txt")"; fi
done

echo
echo "=========================================================================="
echo "SCENARIO 16 — RED. The pre-fix launcher must DIE on this path, for both"
echo "              tokens, and record none of it"
echo "=========================================================================="
# THE INVERSION, AND IT IS THE REASON SCENARIO 15 IS WORTH ANYTHING. Before the
# fix, file_followup() ended on a test of the follow-up id, both call sites are
# bare in an `if` body, and `set -euo pipefail` is unsuspended there — so an
# empty id took the run down AFTER the merge had landed. If scenario 15 passes
# against that file it is not a control.
if [ -z "$pre_a" ]; then
  skip "the pre-fix launcher dies after the merge and records nothing" \
       "FLEET_SH_PRE_A was not set, so nothing was measured. This is NOT a pass."
else
  # AND THE DIAGNOSTIC IS PART OF THE CASE, NOT DECORATION. A bare "some fact
  # failed" cannot tell a death-after-merge from a run that never merged at
  # all, and the severity of this finding is entirely in the first of those. So
  # the merge is asserted SEPARATELY and positively, and the reason the rest of
  # the contract fails is printed on the PASS line where a reader sees it.
  for tok_sfx in "MERGE-PARENT-OPEN ttt s16a" "APPROVE-WITH-FINDINGS uuu s16b"; do
    # shellcheck disable=SC2086
    set -- $tok_sfx
    IFS='|' read -r r st db <<< "$(run_with_token "$3" "$2" "$pre_a" "$1" silent)"
    d=$(bzyk_path_ok "$r" "$st" "$db" "$2") && d=""
    if [ -z "$d" ]; then
      no "$1: RED NOT REPRODUCED — the pre-fix launcher satisfies scenario 15, so scenario 15 is not measuring the fix" "$(grep "^E2E-$2|" "$db")"
    elif ! merged_in "$r" "$2"; then
      no "$1: the pre-fix run failed BEFORE the merge, so this reproduces some other defect and not the blocker" "$d"
    else
      ok "$1: RED REPRODUCED — the pre-fix launcher MERGED and then failed to complete the path ($d), so scenario 15 measures the fix and not the absence of one"
    fi
  done
fi

echo
echo "=========================================================================="
echo "SCENARIO 17 — GREEN across a correct variant (Proofdelve ForgeOs-8zb7 step 2). Rename"
echo "              the internals, reword every sentence, same behaviour"
echo "=========================================================================="
# GENERATED, NOT DESCRIBED. The variant renames both of file_followup()'s return
# globals and rewrites all three pieces of prose this path produces — the two
# per-verdict `lost` sentences and the incident's own detail. Nothing about its
# behaviour changes. If scenario 15 is pinned to a word rather than to the four
# facts, this is where it shows, and this fort has now performed step 2 three
# times: dx34.1 round two, the reap variant, and here.
variant="$work/bzyk-variant-fleet.sh"
python3 - "$launcher" "$variant" <<'PYB' || { skip "the four facts survive renaming the internals and rewording the prose" "the correct variant could not be generated"; variant=""; }
import sys, re
src, dst = sys.argv[1], sys.argv[2]
t = open(src).read()
for old, new in (("followup_bead", "carried_id"), ("followup_body", "carried_body")):
    if t.count(old) < 3:
        sys.exit("expected the %s global to be used at least 3 times, found %d" % (old, t.count(old)))
    t = t.replace(old, new)
# the three sentences this path emits, rewritten and not merely shuffled
prose = [
 ('lost="the follow-up bead could not be filed, so the findings have no bead of their own; the parent is open as intended and the review is on it"',
  'lost="no bead was opened for the findings; the parent stays open as the reviewer intended and her review sits on it"'),
 ('lost="the follow-up triage bead could not be filed, so the parent was NOT closed"',
  'lost="no triage bead was opened, so this parent stays open"'),
]
for old, new in prose:
    if t.count(old) != 1:
        sys.exit("expected exactly one copy of a per-verdict sentence, found %d" % t.count(old))
    t = t.replace(old, new, 1)
# ANCHORED ON THE SENTENCE'S HEAD, NOT ITS FULL SPELLING (the 2026-09-14 rule:
# a generator pinning a whole line refuses the whole scenario for the next
# CORRECT change). Proofdelve ForgeOs-s2lx appended the label-write outcome to this
# detail's tail and this generator went NOT RUN for it. The detail carries no
# inner double quote, so the match runs to the closing one.
old_head = 'emit incident "Fleet merged $bead on $verdict but could NOT file the follow-up bead: $lost.'
if t.count(old_head) != 1:
    sys.exit("expected exactly one unfileable-follow-up incident detail, found %d" % t.count(old_head))
m = re.search(re.escape(old_head) + r'[^"]*"', t)
if not m:
    sys.exit("the unfileable-follow-up incident detail has no closing quote on its line")
t = t[:m.start()] + 'emit incident "Filing a bead for the findings of $bead failed on $verdict after the diff had landed: $lost."' + t[m.end():]
open(dst, "w").write(t)
PYB
if [ -n "$variant" ]; then
  chmod +x "$variant"
  v_ok=1
  for tok_sfx in "MERGE-PARENT-OPEN vvv s17a" "APPROVE-WITH-FINDINGS www s17b"; do
    # shellcheck disable=SC2086
    set -- $tok_sfx
    IFS='|' read -r r st db <<< "$(run_with_token "$3" "$2" "$variant" "$1" silent)"
    bzyk_path_ok "$r" "$st" "$db" "$2" >/dev/null || { v_ok=0; vd="$1: $(bzyk_path_ok "$r" "$st" "$db" "$2")"; }
  done
  if [ "$v_ok" = 1 ]; then
    ok "GREEN: both globals renamed and all three sentences rewritten, and the four facts still hold for both tokens"
  else no "scenario 15 is pinned to this spelling rather than to the behaviour" "${vd:-}"; fi
fi


# ==========================================================================
# SITTING THREE (2026-09-10). Items 4, 1 and 2 of the sitting-three docket.
#
# ONE "BEFORE" FILE FOR ALL OF THEM, AND IT IS NAMED ONCE. The three defects
# below coexisted in the launcher as it stood at the start of this sitting, so
# splitting FLEET_SH_PRE_S3 into three synonyms pointing at one sha would be
# ceremony rather than care. Each inversion states which defect it reproduces,
# which is what makes a shared before-file attributable. It is OPTIONAL and
# reported NOT RUN rather than PASS when absent: an inversion that did not run
# has established nothing.
#   git show a2acdbe:fort/scripts/fleet.sh > /tmp/fleet-pre-s3.sh
# ==========================================================================
pre_s3="${FLEET_SH_PRE_S3:-}"

# Run the dispatcher WITHOUT --once, bounded. Exit 124 means it never
# terminated, which is the whole of Proofdelve ForgeOs-czhb acceptance 7.
run_loop() { # $1 launcher, $2 state, $3 db, $4 timeout secs -> rc
  FLEET_STATE="$2" BD_STORE="$3" timeout "$4" "$1" > "$2/out.txt" 2>&1
}

# Take a bead to a PARKED merge under a chosen token, by dirtying the root the
# way scenario 1 does. Prints "root|state|db". The caller cleans the tree and
# runs another pass to exercise the resume ladder.
defer_to_park() { # $1 name, $2 sfx, $3 launcher-src, $4 token
  local r st db
  r=$(mkfort "$1" ok); mk_launcher "$3" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  echo two >> "$r/subject.txt"                    # uncommitted tracked source
  E2E_WARDEN_TOKEN="$4" run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  wait_forge "$st" "$2"
  E2E_WARDEN_TOKEN="$4" run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  printf '%s|%s|%s' "$r" "$st" "$db"
}
resume_park() { # $1 name, $2 root, $3 state, $4 db, $5 token
  git -C "$2" checkout -- subject.txt
  E2E_WARDEN_TOKEN="$5" run_pass "$work/$1-fleet.sh" "$3" "$4" || true
}

echo
echo "=========================================================================="
echo "SCENARIO 18 — czhb acceptance 1+2. A NON-BLOCKING edge to an OPEN bead is"
echo "              DISPATCHED; a blocks edge to an OPEN bead is REFUSED"
echo "=========================================================================="
r=$(mkfort s18 ok); mk_launcher "$launcher" "$work/s18-fleet.sh" "$r" || exit 3
st="$work/s18-state"; mkdir -p "$st"; db="$work/s18.bd"
# THE REFUSED BEAD IS FIRST, DELIBERATELY. dispatch_pass stops once it has
# filled its slots and FLEET_FORGE_START is 1 here, so a dispatchable bead ahead
# of the refused one ends the loop before the refusal is ever reached -- and the
# case would report "no skip line" as a failure of the guard rather than of the
# fixture. A skip does not consume a slot; a dispatch does.
{ printf 'E2E-par|open||\n'
  printf 'E2E-b18|open||fleet-safe|E2E-par:open:blocks\n'
  printf 'E2E-n18|open||fleet-safe|E2E-par:open:parent-child\n'; } > "$db"
run_dry_pass "$work/s18-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
if grep -q 'DRY-RUN would dispatch E2E-n18' <<<"$out"; then
  ok "czhb 1: a parent-child edge to an OPEN bead no longer blocks dispatch"
else no "a non-blocking edge still refuses" "$out"; fi
if grep -q 'skip E2E-b18' <<<"$out" && grep -q 'the edge type is blocks' <<<"$out"; then
  ok "czhb 2+6: a blocks edge to an OPEN bead is still refused, and the reason NAMES THE TYPE"
else no "a blocks edge was not refused, or the refusal does not say why" "$out"; fi

echo
echo "=========================================================================="
echo "SCENARIO 19 — czhb acceptance 7. THE RUN TERMINATES on an all-refused"
echo "              queue instead of polling forever"
echo "=========================================================================="
# THE DEFECT THIS REPRODUCES: the drain check asked `bd ready`, which RETURNS a
# refused bead, while dispatch_pass asked dispatchable(), which refuses it.
# Neither side moved, the budget could not end the run because budget_left() is
# only consulted before a launch and there were no launches, and the run held
# the exclusive flock. Measured live on 2026-09-10 as six identical passes.
# NO --once HERE, deliberately: --once breaks after one pass whatever the drain
# check concludes, so every other scenario in this file is blind to this.
r=$(mkfort s19 ok); mk_launcher "$launcher" "$work/s19-fleet.sh" "$r" || exit 3
st="$work/s19-state"; mkdir -p "$st"; db="$work/s19.bd"
{ printf 'E2E-par|open||\n'
  printf 'E2E-w19|open||fleet-safe|E2E-par:open:blocks\n'; } > "$db"
run_loop "$work/s19-fleet.sh" "$st" "$db" 20; rc=$?; out=$(cat "$st/out.txt")
if [ "$rc" -ne 124 ] && grep -q 'queue drained' <<<"$out"; then
  ok "czhb 7: a queue of only-refused beads DRAINS and the run exits (rc=$rc, passes=$(printf '%s' "$out" | grep -c 'skip E2E-w19'))"
else no "the run did not terminate" "rc=$rc (124 = killed by timeout, i.e. still polling)
$out"; fi
# THE VACUITY CONTROL, AND IT MUST NOT USE --once (the Warden, covenant-4.5
# review of this sitting, blocking finding). The first version of this case ran
# under run_pass, which passes --once -- and the main loop breaks on --once at
# fleet.sh:2506, BEFORE the drain check at :2542. The drain check never executed,
# so "queue drained" could not have been printed by any launcher right or wrong,
# and the case passed unconditionally while guarding the very property the
# scenario above exists to establish. A control that cannot fail is Proofdelve ForgeOs-8zb7
# class A, and this was one.
#
# AND THE FIXTURE HAS TO REACH THE CHECK WITH NOTHING RUNNING AND WORK STILL
# AVAILABLE, or it still does not discriminate: with a Forge alive,
# `live_forges -eq 0` short-circuits and any_dispatchable() is never consulted at
# all, so a drain check hardwired to "no work" would pass too. FLEET_FORGE_START=0
# gives zero slots, so dispatch_pass returns having launched nothing and
# live_forges stays 0, while the queue's one bead is genuinely dispatchable --
# which is exactly the state in which any_dispatchable() must answer YES.
r=$(mkfort s19b ok); mk_launcher "$launcher" "$work/s19b-fleet.sh" "$r" || exit 3
sed -i 's/^FLEET_FORGE_START=1$/FLEET_FORGE_START=0/; s/^FLEET_FORGE_MIN=1$/FLEET_FORGE_MIN=0/' "$r/fort/scripts/fleet.conf"
st="$work/s19b-state"; mkdir -p "$st"; db="$work/s19b.bd"
printf 'E2E-g19|open||fleet-safe\n' > "$db"
run_loop "$work/s19b-fleet.sh" "$st" "$db" 8; rc=$?; out=$(cat "$st/out.txt")
# THE PROPERTY IS "NO DRAIN DECLARED", AND ITS SHAPE CHANGED ON 2026-09-10
# (Proofdelve ForgeOs-dx34.9). Zero slots with startable work is a run that can never
# change state, which is a stall by construction: the launcher now HALTS ITSELF
# on it (rc 70, reason stalled) where it used to poll until the timeout (rc
# 124). Both shapes satisfy this control and a launcher that DRAINS fails it;
# the PASS line names the shape it saw so the two launchers stay tellable apart.
if ! grep -q 'queue drained' <<<"$out" \
   && { [ "$rc" -eq 124 ] || { [ "$rc" -eq 70 ] && grep -q 'HALT: .*consecutive passes changed no state' <<<"$out"; }; }; then
  shape="kept polling until the timeout (pre-dx34.9 shape)"
  [ "$rc" -eq 70 ] && shape="halted itself as STALLED after 3 no-state passes (dx34.9 shape)"
  ok "VACUITY CONTROL: nothing running and work still dispatchable — the run does NOT declare a drain; it $shape"
else no "the drain check fired on a queue that still has work, or the run ended a third way" "rc=$rc
$out"; fi
# THE INVERSION THAT MAKES THAT A CONTROL RATHER THAN AN OBSERVATION. A launcher
# whose any_dispatchable() always answers "no work" MUST drain the same fixture.
# Generated from the shipped file by substitution, so it cannot drift from it.
blind="$work/blind-drain.sh"
# shellcheck disable=SC2016  # the single quotes are the point: a sed pattern
# matching literal shell text inside the launcher.
if sed 's/^any_dispatchable()[[:space:]]*{$/any_dispatchable() { return 1 #/' "$launcher" > "$blind" \
   && [ "$(grep -cE '^any_dispatchable\(\)[[:space:]]*\{ return 1 #' "$blind")" -eq 1 ]; then
  chmod +x "$blind"
  r2=$(mkfort s19c ok); mk_launcher "$blind" "$work/s19c-fleet.sh" "$r2" || exit 3
  sed -i 's/^FLEET_FORGE_START=1$/FLEET_FORGE_START=0/; s/^FLEET_FORGE_MIN=1$/FLEET_FORGE_MIN=0/' "$r2/fort/scripts/fleet.conf"
  st2="$work/s19c-state"; mkdir -p "$st2"; db2="$work/s19c.bd"
  printf 'E2E-g19|open||fleet-safe\n' > "$db2"
  run_loop "$work/s19c-fleet.sh" "$st2" "$db2" 8; rc2=$?
  if [ "$rc2" -ne 124 ] && grep -q 'queue drained' "$st2/out.txt"; then
    ok "RED: a drain check blind to any_dispatchable() DOES drain that fixture, so the control above can fail"
  else no "the vacuity control cannot fail: the blinded launcher did not drain either" "rc=$rc2
$(cat "$st2/out.txt")"; fi
else
  skip "vacuity-control inversion" "could not blind any_dispatchable() in $launcher"
fi

echo
echo "=========================================================================="
echo "SCENARIO 20 — RED. The pre-sitting launcher must NOT terminate on scenario"
echo "              19's fixture, and must refuse its non-blocking bead"
echo "=========================================================================="
if [ -z "$pre_s3" ] || [ ! -f "$pre_s3" ]; then
  skip "czhb inversion" "set FLEET_SH_PRE_S3 to the launcher before this sitting"
else
  mk_launcher "$pre_s3" "$work/s20-fleet.sh" "$work/s20" 2>/dev/null || true
  r=$(mkfort s20 ok); mk_launcher "$pre_s3" "$work/s20-fleet.sh" "$r" || exit 3
  st="$work/s20-state"; mkdir -p "$st"; db="$work/s20.bd"
  { printf 'E2E-par|open||\n'
    printf 'E2E-w19|open||fleet-safe|E2E-par:open:blocks\n'; } > "$db"
  run_loop "$work/s20-fleet.sh" "$st" "$db" 12; rc=$?; out=$(cat "$st/out.txt")
  if [ "$rc" -eq 124 ] && [ "$(printf '%s' "$out" | grep -c 'skip E2E-w19')" -ge 2 ]; then
    ok "RED: the pre-sitting launcher polled the same refused bead $(printf '%s' "$out" | grep -c 'skip E2E-w19') times and had to be killed"
  else no "the wedge did not reproduce" "rc=$rc passes=$(printf '%s' "$out" | grep -c 'skip E2E-w19')
$out"; fi
  r=$(mkfort s20b ok); mk_launcher "$pre_s3" "$work/s20b-fleet.sh" "$r" || exit 3
  st="$work/s20b-state"; mkdir -p "$st"; db="$work/s20b.bd"
  { printf 'E2E-par|open||\n'
    printf 'E2E-n18|open||fleet-safe|E2E-par:open:parent-child\n'; } > "$db"
  run_dry_pass "$work/s20b-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
  if grep -q 'skip E2E-n18' <<<"$out" && ! grep -q 'would dispatch E2E-n18' <<<"$out"; then
    ok "RED: the pre-sitting launcher refused the parent-child bead the fix dispatches"
  else no "the pre-fix file did not refuse a non-blocking edge" "$out"; fi
fi

echo
echo "=========================================================================="
echo "SCENARIO 21 — j3kp finding 1. A DEFERRED MERGE-PARENT-OPEN RESUMES AND"
echo "              LANDS, with the parent still open and the follow-up filed"
echo "=========================================================================="
# THE INSTRUMENT IS END TO END, NOT SOURCE EXTRACTION (docket correction C4,
# which asks that this criterion name its instrument). A deferral needs a
# trigger and a second pass, and no scenario in this file did that for any token
# before now: the tree is dirtied so land() parks the merge, then cleaned so the
# resume ladder runs for real.
IFS='|' read -r r st db <<< "$(defer_to_park s21 mpo "$launcher" MERGE-PARENT-OPEN)"
out=$(cat "$st/out.txt")
if grep -q 'NOT MERGED this pass' <<<"$out"; then
  ok "j3kp 1: the MERGE-PARENT-OPEN merge PARKED on a dirty tree (the deferral really happened)"
else no "the merge did not park, so the resume ladder is not under test" "$out"; fi
resume_park s21 "$r" "$st" "$db" MERGE-PARENT-OPEN; out=$(cat "$st/out.txt")
if grep -q 'RETRYING THE DEFERRED MERGE ALONE' <<<"$out" && merged_in "$r" mpo; then
  ok "j3kp 1: the deferred MERGE-PARENT-OPEN RESUMED and the diff LANDED"
else no "the deferred new token did not resume" "$out"; fi
if [ "$(grep -c '^E2E-mpo|closed' "$db")" -eq 0 ] && [ "$(grep -c '^E2E-fu1|' "$db")" -eq 1 ]; then
  ok "j3kp 1: and it kept its meaning on resume — parent still OPEN, follow-up filed"
else no "the resumed token lost its meaning" "$(cat "$db")
$out"; fi
if ! grep -q 'NEEDS A PERSON' <<<"$out"; then
  ok "j3kp 1: nothing was escalated to a person"
else no "the resumed token still reached needs-person" "$out"; fi

echo
echo "=========================================================================="
echo "SCENARIO 22 — j3kp finding 1, criterion 6 (NEW, correction C1). A DEFERRED"
echo "              PLAIN APPROVE STILL RESUMES AND LANDS"
echo "=========================================================================="
# THIS IS THE CRITERION C1 EXISTS TO ADD, and its absence is what made the
# one-predicate remedy look correct. APPROVE is landable and files NO follow-up,
# so a single predicate keyed on "does this verdict file a follow-up" -- which
# is what the docket's emphasised text instructed -- would send every deferred
# plain APPROVE to needs-person. The record is emptied first, because APPROVE
# must land WITHOUT one; only the two follow-up tokens need it.
IFS='|' read -r r st db <<< "$(defer_to_park s22 apo "$launcher" APPROVE)"
: > "$st/workers/apo/warden-record"
resume_park s22 "$r" "$st" "$db" APPROVE; out=$(cat "$st/out.txt")
if merged_in "$r" apo && [ "$(grep -c '^E2E-apo|closed' "$db")" -eq 1 ] \
   && ! grep -q 'NEEDS A PERSON' <<<"$out"; then
  ok "C1 criterion 6: a deferred plain APPROVE resumed, landed and closed with an EMPTY record, as it must"
else no "a deferred plain APPROVE no longer lands — this is finding 1 moved onto APPROVE" "closed=$(grep -c '^E2E-apo|closed' "$db")
$out"; fi

echo
echo "=========================================================================="
echo "SCENARIO 23 — j3kp finding 1, criterion 4. THE SECOND TRIGGER IS SHOWN NOT"
echo "              TO FIRE: a deferred MERGE-PARENT-OPEN with NO stored record"
echo "=========================================================================="
# THE CASE THE NAIVE :2173-ONLY FIX WOULD BREAK, and the reason this was never a
# one-line change. Teaching the resume arm the third token WITHOUT teaching the
# record check would hand a recordless MERGE-PARENT-OPEN to a path only ever
# exercised for the two tokens it already knew: the merge lands and the
# follow-up that carries the findings cannot be written, which is the
# Proofdelve ForgeOs-bzyk orphan unmasked by a second route inside the fix for the first.
IFS='|' read -r r st db <<< "$(defer_to_park s23 mpx "$launcher" MERGE-PARENT-OPEN)"
: > "$st/workers/mpx/warden-record"
resume_park s23 "$r" "$st" "$db" MERGE-PARENT-OPEN; out=$(cat "$st/out.txt")
if grep -q 'NEEDS A PERSON' <<<"$out" && ! merged_in "$r" mpx; then
  ok "j3kp 4: a recordless MERGE-PARENT-OPEN stops at NEEDS A PERSON and nothing is merged"
else no "the second trigger fired: a recordless new token was acted on" "merged=$(merged_in "$r" mpx && echo yes || echo no)
$out"; fi
# THE LOOSEST FORM THAT STILL DISCRIMINATES (Proofdelve ForgeOs-8zb7 class B). What must
# be true is that the refusal names THE VERDICT IT ACTUALLY HAD and says the
# RECORD is what is missing -- the pre-fix message names neither, because it
# stops at the verdict arm and its text is hardcoded to the other token. The
# sentence around those two facts is deliberately not pinned, so scenario 29's
# reworded variant does not redden for a correct change.
npline="$(grep 'NEEDS A PERSON' "$st/out.txt" 2>/dev/null | head -1)"
if grep -q 'MERGE-PARENT-OPEN' <<<"$npline" && grep -qi 'record' <<<"$npline"; then
  ok "j3kp 4: and the refusal names the verdict it actually had and points at the record"
else no "the needs-person message still names the wrong token" "line: ${npline:-<none>}"; fi

echo
echo "=========================================================================="
echo "SCENARIO 24 — RED. The pre-sitting launcher must send a deferred"
echo "              MERGE-PARENT-OPEN to NEEDS A PERSON (finding 1 itself)"
echo "=========================================================================="
if [ -z "$pre_s3" ] || [ ! -f "$pre_s3" ]; then
  skip "finding 1 inversion" "set FLEET_SH_PRE_S3 to the launcher before this sitting"
else
  IFS='|' read -r r st db <<< "$(defer_to_park s24 mpr "$pre_s3" MERGE-PARENT-OPEN)"
  resume_park s24 "$r" "$st" "$db" MERGE-PARENT-OPEN; out=$(cat "$st/out.txt")
  if grep -q 'no usable stored verdict' <<<"$out" && ! merged_in "$r" mpr; then
    ok "RED: the pre-sitting launcher called a perfectly good MERGE-PARENT-OPEN verdict unusable BY NAME"
  else no "finding 1 did not reproduce, so scenario 21 is not measuring it" "$out"; fi
fi

echo
echo "=========================================================================="
echo "SCENARIO 25 — docket item 2 / correction C2. AN UNBUILDABLE FOLLOW-UP BODY"
echo "              TAKES THE bzyk BRANCH: merged, NOT closed, escalated, LOUD"
echo "=========================================================================="
# WHAT C2 CORRECTS, AND WHY THE OBVIOUS ASSERTION IS NOT ENOUGH. `|| true` on the
# body-building group would let the run continue with a body whose verbatim
# section is EMPTY -- the header printfs having already succeeded -- so bd create
# would SUCCEED, followup_bead would be set, the bzyk branch would be SKIPPED, no
# incident emitted, and the parent CLOSED on APPROVE-WITH-FINDINGS with the
# findings gone. A size test alone cannot see that either, for the same reason.
#
# AND "NO BEAD WAS FILED AND NOTHING CLOSED" IS SATISFIED BY A RUN THAT SIMPLY
# DIED, which is what the pre-fix launcher does here -- so that pair of
# assertions does not discriminate the fix from the bug and this scenario used
# them in its first draft. The contract is asserted instead, through this file's
# own bzyk_path_ok: MERGED, not closed, fleet-safe removed, fleet-escalated
# applied, and an incident on the stream. A dying run reaches none of the last
# three.
for tok_sfx in "APPROVE-WITH-FINDINGS xaw s25a" "MERGE-PARENT-OPEN xmp s25b"; do
  # shellcheck disable=SC2086
  set -- $tok_sfx
  r=$(mkfort "$3" ok); mk_launcher "$launcher" "$work/$3-fleet.sh" "$r" || exit 3
  st="$work/$3-state"; mkdir -p "$st"; db="$work/$3.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  E2E_WARDEN_TOKEN="$1" E2E_WARDEN_RESULT=norecord run_pass "$work/$3-fleet.sh" "$st" "$db" || true
  wait_forge "$st" "$2"
  E2E_WARDEN_TOKEN="$1" E2E_WARDEN_RESULT=norecord run_pass "$work/$3-fleet.sh" "$st" "$db" || true
  if d=$(bzyk_path_ok "$r" "$st" "$db" "$2"); then
    ok "C2 [$1]: an unbuildable body MERGED, did NOT close, escalated the bead and emitted an incident"
  else no "C2 [$1]: the unbuildable-body path did not hold the bzyk contract" "$d
$(tail -20 "$st/out.txt")"; fi
  if grep -q 'could not be built from' "$st/out.txt"; then
    ok "C2 [$1]: and the run SURVIVED and said so, rather than dying inside file_followup()"
  else no "C2 [$1]: nothing announced the unbuildable body" "$(tail -20 "$st/out.txt")"; fi
done

echo
echo "=========================================================================="
echo "SCENARIO 26 — docket item 3 / correction C3. THE DEPENDENCY ASSERTION IS"
echo "              POSITIVE, TOLERATES BOTH FLAG SYNTAXES, AND DISCRIMINATES"
echo "=========================================================================="
# One predicate, applied in BOTH directions. Scenario 10 asserted a NEGATIVE
# list -- "the call must not mention -from, related or tracks" -- which is a
# spelling pinned in disguise: bd's vocabulary has ten types and the list named
# three, so `--type parent-child` would have passed it silently. What must be
# TRUE is that the older token's edge is still a BLOCKING one, and there are
# exactly two spellings that produce one.
if dep_edge_is_blocking 'dep add A B --actor x' \
   && dep_edge_is_blocking 'dep add A B --type blocks --actor x' \
   && dep_edge_is_blocking 'dep add A B --type=blocks' \
   && ! dep_edge_is_blocking 'dep add A B --type discovered-from --actor x' \
   && ! dep_edge_is_blocking 'dep add A B --type=parent-child' \
   && ! dep_edge_is_blocking 'dep add A B --type blocks-someday' \
   && ! dep_edge_is_blocking ''; then
  ok "item 3: the predicate accepts both blocking spellings, both flag syntaxes, and rejects every non-blocking one"
else no "the blocking-edge predicate does not discriminate" "see dep_edge_is_blocking"; fi


echo
echo "=========================================================================="
echo "SCENARIO 27 — RED (C1). THE NAIVE ONE-PREDICATE FIX MUST BREAK A DEFERRED"
echo "              PLAIN APPROVE, which is what criterion 6 exists to catch"
echo "=========================================================================="
# The docket's emphasised instruction was to key BOTH resume sites on one
# property, "does this verdict file a follow-up". This variant does exactly that
# and nothing else, deterministically generated from the shipped file rather than
# described -- and a deferred plain APPROVE must then be escalated to a person,
# which is finding 1 moved off MERGE-PARENT-OPEN and onto APPROVE. Without this
# case, scenario 22 passes against both the right fix and the wrong one.
naive1="$work/naive-one-predicate.sh"
# shellcheck disable=SC2016  # the single quotes are the point: these are
# sed and grep patterns matching literal shell text inside the launcher.
if sed 's/if ! verdict_is_landable "\$lverdict"; then/if ! verdict_files_followup "$lverdict"; then/' \
     "$launcher" > "$naive1" \
   && [ "$(grep -c 'if ! verdict_files_followup "\$lverdict"; then' "$naive1")" -eq 1 ]; then
  chmod +x "$naive1"
  IFS='|' read -r r st db <<< "$(defer_to_park s27 apo "$naive1" APPROVE)"
  : > "$st/workers/apo/warden-record"
  resume_park s27 "$r" "$st" "$db" APPROVE; out=$(cat "$st/out.txt")
  if grep -q 'no usable stored verdict' <<<"$out" && ! merged_in "$r" apo; then
    ok "RED (C1): the one-predicate remedy DOES send a deferred plain APPROVE to a person, so scenario 22 discriminates"
  else no "the naive one-predicate variant did not break APPROVE, so scenario 22 proves nothing" "$out"; fi
else
  skip "C1 naive-variant control" "could not generate the one-predicate variant from $launcher"
fi

echo
echo "=========================================================================="
echo "SCENARIO 28 — RED (docket criterion 4). THE NAIVE :2173-ONLY FIX MUST LET A"
echo "              RECORDLESS MERGE-PARENT-OPEN THROUGH — the second trigger"
echo "=========================================================================="
# Teach the verdict arm the third token but leave the RECORD check hardcoded to
# APPROVE-WITH-FINDINGS, which is the one-line repair the docket warns against.
# A recordless MERGE-PARENT-OPEN then reaches land(), and the findings it exists
# to carry cannot be written: the Proofdelve ForgeOs-bzyk orphan by a second route.
naive2="$work/naive-2173-only.sh"
# shellcheck disable=SC2016  # the single quotes are the point: these are
# sed and grep patterns matching literal shell text inside the launcher.
if sed 's/if verdict_files_followup "\$lverdict" \&\& \[ ! -s "\$lrecord" \]; then/if [ "$lverdict" = "APPROVE-WITH-FINDINGS" ] \&\& [ ! -s "$lrecord" ]; then/' \
     "$launcher" > "$naive2" \
   && [ "$(grep -c 'if \[ "\$lverdict" = "APPROVE-WITH-FINDINGS" \] && \[ ! -s "\$lrecord" \]; then' "$naive2")" -eq 1 ]; then
  chmod +x "$naive2"
  IFS='|' read -r r st db <<< "$(defer_to_park s28 mpx "$naive2" MERGE-PARENT-OPEN)"
  : > "$st/workers/mpx/warden-record"
  resume_park s28 "$r" "$st" "$db" MERGE-PARENT-OPEN; out=$(cat "$st/out.txt")
  if merged_in "$r" mpx; then
    ok "RED (criterion 4): the :2173-only remedy DOES merge a recordless MERGE-PARENT-OPEN, so scenario 23 discriminates"
  else no "the second trigger did not fire in the naive variant, so scenario 23 proves nothing" "$out"; fi
else
  skip "criterion 4 naive-variant control" "could not generate the :2173-only variant from $launcher"
fi

echo
echo "=========================================================================="
echo "SCENARIO 29 — GREEN across a CORRECT variant (Proofdelve ForgeOs-8zb7 step 2). Rename"
echo "              both predicates and reword both refusals: same behaviour"
echo "=========================================================================="
# The half that says the three scenarios above assert the PROPERTY rather than
# this sitting's spelling of it. Both function names change, and both
# needs-person sentences are rewritten around the two facts scenario 23 requires
# (the verdict it had, and that the record is what is missing).
corr="$work/correct-variant.sh"
python3 - "$launcher" "$corr" <<'PYC'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
pairs = [("verdict_is_landable", "may_act_on_stored_verdict"),
         ("verdict_files_followup", "verdict_needs_its_record")]
for old, new in pairs:
    if t.count(old) < 3:
        sys.exit("expected the predicate %s at its definition and both call sites, found %d" % (old, t.count(old)))
    t = t.replace(old, new)
prose = [
 ("""say "$bead: deferred at the merge with no usable stored verdict — NEEDS A PERSON\"""",
  """say "$bead: its stored verdict ('$lverdict') is not one this fleet may act on — NEEDS A PERSON\""""),
 ("""say "$bead: deferred on $lverdict but its stored review record is gone — NEEDS A PERSON\"""",
  """say "$bead: on $lverdict the review record is what is missing, so the findings cannot be carried — NEEDS A PERSON\""""),
]
for old, new in prose:
    if t.count(old) != 1:
        sys.exit("expected exactly one copy of a resume-arm sentence, found %d" % t.count(old))
    t = t.replace(old, new, 1)
open(dst, "w", encoding="utf-8").write(t)
PYC
if [ -s "$corr" ]; then
  chmod +x "$corr"
  v_ok=1; vwhy=""
  IFS='|' read -r r st db <<< "$(defer_to_park s29a mpo "$corr" MERGE-PARENT-OPEN)"
  resume_park s29a "$r" "$st" "$db" MERGE-PARENT-OPEN
  if merged_in "$r" mpo && [ "$(grep -c '^E2E-mpo|closed' "$db")" -eq 0 ]; then :
  else v_ok=0; vwhy="$vwhy deferred-MPO-did-not-land-or-closed"; fi
  IFS='|' read -r r st db <<< "$(defer_to_park s29b apo "$corr" APPROVE)"
  : > "$st/workers/apo/warden-record"
  resume_park s29b "$r" "$st" "$db" APPROVE
  merged_in "$r" apo || { v_ok=0; vwhy="$vwhy deferred-APPROVE-did-not-land"; }
  IFS='|' read -r r st db <<< "$(defer_to_park s29c mpx "$corr" MERGE-PARENT-OPEN)"
  : > "$st/workers/mpx/warden-record"
  resume_park s29c "$r" "$st" "$db" MERGE-PARENT-OPEN; out=$(cat "$st/out.txt")
  npline="$(grep 'NEEDS A PERSON' "$st/out.txt" 2>/dev/null | head -1)"
  if merged_in "$r" mpx; then v_ok=0; vwhy="$vwhy recordless-MPO-merged"; fi
  if grep -q 'MERGE-PARENT-OPEN' <<<"$npline" && grep -qi 'record' <<<"$npline"; then :
  else v_ok=0; vwhy="$vwhy refusal-lost-its-two-facts[$npline]"; fi
  if [ "$v_ok" = 1 ]; then
    ok "GREEN: both predicates renamed and both refusals reworded, and all three resume properties still hold"
  else no "the resume scenarios are pinned to this sitting's spelling rather than to the behaviour" "$vwhy"; fi
else
  skip "correct-variant control" "could not generate the reworded variant"
fi

echo
echo "=========================================================================="
echo "SCENARIO 30 — Proofdelve ForgeOs-dx34.9 acceptance 1-3, POSITIVE. A WEDGED RUN HALTS"
echo "              ITSELF: no halt file from a person, no person"
echo "=========================================================================="
# THE WEDGE RECIPE, AND WHY IT IS NOT czhb's. The bead names "a bead bd ready
# clears and the dispatch guard refuses" as the known recipe; on the shipped
# launcher that recipe DRAINS, because czhb made both sides ask
# any_dispatchable() (scenario 19). The next wedge has a different cause, and
# fleet.sh names one in any_dispatchable()'s own header: a bead dispatchable()
# accepts whose worktree a launcher OUTSIDE this run holds. dispatch_pass skips
# it on forge.sh's flock, the drain check counts it as work, and no pass can
# differ from the last. Built here by holding that flock from a process that is
# not a fleet worker -- which is what a forge.sh started by hand, or an orphan
# of a killed run, does to the fleet. Under FLEET_POLL=1 and
# FLEET_STALL_PASSES=3 the fixed launcher halts in about four seconds; the 20s
# timeout is the ceiling that keeps a regressed launcher from hanging this file.
r=$(mkfort s30 ok); mk_launcher "$launcher" "$work/s30-fleet.sh" "$r" || exit 3
st="$work/s30-state"; mkdir -p "$st"; db="$work/s30.bd"
printf 'E2E-st1|open||fleet-safe\n' > "$db"
mkdir -p "$r-worktrees/st1"
flock "$r-worktrees/st1/.forge.lock" sleep 60 &
lockholder=$!; sleep 0.3
run_loop "$work/s30-fleet.sh" "$st" "$db" 20; rc=$?; out=$(cat "$st/out.txt")
kill "$lockholder" 2>/dev/null; wait "$lockholder" 2>/dev/null
ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
if [ "$rc" -eq 70 ] && [ -e "$st/HALT" ] && grep -q 'consecutive passes changed no state' "$st/HALT" \
   && grep -q 'stall 3/3' <<<"$out" && ! grep -q 'queue drained' <<<"$out"; then
  ok "acceptance 1+3: the wedged run halted ITSELF (rc=70) after 3 no-state passes -- no halt file from a person, no person, no drain declared"
else no "the wedged run did not halt itself" "rc=$rc HALT=$([ -e "$st/HALT" ] && echo present || echo absent)
$out"; fi
if grep -q '"reason":"stalled: ' <<<"$ended" && grep -q '"stalled":true' <<<"$ended" \
   && ! grep -q '"reason":"drained' <<<"$ended" && ! grep -q '"reason":"halted: ' <<<"$ended" \
   && ! grep -q '"interrupted":true' <<<"$ended"; then
  ok "acceptance 2 / Proofdelve ForgeOs-6843: fleet.ended says stalled -- not drained, not halted:, not interrupted -- and carries stalled:true"
else no "the stall did not record itself as a stall in fleet.ended" "$ended"; fi
if printf '%s' "$out" | grep 'stall 1/3' | grep -q 'a live launcher already holds' \
   && grep -q 'a live launcher already holds' "$st/HALT"; then
  ok "the stall lines and the halt file NAME the divergence (the foreign lock), so the halt says what the stall was made of"
else no "the stall lines do not say what diverged" "$(printf '%s' "$out" | grep 'stall '; cat "$st/HALT")"; fi
if grep -q 'FLEET STALLED' "$r/emitted" && [ "$(grep -c '^E2E-st1|open||fleet-safe' "$db")" -eq 1 ]; then
  ok "a FLEET STALLED incident was emitted, and the bead was never claimed: the halt left the tracker as it found it"
else no "no FLEET STALLED incident, or the bead was touched" "$(cat "$db"; grep -c incident "$r/emitted")"; fi

# THE INVERSION. The same wedge against the launcher before this sitting must
# SPIN: identical passes until the timeout kills it, no halt file, no stalled
# reason. That is the 16-minute run of 2026-09-10 reproduced in eight seconds,
# and without it scenario 30 is an observation rather than a control.
# READ 124 CORRECTLY: timeout returns 124 when IT fired, which here means the
# run did not stop by itself -- the property. The skip count is the positive
# evidence that it was spinning on the wedge and not stuck somewhere else.
if [ -z "$pre_dx349" ] || [ ! -f "$pre_dx349" ]; then
  skip "dx34.9 inversion" "set FLEET_SH_PRE_DX349 to the launcher before this sitting (git show 233d977:fort/scripts/fleet.sh)"
else
  r=$(mkfort s30b ok); mk_launcher "$pre_dx349" "$work/s30b-fleet.sh" "$r" || exit 3
  st="$work/s30b-state"; mkdir -p "$st"; db="$work/s30b.bd"
  printf 'E2E-st2|open||fleet-safe\n' > "$db"
  mkdir -p "$r-worktrees/st2"
  flock "$r-worktrees/st2/.forge.lock" sleep 60 &
  lockholder=$!; sleep 0.3
  run_loop "$work/s30b-fleet.sh" "$st" "$db" 8; rc=$?; out=$(cat "$st/out.txt")
  kill "$lockholder" 2>/dev/null; wait "$lockholder" 2>/dev/null
  skips=$(printf '%s' "$out" | grep -c 'skip E2E-st2: a live launcher already holds')
  if [ "$rc" -eq 124 ] && [ ! -e "$st/HALT" ] && [ "$skips" -ge 3 ] && ! grep -q '"stalled"' "$r/emitted"; then
    ok "RED: the pre-dx34.9 launcher SPINS on the same wedge -- $skips identical passes in 8s, no halt file, killed only by the timeout -- so scenario 30 can fail"
  else no "the inversion did not reproduce the wedge" "rc=$rc skips=$skips HALT=$([ -e "$st/HALT" ] && echo present || echo absent)
$out"; fi
fi

echo
echo "=========================================================================="
echo "SCENARIO 31 — dx34.9 POSITIVE, second cause. A TRACKER THAT REFUSES EVERY"
echo "              CLAIM (Proofdelve ForgeOs-dx34.2's contention) is the same stall"
echo "=========================================================================="
# The detector is about the SHAPE of a pass and not about any one cause, and
# this is the second cause: dispatchable() says yes, bd refuses the claim,
# nothing changes. On the shipped launcher before this sitting it too spins.
r=$(mkfort s31 ok); mk_launcher "$launcher" "$work/s31-fleet.sh" "$r" || exit 3
st="$work/s31-state"; mkdir -p "$st"; db="$work/s31.bd"
printf 'E2E-zs1|open||fleet-safe\n' > "$db"
E2E_BD_CLAIM=refuse run_loop "$work/s31-fleet.sh" "$st" "$db" 20; rc=$?; out=$(cat "$st/out.txt")
ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
if [ "$rc" -eq 70 ] && [ -e "$st/HALT" ] && grep -q '"stalled":true' <<<"$ended" \
   && printf '%s' "$out" | grep 'stall 1/3' | grep -q 'claim refused'; then
  ok "a tracker refusing every claim halts as STALLED after 3 passes, and the stall lines name the refused claim"
else no "the claim-refused wedge was not detected" "rc=$rc
$out
$ended"; fi

echo
echo "=========================================================================="
echo "SCENARIO 32 — dx34.9 acceptance 4, NEGATIVE. A HEALTHY RUN WITH A LONG"
echo "              QUIET STRETCH IS UNTOUCHED, and the launcher says WHY"
echo "=========================================================================="
# THE HALF THAT MAKES SCENARIO 30 MEAN ANYTHING. Run 20260910T143714 drained
# cleanly with 14.2 minutes of fleet-event silence and one worker event: a Forge
# working, a bead queued behind it, pass after pass dispatching nothing and
# reaping nothing. Replayed here at FLEET_POLL=1: the Forge sleeps 5s, so at
# least four passes go by with a Forge LIVE, nothing to reap, and a startable
# bead the single slot cannot take. A detector that would have halted that run
# is a worse failure than the wedge (the bead's words). The counter must stay
# at zero, and the run must say why it stayed there.
# WITHOUT THE STUB VERIFIER'S B1 INJECTION. mkfort's verify.sh poisons $root
# during every post-merge verification, deliberately, for scenario 1 -- which
# would park the SECOND bead's merge here and turn a healthy run into a parked
# one for a reason that has nothing to do with stalls. Stripped and COMMITTED
# (an uncommitted edit to it would itself dirty the tree and park the merge).
# Deletes the INJECTION line only (the `case "$PWD"` that writes POISON); the
# RED predicate below it stays, so this verifier is still one that CAN fail
# (the Warden, round one, finding 7: the first spelling deleted both).
unpoison() { sed -i '/printf .POISON/d' "$1/fort/scripts/verify.sh"
  grep -q 'grep -q POISON' "$1/fort/scripts/verify.sh" || { echo "HARNESS REFUSES: unpoison removed the RED predicate" >&2; exit 3; }
  ! grep -q 'printf .POISON' "$1/fort/scripts/verify.sh" || { echo "HARNESS REFUSES: unpoison left the injection" >&2; exit 3; }
  git -C "$1" commit -qam 'stub verifier without the B1 injection'; }
r=$(mkfort s32 ok); unpoison "$r"; mk_launcher "$launcher" "$work/s32-fleet.sh" "$r" || exit 3
st="$work/s32-state"; mkdir -p "$st"; db="$work/s32.bd"
printf 'E2E-lg1|open||fleet-safe\nE2E-lg2|open||fleet-safe\n' > "$db"
E2E_FORGE_SLEEP=5 run_loop "$work/s32-fleet.sh" "$st" "$db" 60; rc=$?; out=$(cat "$st/out.txt")
# the quiet stretch, measured from the launcher's own timestamps
t_disp="$(printf '%s' "$out" | grep 'dispatched E2E-lg1' | head -1 | cut -c1-8)"
t_exit="$(printf '%s' "$out" | grep 'E2E-lg1: Forge exited' | head -1 | cut -c1-8)"
gap=-1
if [ -n "$t_disp" ] && [ -n "$t_exit" ]; then
  gap=$(( $(date -d "$t_exit" +%s) - $(date -d "$t_disp" +%s) )); [ "$gap" -lt 0 ] && gap=$((gap + 86400))
fi
if [ "$rc" -eq 0 ] && [ ! -e "$st/HALT" ] && grep -q 'queue drained.*stall counter peak 0/3' <<<"$out" \
   && ! grep -q 'stall 1/' <<<"$out" && [ "$gap" -ge 4 ] \
   && merged_in "$r" lg1 && merged_in "$r" lg2 \
   && [ "$(grep -c '^E2E-lg1|closed' "$db")" -eq 1 ] && [ "$(grep -c '^E2E-lg2|closed' "$db")" -eq 1 ]; then
  ok "acceptance 4: a ${gap}s quiet stretch (>=4 passes with a Forge live and a bead queued) drained cleanly, both beads landed, and the stall counter peaked at 0/3"
else no "the healthy long-gap run was disturbed, or the fixture had no long gap" "rc=$rc gap=${gap}s HALT=$([ -e "$st/HALT" ] && echo present || echo absent)
$out
$(cat "$db")"; fi
# WHY IT STAYED AT ZERO, SAID BY THE LAUNCHER AND NOT BY THIS HARNESS. Two quiet
# stretches (behind lg1 and behind lg2), one sentence each.
waits=$(printf '%s' "$out" | grep -c 'waiting: nothing to reap or dispatch while 1 Forge(s) are live -- a quiet pass with a live worker is not a stall')
if [ "$waits" -ge 2 ]; then
  ok "the launcher says WHY in its own record ($waits times): a quiet pass with a LIVE worker is not a stall, so the counter is not touched"
else no "the launcher does not say why the counter stayed at zero" "$(printf '%s' "$out" | grep -c waiting) waiting lines
$out"; fi

# THE INVERSION THAT MAKES THAT A CONTROL: THE NAIVE PREDICATE, GENERATED. The
# bead's own prose states the predicate WITHOUT the live-worker term ("a healthy
# pass either dispatches, reaps, or finds the queue empty and exits"), and a
# detector built to that sentence must kill this healthy run. Built from the
# shipped file by rewriting the one call so stall_check() is told no Forge is
# live and given the queue's real answer; the drain check itself is left as it
# is, so the only thing that differs is the term under test.
naive="$work/naive-stall.sh"
python3 - "$launcher" "$naive" <<'PYN'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
old = '  stall_check "$live" "$startable"\n'
if t.count(old) != 1:
    sys.exit("expected exactly one stall_check call site, found %d" % t.count(old))
new = ('  if [ "$live" -gt 0 ]; then if any_dispatchable; then startable=yes; else startable=no; fi; fi\n'
       '  stall_check 0 "$startable"   # NAIVE VARIANT: the live-worker term removed\n'
       '  if [ "$live" -gt 0 ]; then startable=unknown; fi\n')
open(dst, "w", encoding="utf-8").write(t.replace(old, new, 1))
PYN
if [ -s "$naive" ]; then
  chmod +x "$naive"
  r2=$(mkfort s32b ok); unpoison "$r2"; mk_launcher "$naive" "$work/s32b-fleet.sh" "$r2" || exit 3
  st2="$work/s32b-state"; mkdir -p "$st2"; db2="$work/s32b.bd"
  printf 'E2E-ng1|open||fleet-safe\nE2E-ng2|open||fleet-safe\n' > "$db2"
  E2E_FORGE_SLEEP=5 run_loop "$work/s32b-fleet.sh" "$st2" "$db2" 60; rc2=$?; out2=$(cat "$st2/out.txt")
  if [ "$rc2" -eq 70 ] && [ -e "$st2/HALT" ] && grep -q '"stalled":true' "$r2/emitted" \
     && grep -q 'stall 3/3' <<<"$out2"; then
    ok "RED: the NAIVE predicate (no live-worker term) HALTS the same healthy run as stalled -- the worse-than-the-wedge failure -- so the control above can fail"
  else no "the naive predicate did not kill the healthy run, so the negative control may be vacuous" "rc=$rc2
$out2"; fi
else
  skip "naive-predicate inversion" "could not generate the naive variant from $launcher"
fi

echo
echo "=========================================================================="
echo "SCENARIO 33 — dx34.9 acceptance 5. THE COUNTER RESETS ON A PASS THAT DOES"
echo "              WORK, executed: two refused claims, then a grant"
echo "=========================================================================="
# N absorbing the transient it exists for: bd refuses the first two claims
# (contention, Proofdelve ForgeOs-dx34.2) and grants the third. The counter must read 1,
# then 2, then reset on the dispatch, and the run must end DRAINED with the bead
# landed -- and the drain line must carry the peak, so a reader of a real run
# can see a transient that was absorbed rather than only one that was not.
r=$(mkfort s33 ok); mk_launcher "$launcher" "$work/s33-fleet.sh" "$r" || exit 3
st="$work/s33-state"; mkdir -p "$st"; db="$work/s33.bd"
printf 'E2E-rs1|open||fleet-safe\n' > "$db"
E2E_BD_CLAIM_REFUSE_N=2 run_loop "$work/s33-fleet.sh" "$st" "$db" 30; rc=$?; out=$(cat "$st/out.txt")
if [ "$rc" -eq 0 ] && [ ! -e "$st/HALT" ] \
   && printf '%s' "$out" | grep 'stall 1/3' | grep -q 'claim refused' \
   && grep -q 'stall 2/3' <<<"$out" && ! grep -q 'stall 3/3' <<<"$out" \
   && grep -q 'stall counter reset from 2: this pass dispatched 1' <<<"$out" \
   && grep -q 'queue drained.*stall counter peak 2/3' <<<"$out" \
   && merged_in "$r" rs1 && [ "$(grep -c '^E2E-rs1|closed' "$db")" -eq 1 ]; then
  ok "acceptance 5: the counter went 1, 2, reset on the third pass's dispatch, and the run drained with the bead landed and 'peak 2/3' in its record"
else no "the reset is not executed as specified" "rc=$rc HALT=$([ -e "$st/HALT" ] && echo present || echo absent)
$out"; fi


echo
echo "=========================================================================="
echo "SCENARIO 34 — Proofdelve ForgeOs-dx34.11, POSITIVE. A MERGE THAT DEFERS FOREVER ON ONE"
echo "              REASON NO LONGER MASKS A REAL STALL"
echo "=========================================================================="
# THE SCENARIO dx34.9's own stall detector could not reach (the Warden's finding 2).
# stall_check only accumulates when startable=yes, so a LONE deferred merge just
# drains -- it is NOT the spin. The spin needs a deferred merge (reapable every
# pass, so the OLD counter reset every pass) COEXISTING with genuinely startable
# work that never starts. Built here as: dfx dispatched, built, reviewed, then
# deferred FOREVER on a persistently dirty root (one unchanging reason); dfy
# ready and dispatchable but its worktree lock held by a foreign process, so
# dispatch_pass skips it every pass and startable stays yes. On the fixed
# launcher the re-deferral on the SAME reason is not counted as a reap, so the
# stall counter finally climbs and the run halts itself and NAMES dfy.
r=$(mkfort s34 ok); mk_launcher "$launcher" "$work/s34-fleet.sh" "$r" || exit 3
st="$work/s34-state"; mkdir -p "$st"; db="$work/s34.bd"
printf 'E2E-dfx|open||fleet-safe\nE2E-dfy|open||fleet-safe\n' > "$db"
echo two >> "$r/subject.txt"          # persistent dirty root: dfx defers on one unchanging reason
mkdir -p "$r-worktrees/dfy"
flock "$r-worktrees/dfy/.forge.lock" sleep 60 &
lockholder=$!; sleep 0.3
run_loop "$work/s34-fleet.sh" "$st" "$db" 25; rc=$?; out=$(cat "$st/out.txt")
kill "$lockholder" 2>/dev/null; wait "$lockholder" 2>/dev/null
ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
defers=$(printf '%s' "$out" | grep -c 'E2E-dfx: NOT MERGED this pass')
if [ "$rc" -eq 70 ] && [ -e "$st/HALT" ] && [ "$defers" -ge 3 ] \
   && grep -q 'stall 3/3' <<<"$out" && grep -q 'reaped nothing' <<<"$out" \
   && grep -q '"stalled":true' <<<"$ended" && ! grep -q '"reason":"drained' <<<"$ended"; then
  ok "a merge deferring forever on ONE reason ($defers times) no longer resets the stall counter -- the run halted itself as stalled, reaping nothing"
else no "the perpetual same-reason deferral did not stop masking the stall" "rc=$rc defers=$defers HALT=$([ -e "$st/HALT" ] && echo present || echo absent)
$out
$ended"; fi
# THE STALL IS ATTRIBUTED TO THE THING ACTUALLY STUCK (dfy), not to the noisy
# deferred merge -- the halt names the locked ready bead, the real cause.
if grep -q 'E2E-dfy: a live launcher already holds' "$st/HALT"; then
  ok "the halt names dfy (the startable-but-unstartable bead) as what the stall was made of, not the loud deferred merge"
else no "the halt does not name the real stalled bead" "$(cat "$st/HALT")"; fi
# dfx keeps its worktree (usz6): the fix must not reap-and-lose the parked merge.
if [ -d "$r-worktrees/dfx" ] && [ "$(grep -c '^E2E-dfx|closed' "$db")" -eq 0 ]; then
  ok "the deferred merge kept its worktree and was never closed -- the stall halt does not strand it"
else no "the deferred merge was lost or closed" "$(cat "$db")"; fi

# THE INVERSION, GENERATED, so it isolates EXACTLY the dx34.11 back-out and always
# runs (never NOT RUN for a missing env file). Strip the back-out block from the
# shipped launcher: the result is byte-identical except that a same-reason
# re-deferral counts as a reap again, which is the pre-fix behaviour. It must
# SPIN on the same fixture -- the counter reset every pass, no halt, killed only
# by the timeout, and NOT ONE 'stall 1/3' line, because the counter never climbs.
prefix="$work/s34-prefix.sh"
python3 - "$launcher" "$prefix" <<'PYX'
import sys, re
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
# remove the dx34.11 back-out: from its comment start through its closing fi
m = re.search(r"\n        # Proofdelve ForgeOs-dx34\.11 shape \(a\)\..*?\n        fi\n", t, re.S)
if not m:
    sys.exit("could not find the dx34.11 back-out block to strip")
t2 = t[:m.start()] + "\n" + t[m.end():]
# GUARD ON THE DECREMENT ITSELF (the Warden, dx34.11 review finding 7). The prior
# spelling checked for "pre_state = deferred-merge", which never appears -- the
# shipped text is `[ "$pre_state" = deferred-merge ]` -- so the `and` made the
# whole assertion unfirable and only the regex's own sys.exit protected the strip.
# The decrement is the thing being removed, so assert IT is gone.
if "pass_reaped=$((pass_reaped - 1))" in t2:
    sys.exit("back-out decrement still present after strip")
open(dst, "w", encoding="utf-8").write(t2)
PYX
if [ -s "$prefix" ]; then
  chmod +x "$prefix"
  r=$(mkfort s34b ok); mk_launcher "$prefix" "$work/s34b-fleet.sh" "$r" || exit 3
  st="$work/s34b-state"; mkdir -p "$st"; db="$work/s34b.bd"
  printf 'E2E-dgx|open||fleet-safe\nE2E-dgy|open||fleet-safe\n' > "$db"
  echo two >> "$r/subject.txt"
  mkdir -p "$r-worktrees/dgy"
  flock "$r-worktrees/dgy/.forge.lock" sleep 60 &
  lockholder=$!; sleep 0.3
  run_loop "$work/s34b-fleet.sh" "$st" "$db" 10; rc=$?; out=$(cat "$st/out.txt")
  kill "$lockholder" 2>/dev/null; wait "$lockholder" 2>/dev/null
  defers=$(printf '%s' "$out" | grep -c 'E2E-dgx: NOT MERGED this pass')
  if [ "$rc" -eq 124 ] && [ ! -e "$st/HALT" ] && [ "$defers" -ge 3 ] \
     && ! grep -q 'stall 1/3' <<<"$out" && ! grep -q '"stalled":true' "$r/emitted"; then
    ok "RED: strip the back-out and the same fixture SPINS -- $defers same-reason deferrals, no 'stall 1/3', no halt, killed by the timeout -- so scenario 34 can fail"
  else no "the inversion did not reproduce the pre-fix spin" "rc=$rc defers=$defers HALT=$([ -e "$st/HALT" ] && echo present || echo absent)
$out"; fi
else
  skip "dx34.11 inversion" "could not generate the back-out-stripped variant"
fi


echo
echo "=========================================================================="
echo "SCENARIO 36 — Proofdelve ForgeOs-dx34.12 finding 4. --dry-run WITHOUT --once EXITS"
echo "              AFTER ONE PASS instead of spinning forever"
echo "=========================================================================="
# --dry-run counts a pass as dispatched but claims nothing, so any_dispatchable()
# stays true forever: before this sitting a dry loop with no --once polled with no
# way to stop it but by hand. A dry run decides everything and acts on nothing,
# which is a report, and a report is one pass.
r=$(mkfort s36 ok); mk_launcher "$launcher" "$work/s36-fleet.sh" "$r" || exit 3
st="$work/s36-state"; mkdir -p "$st"; db="$work/s36.bd"
printf 'E2E-aaa|open||fleet-safe\n' > "$db"    # a genuinely dispatchable bead
FLEET_STATE="$st" BD_STORE="$db" timeout 30 "$work/s36-fleet.sh" --dry-run > "$st/out.txt" 2>&1; rc=$?
out=$(cat "$st/out.txt"); ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
begun="$(grep 'fleet.begun' "$r/emitted" | tail -1)"
if [ "$rc" -eq 0 ] && grep -q 'DRY-RUN would dispatch' <<<"$out" \
   && grep -q '"dry_run":true' <<<"$begun" \
   && grep -q '"reason":"dry run' <<<"$ended"; then
  ok "--dry-run alone exits after one pass (rc 0), the begun payload carries dry_run:true, and the end reason names the dry run"
else no "--dry-run alone did not exit after one pass" "rc=$rc
$out
begun=$begun
ended=$ended"; fi
# claimed/launched/landed nothing
if [ "$(grep -c '^E2E-aaa|open||fleet-safe' "$db")" -eq 1 ] && ! merged_in "$r" aaa; then
  ok "the dry run claimed, launched and landed nothing"
else no "the dry run mutated state" "$(cat "$db")"; fi
# --dry-run --once behaves identically (one pass, rc 0)
r=$(mkfort s36c ok); mk_launcher "$launcher" "$work/s36c-fleet.sh" "$r" || exit 3
st="$work/s36c-state"; mkdir -p "$st"; db="$work/s36c.bd"; printf 'E2E-aaa|open||fleet-safe\n' > "$db"
FLEET_STATE="$st" BD_STORE="$db" timeout 30 "$work/s36c-fleet.sh" --dry-run --once > "$st/out.txt" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'DRY-RUN would dispatch' "$st/out.txt"; then
  ok "--dry-run --once behaves identically (rc 0, one pass)"
else no "--dry-run --once diverged from --dry-run" "rc=$rc
$(cat "$st/out.txt")"; fi
# THE INVERSION, GENERATED: strip the --dry-run break, and a dry loop must SPIN.
prefix="$work/s36-prefix.sh"
python3 - "$launcher" "$prefix" <<'PYX'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
line = '  if [ "$dry" = 1 ]; then set_end_reason "dry run: one pass, nothing claimed, launched or landed"; break; fi\n'
if t.count(line) != 1:
    sys.exit("expected exactly one --dry-run break, found %d" % t.count(line))
open(dst, "w", encoding="utf-8").write(t.replace(line, "", 1))
PYX
if [ -s "$prefix" ]; then
  chmod +x "$prefix"
  r=$(mkfort s36b ok); mk_launcher "$prefix" "$work/s36b-fleet.sh" "$r" || exit 3
  st="$work/s36b-state"; mkdir -p "$st"; db="$work/s36b.bd"; printf 'E2E-aaa|open||fleet-safe\n' > "$db"
  FLEET_STATE="$st" BD_STORE="$db" timeout 15 "$work/s36b-fleet.sh" --dry-run > "$st/out.txt" 2>&1; rc=$?
  passes=$(grep -c 'DRY-RUN would dispatch' "$st/out.txt")
  if [ "$rc" -eq 124 ] && [ "$passes" -ge 3 ]; then
    ok "RED: strip the --dry-run break and a dry loop SPINS -- $passes dry passes, killed only by the timeout (rc 124) -- so scenario 36 can fail"
  else no "the inversion did not reproduce the dry-run spin" "rc=$rc passes=$passes
$(cat "$st/out.txt")"; fi
else
  skip "dx34.12 dry-run inversion" "could not generate the no-break variant"
fi

echo
echo "=========================================================================="
echo "SCENARIO 37 — Proofdelve ForgeOs-6843, third sighting. AN UNEXPECTED DEATH IS LEGIBLE"
echo "              AS UNDETERMINED, NOT RECORDED AS A CLEAN DRAIN"
echo "=========================================================================="
# The drain vocabulary is unchanged (criterion 2): a real drain still says drained.
r=$(mkfort s37 ok); mk_launcher "$launcher" "$work/s37-fleet.sh" "$r" || exit 3
st="$work/s37-state"; mkdir -p "$st"; db="$work/s37.bd"; : > "$db"   # empty queue -> immediate drain
# NOT --once: --once breaks with "one pass complete" before the drain check. A
# real drain is a continuous run finding nothing startable; on an empty queue it
# drains on the first pass.
run_loop "$work/s37-fleet.sh" "$st" "$db" 10 >/dev/null 2>&1
ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
if grep -q '"reason":"drained"' <<<"$ended"; then
  ok "GREEN: a genuine drain still records reason \"drained\" -- the vocabulary is unchanged for the path that already set it"
else no "a real drain no longer says drained" "$ended"; fi
# AN UNDETERMINED DEATH: inject a failing command into the loop body so set -e
# aborts on a path nobody anticipated, reaching the EXIT trap with no reason set.
mkdie() { # $1 src, $2 dst
  python3 - "$1" "$2" <<'PYD'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
# ANCHORED ON THE LINE'S HEAD, NOT ITS WHOLE SPELLING: the reset line grew a
# counter in b9mj round three and an exact-match anchor refused the whole
# harness (rc 3) for a correct change -- the 41c generator's class.
import re
m = re.search(r'^  pass_dispatched=0; pass_reaped=0; pass_note=""[^\n]*\n', t, re.M)
if not m or len(re.findall(r'^  pass_dispatched=0; pass_reaped=0; pass_note=""', t, re.M)) != 1:
    sys.exit("expected one loop-top reset line")
open(dst, "w", encoding="utf-8").write(t[:m.end()] + '  e2e_unhandled_death_xyz   # injected: an unanticipated failure under set -e\n' + t[m.end():])
PYD
}
die="$work/s37-die.sh"; mkdie "$launcher" "$die"; chmod +x "$die"
r=$(mkfort s37b ok); mk_launcher "$die" "$work/s37b-fleet.sh" "$r" || exit 3
st="$work/s37b-state"; mkdir -p "$st"; db="$work/s37b.bd"; printf 'E2E-aaa|open||fleet-safe\n' > "$db"
FLEET_STATE="$st" BD_STORE="$db" timeout 15 "$work/s37b-fleet.sh" >/dev/null 2>&1; rc=$?
ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
if [ "$rc" -ne 0 ] && grep -q 'without a recorded reason' <<<"$ended" \
   && ! grep -q '"reason":"drained"' <<<"$ended"; then
  ok "REFUSE: an unhandled death (set -e abort) is recorded as an undetermined end, NOT as a clean drain"
else no "an unexpected death did not record as undetermined" "rc=$rc
$ended"; fi
# THE INVERSION, GENERATED: the SAME injected death on a variant whose default is
# still \"drained\" (item 2's pre-fix) records a CLEAN DRAIN for a crash -- the bug.
prefix="$work/s37-prefix.sh"
python3 - "$die" "$prefix" <<'PYX'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
new = 'end_reason="ended without a recorded reason (see the run\'s narrative log)"'
if t.count(new) != 1:
    sys.exit("expected one undetermined default, found %d" % t.count(new))
open(dst, "w", encoding="utf-8").write(t.replace(new, 'end_reason="drained"', 1))
PYX
if [ -s "$prefix" ]; then
  chmod +x "$prefix"
  r=$(mkfort s37c ok); mk_launcher "$prefix" "$work/s37c-fleet.sh" "$r" || exit 3
  st="$work/s37c-state"; mkdir -p "$st"; db="$work/s37c.bd"; printf 'E2E-aaa|open||fleet-safe\n' > "$db"
  FLEET_STATE="$st" BD_STORE="$db" timeout 15 "$work/s37c-fleet.sh" >/dev/null 2>&1; rc=$?
  ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
  if grep -q '"reason":"drained"' <<<"$ended"; then
    ok "RED: with the pre-fix default (\"drained\"), the identical unhandled death records a CLEAN DRAIN -- the Proofdelve ForgeOs-6843 bug reproduced -- so scenario 37 can fail"
  else no "the pre-fix default did not reproduce the clean-drain-on-crash bug" "rc=$rc
$ended"; fi
else
  skip "6843 default inversion" "could not generate the drained-default variant"
fi

echo
echo "=========================================================================="
echo "SCENARIO 38 — Proofdelve ForgeOs-g3n1 (incident Proofdelve ForgeOs-7gag). A REVIEW THAT DIES OF"
echo "              A FULL DISK HALTS THE RUN; IT DOES NOT SPEND THE LADDER AND PAGE"
echo "=========================================================================="
# THE 7gag SHAPE ON THE REVIEW PATH: the Warden on b0vj.70 died mid-record with
# 'write error: Disk quota exceeded', no result file appeared, and review_one
# read the absent result as an availability failure -- spent the rung, spent the
# ladder, paged the Overseer over a review nobody could have finished. With one
# rung in this fixture's ladder the pre-fix path pages on the first miss.
r=$(mkfort s38 ok); unpoison "$r"; mk_launcher "$launcher" "$work/s38-fleet.sh" "$r" || exit 3
st="$work/s38-state"; mkdir -p "$st"; db="$work/s38.bd"
printf 'E2E-en1|open||fleet-safe\n' > "$db"
run_pass "$work/s38-fleet.sh" "$st" "$db" || true
wait_forge "$st" en1
E2E_WARDEN_RESULT=envfail run_pass "$work/s38-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
if [ "$rc" -eq 70 ] && [ -e "$st/HALT" ] && grep -q 'ENVIRONMENTAL FAILURE' <<<"$out" \
   && grep -q '"reason":"halted: ENVIRONMENTAL FAILURE' <<<"$ended" \
   && [ "$(wstate "$st/workers/en1")" = parked-review ] \
   && ! grep -q 'fleet.escalated\|PAGING\|paged' "$st/out.txt" && ! grep -q 'incident.*ladder' "$r/emitted"; then
  ok "g3n1: a review log naming the host HALTS (exit 70, HALT file, reason 'halted: ENVIRONMENTAL FAILURE'), the worker is parked-review, nobody is paged"
else no "g3n1: review-path environmental halt" "rc=$rc HALT=$([ -e "$st/HALT" ] && echo present || echo absent) state=$(wstate "$st/workers/en1")
$ended
$(printf '%s' "$out" | tail -12)"; fi
# THE VACUITY CONTROL: a review that simply dies (no host line) still takes the
# ladder as before -- one rung here, so it pages -- and does NOT halt.
r=$(mkfort s38b ok); unpoison "$r"; mk_launcher "$launcher" "$work/s38b-fleet.sh" "$r" || exit 3
st="$work/s38b-state"; mkdir -p "$st"; db="$work/s38b.bd"
printf 'E2E-en2|open||fleet-safe\n' > "$db"
run_pass "$work/s38b-fleet.sh" "$st" "$db" || true
wait_forge "$st" en2
E2E_WARDEN_RESULT=none run_pass "$work/s38b-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if [ ! -e "$st/HALT" ] && grep -q 'PAGED the Overseer' <<<"$out" && [ "$(wstate "$st/workers/en2")" = needs-person ]; then
  ok "g3n1 control: a review that dies with NO host line still walks the ladder and hands the bead to a person -- the halt is not unconditional"
else no "g3n1 control: plain dead review" "HALT=$([ -e "$st/HALT" ] && echo present || echo absent) state=$(wstate "$st/workers/en2")
$(printf '%s' "$out" | tail -8)"; fi
# THE SCOPE CONTROL (g3n1 round one, blocking finding): a review that COMPLETED and
# recorded a verdict, whose prose mentions the signature, LANDS -- it is not asked.
r=$(mkfort s38d ok); unpoison "$r"; mk_launcher "$launcher" "$work/s38d-fleet.sh" "$r" || exit 3
st="$work/s38d-state"; mkdir -p "$st"; db="$work/s38d.bd"
printf 'E2E-en4|open||fleet-safe\n' > "$db"
run_pass "$work/s38d-fleet.sh" "$st" "$db" || true
wait_forge "$st" en4
E2E_WARDEN_RESULT=mentions run_pass "$work/s38d-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if [ ! -e "$st/HALT" ] && [ "$(wstate "$st/workers/en4")" = settled ] && grep -q 'E2E-en4: merged to main' <<<"$out"; then
  ok "g3n1 scope: a COMPLETED review whose prose mentions the host signature is landed, not halted -- the check is asked only of a review that produced no result"
else no "g3n1 scope: completed review mentioning the signature" "HALT=$([ -e "$st/HALT" ] && echo present || echo absent) state=$(wstate "$st/workers/en4")
$(printf '%s' "$out" | tail -8)"; fi
# THE INVERSION, GENERATED: strip review_one's environmental block from the
# shipped file and the same fixture walks the ladder and pages -- 7gag verbatim.
pre="$work/s38-pre.sh"
python3 - "$launcher" "$pre" <<'PYE'
import sys, re
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
m = re.search(r"\n    # A BROKEN HOST IS CHECKED BEFORE THE GOVERNOR AND BEFORE THE LADDER\n.*?\n    fi\n(?=    looks_rate_limited \"\$wlog\")", t, re.S)  # the block ends at its own `fi`, whatever its inner lines
if not m:
    sys.exit("could not find review_one's environmental block to strip")
t2 = t[:m.start()] + "\n" + t[m.end():]
if 'env_halt_if "$wlog"' in t2:
    sys.exit("the review-path env_halt_if call survived the strip")
open(dst, "w", encoding="utf-8").write(t2)
PYE
if [ -s "$pre" ]; then
  chmod +x "$pre"
  r=$(mkfort s38c ok); unpoison "$r"; mk_launcher "$pre" "$work/s38c-fleet.sh" "$r" || exit 3
  st="$work/s38c-state"; mkdir -p "$st"; db="$work/s38c.bd"
  printf 'E2E-en3|open||fleet-safe\n' > "$db"
  run_pass "$work/s38c-fleet.sh" "$st" "$db" || true
  wait_forge "$st" en3
  E2E_WARDEN_RESULT=envfail run_pass "$work/s38c-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
  if [ ! -e "$st/HALT" ] && grep -q 'PAGED the Overseer' <<<"$out" && [ "$(wstate "$st/workers/en3")" = needs-person ]; then
    ok "RED: without the review-path check the SAME full-disk review spends the ladder and hands the bead to a person (7gag on b0vj.70) -- so scenario 38 can fail"
  else no "the inversion did not reproduce 7gag's review-path shape" "rc=$rc HALT=$([ -e "$st/HALT" ] && echo present || echo absent) state=$(wstate "$st/workers/en3")
$(printf '%s' "$out" | tail -8)"; fi
else
  skip "g3n1 review-path inversion" "could not generate the stripped variant"
fi

echo
echo "=========================================================================="
echo "SCENARIO 39 — Proofdelve ForgeOs-dx34.18. A WORKER THAT FINISHES INSIDE ANOTHER BEAD'S"
echo "              REAP PASS IS REAPED, NOT STRANDED BY THE DRAIN CHECK"
echo "=========================================================================="
# THE 15k.6 SHAPE, BUILT. Two ready beads at Forge concurrency 2. Pass 1
# dispatches both: rd1's stub Forge is instant, rc1's sleeps 2s. Pass 2's reap
# loop walks the worker directories in NAME ORDER: rc1 first (still running --
# skipped), then rd1 -- verifier, a 3s review (E2E_WARDEN_SLEEP), merge -- and
# rc1's Forge finishes INSIDE that reap, after the loop has passed it. At the
# foot of pass 2 rc1 is FINISHED: not live, not startable. That ordering is the
# real one: 15k.6 sorted before b0vj.53. Pre-fix: "queue drained" with rc1
# finished and unreaped (run log :91 of 20260911T222003). Post-fix: the foot
# sees one reapable worker, says so once, and pass 3 takes rc1 -- the assertion
# is that it was TAKEN (its verifier ran; it did not end the run as finished),
# not how its own merge went (since Proofdelve ForgeOs-36b9 the second is refreshed from
# main before its verifier and lands cleanly; before it, both beads wrote one
# marker file and the second was returned at the merge). Two earlier drafts of this fixture measured
# nothing: one pre-built the finished worker and dispatched the other in the
# same pass (still LIVE at the foot); one named the straggler so it sorted AFTER
# the slow bead, and the reap loop's own walk picked it up.
r=$(mkfort s39 ok); unpoison "$r"
sed -i 's/^FLEET_FORGE_START=1$/FLEET_FORGE_START=2/' "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "conc 2"
mk_launcher "$launcher" "$work/s39-fleet.sh" "$r" || exit 3
st="$work/s39-state"; mkdir -p "$st"; db="$work/s39.bd"
printf 'E2E-rc1|open||fleet-safe||src/a/\nE2E-rd1|open||fleet-safe||src/b/\n' > "$db"   # disjoint Touches: both must be live at once (Proofdelve ForgeOs-b9mj; the guard is scenario 42's subject)
E2E_FORGE_SLOW_BEAD=E2E-rc1 E2E_FORGE_SLOW_SLEEP=2 E2E_WARDEN_SLEEP=3 run_loop "$work/s39-fleet.sh" "$st" "$db" 60; rc=$?; out=$(cat "$st/out.txt")
ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
# SINCE Proofdelve ForgeOs-4bzvk (Regent sitting 2026-10-23) reap_pass re-asks the order
# after every worker, so rc1 -- finished inside rd1's reap -- is taken in that
# SAME pass, and the foot of the pass finds nothing reapable: the drain term
# below never has to speak. What this fixture asserts on the shipped launcher
# is therefore the stronger property: rc1 is taken, never stranded.
if [ "$rc" -eq 0 ] && grep -q '"reason":"drained"' <<<"$ended" \
   && [ "$(wstate "$st/workers/rc1")" != finished ] && [ "$(wstate "$st/workers/rd1")" = settled ] \
   && grep -q 'E2E-rc1: running the host verifier' <<<"$out" \
   && ! grep -q 'E2E-rc1: FINISHED, NOT YET REAPED' <<<"$out"; then
  ok "dx34.18 + 4bzvk: the Forge that finished inside rd1's reap (rc1) was TAKEN -- its verifier ran, it did not end the run as FINISHED, NOT YET REAPED, and the run drained"
else no "dx34.18: finished-worker strand" "rc=$rc rd1=$(wstate "$st/workers/rd1") rc1=$(wstate "$st/workers/rc1")
$ended
$(printf '%s' "$out" | tail -14)"; fi
# THE DRAIN TERM ITSELF, on a launcher that walks a snapshot again (4bzvk's
# re-ask taken out, the governor harness's RED 6 construction): there rc1 is
# NOT in pass 2's order, so only the foot's reapable term keeps the run alive
# for pass 3. This is dx34.18's original assertion, kept where it can still be
# reached.
snap="$work/s39-snap.sh"
# shellcheck disable=SC2016  # sed PATTERNS: the $ names the launcher's own text, literally
sed -e '/^  local d c sfx bead wt vout resume frc taken=" "$/a\  local snap; snap="$(reap_order)"' \
    -e 's|^    for c in \$(reap_order); do$|    for c in $snap; do|' "$launcher" > "$snap"
# shellcheck disable=SC2016  # a grep PATTERN naming the variant's own text, literally
if ! cmp -s "$snap" "$launcher" && grep -q '^    for c in \$snap; do$' "$snap"; then
  chmod +x "$snap"
  r=$(mkfort s39s ok); unpoison "$r"
  sed -i 's/^FLEET_FORGE_START=1$/FLEET_FORGE_START=2/' "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "conc 2"
  mk_launcher "$snap" "$work/s39s-fleet.sh" "$r" || exit 3
  st="$work/s39s-state"; mkdir -p "$st"; db="$work/s39s.bd"
  printf 'E2E-rc1|open||fleet-safe||src/a/\nE2E-rd1|open||fleet-safe||src/b/\n' > "$db"
  E2E_FORGE_SLOW_BEAD=E2E-rc1 E2E_FORGE_SLOW_SLEEP=2 E2E_WARDEN_SLEEP=3 run_loop "$work/s39s-fleet.sh" "$st" "$db" 60; rc=$?; out=$(cat "$st/out.txt")
  ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
  if [ "$rc" -eq 0 ] && grep -q '"reason":"drained"' <<<"$ended" \
     && [ "$(wstate "$st/workers/rc1")" != finished ] && [ "$(wstate "$st/workers/rd1")" = settled ] \
     && grep -q 'not draining: nothing is startable, but 1 worker(s) are reapable' <<<"$out" \
     && grep -q 'E2E-rc1: running the host verifier' <<<"$out" \
     && ! grep -q 'E2E-rc1: FINISHED, NOT YET REAPED' <<<"$out"; then
    ok "dx34.18 (snapshot launcher): rc1, absent from pass 2's order, was TAKEN by the next pass -- 'not draining' said once, its verifier ran, never FINISHED, NOT YET REAPED"
  else no "dx34.18 (snapshot launcher): finished-worker strand" "rc=$rc rd1=$(wstate "$st/workers/rd1") rc1=$(wstate "$st/workers/rc1")
$ended
$(printf '%s' "$out" | tail -14)"; fi
else
  skip "dx34.18 drain term on a snapshot launcher" "could not generate the snapshot variant (the 4bzvk loop lines moved)"
fi
# MUST NOT CHANGE: no workers and no ready beads still drains on the first quiet pass (scenario 37 asserts it too); the leftovers line is unchanged in wording
# THE INVERSION, GENERATED: put the pre-dx34.18 drain back (no reapable term) and
# the same fixture drains with rd2 FINISHED, NOT YET REAPED -- the 15k.6 strand.
pre="$work/s39-pre.sh"
python3 - "$snap" "$pre" <<'PYR'
import sys, re
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
m = re.search(r'    reapable="\$\(reapable_workers\)"\n    if \[ "\$reapable" -gt 0 \]; then\n.*?\n    else\n(      set_end_reason "drained".*?\n      say "queue drained.*?\n      break\n)    fi\n', t, re.S)
if not m:
    sys.exit("could not find the dx34.18 drain block")
old_drain = "".join(l[2:] + "\n" for l in m.group(1).rstrip("\n").split("\n"))   # dedent the pre-fix three lines
t2 = t[:m.start()] + old_drain + t[m.end():]
if "reapable_workers)" in t2.split("stall_check \"$live\" \"$startable\"")[1][:2000]:
    sys.exit("the reapable term survived the strip")
open(dst, "w", encoding="utf-8").write(t2)
PYR
if [ -s "$pre" ]; then
  chmod +x "$pre"
  r=$(mkfort s39b ok); unpoison "$r"
  sed -i 's/^FLEET_FORGE_START=1$/FLEET_FORGE_START=2/' "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "conc 2"
  mk_launcher "$pre" "$work/s39b-fleet.sh" "$r" || exit 3
  st="$work/s39b-state"; mkdir -p "$st"; db="$work/s39b.bd"
  printf 'E2E-rc1|open||fleet-safe||src/a/\nE2E-rd1|open||fleet-safe||src/b/\n' > "$db"   # disjoint Touches: both must be live at once (Proofdelve ForgeOs-b9mj; the guard is scenario 42's subject)
  E2E_FORGE_SLOW_BEAD=E2E-rc1 E2E_FORGE_SLOW_SLEEP=2 E2E_WARDEN_SLEEP=3 run_loop "$work/s39b-fleet.sh" "$st" "$db" 60; rc=$?; out=$(cat "$st/out.txt")
  ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
  # a never-taken worker has no state file (its 'finished' is derived from its exit file), so assert on that and the leftovers line
  if grep -q '"reason":"drained"' <<<"$ended" && [ -e "$st/workers/rc1/exit" ] && [ ! -e "$st/workers/rc1/state" ] \
     && grep -q 'E2E-rc1: FINISHED, NOT YET REAPED' <<<"$out"; then
    ok "RED: without the reapable term the SAME fixture drains with rc1 FINISHED, NOT YET REAPED -- the 15k.6 strand reproduced -- so scenario 39 can fail"
  else no "the inversion did not reproduce the strand" "rc=$rc rc1=$(wstate "$st/workers/rc1")
$ended
$(printf '%s' "$out" | tail -8)"; fi
else
  skip "dx34.18 drain inversion" "could not generate the pre-fix drain variant"
fi

echo
echo "=========================================================================="
echo "SCENARIO 40 — Proofdelve ForgeOs-dx34.18 step 2. A DEFERRED MERGE KEEPS THE RUN ALIVE"
echo "              (VISIBLY) INSTEAD OF DRAINING AND STRANDING IT"
echo "=========================================================================="
# A worker parked at the merge on a persistently dirty root. Pre-fix the run
# drained on the first quiet pass and the merge waited for somebody to label an
# unrelated bead. Post-fix the run stays up, retries the merge each pass, says
# 'not draining' once, and names the parked merge every pass; the timeout is
# what ends it here, and rc=124 is the assertion that it was still alive.
r=$(mkfort s40 ok); mk_launcher "$launcher" "$work/s40-fleet.sh" "$r" || exit 3
st="$work/s40-state"; mkdir -p "$st"; db="$work/s40.bd"
printf 'E2E-rd3|open||fleet-safe\n' > "$db"
echo two >> "$r/subject.txt"                    # uncommitted tracked source: the merge parks
run_pass "$work/s40-fleet.sh" "$st" "$db" || true
wait_forge "$st" rd3
run_pass "$work/s40-fleet.sh" "$st" "$db" || true      # verify, review, park at the merge
if [ "$(wstate "$st/workers/rd3")" = deferred-merge ]; then
  run_loop "$work/s40-fleet.sh" "$st" "$db" 6; rc=$?; out=$(cat "$st/out.txt")
  if [ "$rc" -eq 124 ] && grep -q 'not draining: nothing is startable, but 1 worker(s) are reapable' <<<"$out" \
     && [ "$(printf '%s' "$out" | grep -c 'E2E-rd3: NOT MERGED this pass')" -ge 2 ] \
     && grep 'fleet.ended' "$r/emitted" | tail -1 | grep -q '"reason":"interrupted by SIGTERM"'; then
    ok "dx34.18 step 2: a lone deferred merge keeps the run alive until the 6s timeout's SIGTERM (rc 124, fleet.ended 'interrupted by SIGTERM', never 'drained'), retried each pass, 'not draining' said once"
  else no "dx34.18 step 2: deferred merge" "rc=$rc state=$(wstate "$st/workers/rd3")
$(printf '%s' "$out" | tail -10)"; fi
  # and once the tree is landable the run LANDS it and drains -- the wait was for something
  git -C "$r" checkout -- subject.txt
  run_loop "$work/s40-fleet.sh" "$st" "$db" 20; rc=$?; out=$(cat "$st/out.txt")
  ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
  if [ "$rc" -eq 0 ] && grep -q '"reason":"drained"' <<<"$ended" && [ "$(wstate "$st/workers/rd3")" = settled ]; then
    ok "dx34.18 step 2: with the tree landable the parked merge LANDS, the worker settles, and the run drains"
  else no "dx34.18 step 2: landing after the wait" "rc=$rc state=$(wstate "$st/workers/rd3")
$ended"; fi
  if [ -s "$pre" ]; then
    # RED: the pre-fix drain ends the run at once with the merge still parked
    r2=$(mkfort s40b ok); mk_launcher "$pre" "$work/s40b-fleet.sh" "$r2" || exit 3
    st2="$work/s40b-state"; mkdir -p "$st2"; db2="$work/s40b.bd"
    printf 'E2E-rd4|open||fleet-safe\n' > "$db2"
    echo two >> "$r2/subject.txt"
    run_pass "$work/s40b-fleet.sh" "$st2" "$db2" || true; wait_forge "$st2" rd4
    run_pass "$work/s40b-fleet.sh" "$st2" "$db2" || true
    run_loop "$work/s40b-fleet.sh" "$st2" "$db2" 6; rc=$?
    ended="$(grep 'fleet.ended' "$r2/emitted" | tail -1)"
    if [ "$rc" -eq 0 ] && grep -q '"reason":"drained"' <<<"$ended" && [ "$(wstate "$st2/workers/rd4")" = deferred-merge ]; then
      ok "RED: the pre-fix drain ends the run 'drained' with the merge still parked (deferred-merge) -- so scenario 40 can fail"
    else no "the deferred-merge inversion did not reproduce" "rc=$rc state=$(wstate "$st2/workers/rd4")
$ended"; fi
  fi
else
  no "dx34.18 step 2: fixture" "the merge did not park; state=$(wstate "$st/workers/rd3")"
fi

echo
echo "=========================================================================="
echo "SCENARIO 41 — Proofdelve ForgeOs-hifw. THE REVIEW RANGE IS THREE-DOT: A SIBLING BEAD THAT"
echo "              LANDED FIRST DOES NOT RENDER AS DELETIONS IN THE WARDEN'S DIFF"
echo "=========================================================================="
# Two beads cut from ONE base in one pass (Forge concurrency 2), then reaped in
# one pass: hf1 lands first and moves main; hf2's review is then handed a range.
# Two-dot (main..bead/hf2, the pre-fix spelling) compares the TIPS, so hf1's
# landed files show as `D` in hf2's diff -- qjfb f1 / 02ku f6 / glvm f8 on
# 2026-09-12. Three-dot diffs from the merge base and shows hf2's own work only.
r=$(mkfort s41 ok); unpoison "$r"
sed -i 's/^FLEET_FORGE_START=1$/FLEET_FORGE_START=2/' "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "conc 2"
mk_launcher "$launcher" "$work/s41-fleet.sh" "$r" || exit 3
st="$work/s41-state"; mkdir -p "$st"; db="$work/s41.bd"
printf 'E2E-hf1|open||fleet-safe||src/a/\nE2E-hf2|open||fleet-safe||src/b/\n' > "$db"   # disjoint Touches: both must be live at once (Proofdelve ForgeOs-b9mj)
run_pass "$work/s41-fleet.sh" "$st" "$db" || true          # dispatches BOTH from one base
wait_forge "$st" hf1; wait_forge "$st" hf2
run_pass "$work/s41-fleet.sh" "$st" "$db" || true          # reaps hf1 (lands), then hf2 (reviewed against a moved main)
range2="$(awk '$1=="E2E-hf2"{print $2}' "$r/warden-ranges" | tail -1)"
dels="$(grep -c '^D' "$r/warden-diff-hf2" 2>/dev/null || true)"
if [ -n "$range2" ] && case "$range2" in *...*) true ;; *) false ;; esac && [ "$dels" = 0 ] \
   && grep -q 'marker-hf2.txt' "$r/warden-diff-hf2" \
   && [ "$(wstate "$st/workers/hf1")" = settled ]; then
  ok "hifw: hf2 was reviewed against '$range2' (three-dot) after hf1 landed: 0 deletions in the diff the reviewer saw, and its own marker change shows"
else no "hifw: three-dot range" "range='$range2' deletions=$dels hf1=$(wstate "$st/workers/hf1") hf2=$(wstate "$st/workers/hf2")
$(head -5 "$r/warden-diff-hf2" 2>&1)"; fi
# STEP 2: a branch that DELETES a file still shows its deletion under three dots.
r=$(mkfort s41b ok); unpoison "$r"; mk_launcher "$launcher" "$work/s41b-fleet.sh" "$r" || exit 3
st="$work/s41b-state"; mkdir -p "$st"; db="$work/s41b.bd"
printf 'E2E-hf3|open||fleet-safe\n' > "$db"
run_pass "$work/s41b-fleet.sh" "$st" "$db" || true; wait_forge "$st" hf3
git -C "$r-worktrees/hf3" rm -q subject.txt && git -C "$r-worktrees/hf3" -c user.email=h@h -c user.name=h commit -qm "hf3 deletes subject.txt"
run_pass "$work/s41b-fleet.sh" "$st" "$db" || true
range3="$(awk '$1=="E2E-hf3"{print $2}' "$r/warden-ranges" | tail -1)"
if [ -n "$range3" ] && grep -q '^D.*subject.txt' "$r/warden-diff-hf3" 2>/dev/null; then
  ok "hifw step 2: a branch's OWN deletion still shows as D in the diff the reviewer saw under the three-dot range ('$range3')"
else no "hifw step 2: own deletion" "range='$range3'
$(head -5 "$r/warden-diff-hf3" 2>&1)"; fi
# THE INVERSION, GENERATED: put the two-dot spelling back at the one call site and
# the SAME two-bead fixture shows hf1's landed file as a deletion in hf2's diff.
pre="$work/s41-pre.sh"
python3 - "$launcher" "$pre" <<'PYH'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
old = '"$main_branch...bead/$sfx"'
if t.count(old) != 1:
    sys.exit("expected exactly one three-dot review range, found %d" % t.count(old))
t = t.replace(old, '"$main_branch' + '..' + 'bead/$sfx"', 1)
# AND WITHOUT Proofdelve ForgeOs-36b9's refresh: once the branch contains main, the two
# spellings agree (that is the docket's own point (b)), so the pre-hifw shape
# is two-dot AND no refresh. On a launcher without the function this is a no-op.
import re
m = re.search(r'^prelanding_refresh\(\)[ \t]*\{[^\n]*\n', t, re.M)
if m:
    t = t[:m.end()] + '  prelanding_result=current; return 0   # 41c variant: no refresh\n' + t[m.end():]
open(dst, "w", encoding="utf-8").write(t)
PYH
if [ -s "$pre" ]; then
  chmod +x "$pre"
  r=$(mkfort s41c ok); unpoison "$r"
  sed -i 's/^FLEET_FORGE_START=1$/FLEET_FORGE_START=2/' "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "conc 2"
  mk_launcher "$pre" "$work/s41c-fleet.sh" "$r" || exit 3
  st="$work/s41c-state"; mkdir -p "$st"; db="$work/s41c.bd"
  printf 'E2E-hf4|open||fleet-safe||src/a/\nE2E-hf5|open||fleet-safe||src/b/\n' > "$db"   # disjoint Touches (Proofdelve ForgeOs-b9mj)
  run_pass "$work/s41c-fleet.sh" "$st" "$db" || true; wait_forge "$st" hf4; wait_forge "$st" hf5
  run_pass "$work/s41c-fleet.sh" "$st" "$db" || true
  range5="$(awk '$1=="E2E-hf5"{print $2}' "$r/warden-ranges" | tail -1)"
  dels="$(grep -c '^D' "$r/warden-diff-hf5" 2>/dev/null || true)"
  if [ -n "$range5" ] && [ "$dels" -ge 1 ]; then
    ok "RED: with the two-dot spelling the same fixture shows $dels deletion(s) of the landed sibling's files in hf5's review diff ('$range5') -- hifw reproduced -- so scenario 41 can fail"
  else no "the two-dot inversion did not reproduce hifw" "range='$range5' deletions=$dels hf4=$(wstate "$st/workers/hf4") hf5=$(wstate "$st/workers/hf5")
$(cat "$r/warden-diff-hf5" 2>&1 | head -5)
$(grep -E 'hf4|hf5' "$st/out.txt" | tail -12)"; fi
else
  skip "hifw two-dot inversion" "could not generate the two-dot variant"
fi

echo
echo "=========================================================================="
echo "SCENARIO 42 — Proofdelve ForgeOs-b9mj. THE CO-DISPATCH GUARD: OVERLAPPING TOUCH SETS"
echo "              NEVER SHARE A PASS; DISJOINT ONES DO; NO LINE MEANS SERIAL"
echo "=========================================================================="
# Forge concurrency 2 and two ready beads, in ONE dispatch pass. The property is
# decided inside dispatch_pass against a worker dispatched seconds earlier in the
# same loop, so it is measured end to end: the first bead's worker directory is
# inside its launch grace window (live), the second candidate is read from bd,
# its Touches line parsed, and the intersection asked. E2E_FORGE_SLEEP keeps the
# first Forge alive across the pass. Separate forts per case, because the
# outcome of one dispatch must not be the fixture of the next.
b9mj_fixture() { # $1 name, $2 db lines, [$3 launcher] -> sets r st db and the launcher
  r=$(mkfort "$1" ok); unpoison "$r"
  sed -i 's/^FLEET_FORGE_START=1$/FLEET_FORGE_START=2/' "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "conc 2"
  mk_launcher "${3:-$launcher}" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf '%b' "$2" > "$db"
}
dispatched_count() { grep -c '  dispatched E2E-' "$1/out.txt" 2>/dev/null; }   # say() prefixes a clock; anchor on its two-space gap, not on the line start

# 42a OVERLAP: web/src/App.tsx against web/src/ -- prefix in one direction
b9mj_fixture s42a 'E2E-tsa|open||fleet-safe||web/src/App.tsx, docs/\nE2E-tsb|open||fleet-safe||web/src/\n'
E2E_FORGE_SLEEP=3 run_pass "$work/s42a-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
# the pair prints the candidate's prefix first, then the live worker's
if [ "$(dispatched_count "$st")" -eq 1 ] && grep -q 'dispatched E2E-tsa' <<<"$out" \
   && grep -q 'skip E2E-tsb: its touch set overlaps worker E2E-tsa on web/src/ ~ web/src/App.tsx' <<<"$out" \
   && [ "$(grep -c '^E2E-tsb|open||fleet-safe' "$db")" -eq 1 ]; then
  ok "b9mj: two beads whose touch sets OVERLAP at concurrency 2 -> exactly one dispatched; the skip line names the pair and the overlapping prefixes; the other stays open and unclaimed"
else no "b9mj: overlapping sets co-dispatched or the pair was not named" "dispatched=$(dispatched_count "$st")
$(grep -E 'dispatched|skip|touch' "$st/out.txt")
$(cat "$db")"; fi
wait_forge "$st" tsa

# 42b DISJOINT: both go in one pass
b9mj_fixture s42b 'E2E-tsc|open||fleet-safe||src/digest.ts\nE2E-tsd|open||fleet-safe||test/\n'
E2E_FORGE_SLEEP=3 run_pass "$work/s42b-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
if [ "$(dispatched_count "$st")" -eq 2 ] && [ -s "$st/workers/tsc/touches" ] && [ -s "$st/workers/tsd/touches" ] \
   && [ "$(cat "$st/workers/tsd/touches")" = "test/" ]; then
  ok "b9mj: DISJOINT touch sets -> both dispatched in one pass, and each worker's set is cached in its directory as normalised prefixes"
else no "b9mj: disjoint sets did not both dispatch" "dispatched=$(dispatched_count "$st") tsc=[$(cat "$st/workers/tsc/touches" 2>/dev/null)] tsd=[$(cat "$st/workers/tsd/touches" 2>/dev/null)]
$(grep -E 'dispatched|skip|touch' "$st/out.txt")"; fi
wait_forge "$st" tsc; wait_forge "$st" tsd

# 42c NO LINE WAITS: an undeclared candidate behind a declared live Forge
b9mj_fixture s42c 'E2E-tse|open||fleet-safe||docs/\nE2E-tsf|open||fleet-safe\n'
E2E_FORGE_SLEEP=3 run_pass "$work/s42c-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
if [ "$(dispatched_count "$st")" -eq 1 ] && grep -q 'dispatched E2E-tse' <<<"$out" \
   && grep -q 'skip E2E-tsf: its touch set overlaps worker E2E-tse on <everything>' <<<"$out"; then
  ok "b9mj: a bead with NO Touches line touches everything: it WAITS while any Forge is live (today's serial behaviour), and the skip line says so"
else no "b9mj: an undeclared bead co-dispatched" "dispatched=$(dispatched_count "$st")
$(grep -E 'dispatched|skip|touch' "$st/out.txt")"; fi
wait_forge "$st" tse

# 42d NO LINE BLOCKS: a declared candidate behind an undeclared live Forge --
# the other direction, so the sentinel is read on the live side too
b9mj_fixture s42d 'E2E-tsg|open||fleet-safe\nE2E-tsh|open||fleet-safe||docs/\n'
E2E_FORGE_SLEEP=3 run_pass "$work/s42d-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
if [ "$(dispatched_count "$st")" -eq 1 ] && grep -q 'dispatched E2E-tsg' <<<"$out" \
   && grep -q 'skip E2E-tsh: its touch set overlaps worker E2E-tsg on <everything>' <<<"$out" \
   && [ "$(cat "$st/workers/tsg/touches")" = "<everything>" ]; then
  ok "b9mj: an undeclared LIVE Forge blocks every declared candidate (the sentinel is cached on the live side); an unlabelled board degrades to serial, never to collisions"
else no "b9mj: a declared bead dispatched beside an undeclared live Forge" "dispatched=$(dispatched_count "$st") tsg=[$(cat "$st/workers/tsg/touches" 2>/dev/null)]
$(grep -E 'dispatched|skip|touch' "$st/out.txt")"; fi
wait_forge "$st" tsg

# 42e THE WAIT ENDS: once the overlapping Forge is reaped the held bead dispatches
# on the next pass, unblocked by nothing but time -- a refusal is not a block edge.
b9mj_fixture s42e 'E2E-tsi|open||fleet-safe||src/shared/\nE2E-tsj|open||fleet-safe||src/shared/\n'
E2E_FORGE_SLEEP=2 run_pass "$work/s42e-fleet.sh" "$st" "$db" || true; out1=$(cat "$st/out.txt")
wait_forge "$st" tsi
run_pass "$work/s42e-fleet.sh" "$st" "$db" || true; out2=$(cat "$st/out.txt")
if grep -q 'skip E2E-tsj: its touch set overlaps worker E2E-tsi on src/shared/ ~ src/shared/' <<<"$out1" \
   && grep -q 'dispatched E2E-tsj' <<<"$out2"; then
  ok "b9mj: two beads declaring the same directory serialise; the held one dispatches on the pass after the first Forge is reaped (the source fort's migration-widening form of this case is not carried)"
else no "b9mj: same-directory serialising or the release after reap" "pass1: $(grep -E 'dispatched|skip' <<< "$out1")
pass2: $(grep -E 'dispatched|skip' <<< "$out2")"; fi
wait_forge "$st" tsj

# 42f VACUITY / MUST-NOT-CHANGE: with ONE slot the guard is never consulted for a
# second candidate, and a declared bead carrying `human` is still refused by
# dispatchable() before any touch set is read.
b9mj_fixture s42f 'E2E-tsk|open||fleet-safe,human||docs/\nE2E-tsl|open||fleet-safe||web/\n'
sed -i 's/^FLEET_FORGE_START=2$/FLEET_FORGE_START=1/' "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "conc 1"
E2E_FORGE_SLEEP=1 run_pass "$work/s42f-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
if [ "$(dispatched_count "$st")" -eq 1 ] && grep -q 'dispatched E2E-tsl' <<<"$out" \
   && grep -q 'skip E2E-tsk: carries the human label' <<<"$out" \
   && ! grep -q 'touch set overlaps' <<<"$out"; then
  ok "b9mj MUST NOT CHANGE: the human-label refusal still comes first and a declared set buys a gated bead nothing; at one slot the guard never speaks"
else no "b9mj: dispatchable() ordering or the one-slot case changed" "dispatched=$(dispatched_count "$st")
$(grep -E 'dispatched|skip|touch' "$st/out.txt")"; fi
wait_forge "$st" tsl

# 42h DRY-RUN CONSULTS ITS OWN PASS (the Warden finding 3 on 40c3d6d): the same
# overlapping pair under --dry-run reports ONE would-dispatch and one skip,
# as a real pass would; before the fold both printed would-dispatch.
b9mj_fixture s42h 'E2E-tsr|open||fleet-safe||web/src/App.tsx\nE2E-tss|open||fleet-safe||web/src/\n'
run_dry_pass "$work/s42h-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
if [ "$(grep -c 'DRY-RUN would dispatch' "$st/out.txt")" -eq 1 ] && grep -q 'DRY-RUN would dispatch E2E-tsr' <<<"$out" \
   && grep -q 'skip E2E-tss: its touch set overlaps worker E2E-tsr (dry-run, this pass) on web/src/ ~ web/src/App.tsx' <<<"$out" \
   && [ ! -d "$st/.touches-dry" ] && [ "$(grep -c '|open||fleet-safe' "$db")" -eq 2 ]; then
  ok "b9mj: under --dry-run the second of an overlapping pair is held against the first's dry set, reported as such, nothing claimed, and the pass-local set is cleaned up"
else no "b9mj: dry-run pair" "$(grep -E 'DRY-RUN|skip' "$st/out.txt") dry_dir=$([ -d "$st/.touches-dry" ] && echo present || echo absent)"; fi

# THE INVERSION: the launcher before Proofdelve ForgeOs-b9mj co-dispatches the overlapping
# pair of 42a. Reported NOT RUN, never PASS, when the before-file is absent.
if [ -n "$pre_b9mj" ] && [ -s "$pre_b9mj" ]; then
  b9mj_fixture s42g 'E2E-tsa|open||fleet-safe||web/src/App.tsx, docs/\nE2E-tsb|open||fleet-safe||web/src/\n' "$pre_b9mj"
  E2E_FORGE_SLEEP=3 run_pass "$work/s42g-fleet.sh" "$st" "$db" || true
  if [ "$(dispatched_count "$st")" -eq 2 ]; then
    ok "RED: the pre-b9mj launcher dispatches BOTH overlapping beads in one pass -- the o6ky.13 collision reproduced -- so 42a can fail"
  else no "the pre-b9mj launcher did not co-dispatch the overlapping pair" "dispatched=$(dispatched_count "$st")
$(grep -E 'dispatched|skip' "$st/out.txt")"; fi
  wait_forge "$st" tsa; wait_forge "$st" tsb
else
  skip "b9mj inversion" "FLEET_SH_PRE_B9MJ not set (git show 87b8afa:fort/scripts/fleet.sh)"
fi

echo
echo "=========================================================================="
echo "SCENARIO 43 — Proofdelve ForgeOs-xzg1. THE CEILING IS CARRIED ACROSS RUNS BY AN"
echo "              ORDINARY END AND RESET BY A HALT"
echo "=========================================================================="
# The unit half (clamping, an unreadable file, budget_stop) is in
# scripts/governor-harness.sh; this is the two real ends: a run that DRAINS
# writes $FLEET_STATE/ceiling.last and the next run says it started from it, and
# a run that HALTS (scenario 2's post-merge-red shape) removes it.
r=$(mkfort s43 ok); unpoison "$r"
sed -i 's/^FLEET_FORGE_START=1$/FLEET_FORGE_START=2/' "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "conc 2"
mk_launcher "$launcher" "$work/s43-fleet.sh" "$r" || exit 3
st="$work/s43-state"; mkdir -p "$st"; db="$work/s43.bd"
printf 'E2E-tsm|open||fleet-safe\n' > "$db"
run_loop "$work/s43-fleet.sh" "$st" "$db" 40; rc=$?; out=$(cat "$st/out.txt")
if [ "$rc" -eq 0 ] && grep -q 'queue drained' <<<"$out" \
   && [ "$(cut -d'|' -f1 "$st/ceiling.last" 2>/dev/null)" = 2 ] && grep -q 'carry forge_conc=2 for the next run' "$st/ceiling.log" \
   && grep -q 'forge concurrency starts at 2 (FLEET_FORGE_START)' <<<"$out"; then
  ok "xzg1: a run that DRAINS writes ceiling.last with its final forge_conc, and the first run said it started from FLEET_FORGE_START"
else no "xzg1: the drain did not carry the ceiling out" "rc=$rc file=[$(cat "$st/ceiling.last" 2>/dev/null)]
$(grep -E 'governor|drained' "$st/out.txt" | tail -4)"; fi
prev="$(cut -d'|' -f2 "$st/ceiling.last" 2>/dev/null)"
run_loop "$work/s43-fleet.sh" "$st" "$db" 40; rc=$?; out=$(cat "$st/out.txt")
if [ "$rc" -eq 0 ] && grep -q "forge concurrency starts at 2 (carried from run $prev)" <<<"$out" \
   && grep -q "start forge_conc=2 (carried from run $prev)" "$st/ceiling.log"; then
  ok "xzg1: the NEXT run starts from the carried value and names the run it came from, in the narrative and in ceiling.log"
else no "xzg1: the next run did not carry in" "rc=$rc prev=$prev
$(grep -E 'governor' "$st/out.txt" | tail -2)
$(tail -3 "$st/ceiling.log")"; fi
# THE HALT: scenario 2's fixture (post-merge verifier RED) with a carry file
# pre-placed. After the halt the file is gone and the log says why.
r=$(mkfort s43b POISON); mk_launcher "$launcher" "$work/s43b-fleet.sh" "$r" || exit 3
st="$work/s43b-state"; mkdir -p "$st"; db="$work/s43b.bd"
printf 'E2E-tsn|open||fleet-safe\n' > "$db"
cat > "$r/fort/scripts/verify.sh" <<V
#!/bin/bash
case "\$PWD" in *-worktrees/postmerge-*) echo "VERIFIER RED in \$PWD"; exit 1 ;; esac
echo "VERIFIER GREEN in \$PWD"; exit 0
V
git -C "$r" add -A >/dev/null; git -C "$r" commit -qm "regression only visible after the merge"
printf '2|RPLACED|t\n' > "$st/ceiling.last"
run_pass "$work/s43b-fleet.sh" "$st" "$db" || true; wait_forge "$st" tsn
run_pass "$work/s43b-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if [ "$rc" -eq 70 ] && [ -e "$st/HALT" ] && [ ! -e "$st/ceiling.last" ] && grep -q 'carry RESET (halted)' "$st/ceiling.log" \
   && grep -q 'forge concurrency starts at 2 (carried from run RPLACED)' <<<"$out"; then
  ok "xzg1: a run that HALTS (post-merge red) started from the carried value and then REMOVED ceiling.last, so the run after the halt starts from FLEET_FORGE_START"
else no "xzg1: the halt did not reset the carry" "rc=$rc halt=$([ -e "$st/HALT" ] && echo yes || echo no) carry=$([ -e "$st/ceiling.last" ] && echo present || echo absent)
$(tail -3 "$st/ceiling.log")"; fi

echo
echo "=========================================================================="
echo "SCENARIO 44 — Proofdelve ForgeOs-36b9. LANDABILITY BEFORE THE REVIEW, REFRESH BEFORE"
echo "              THE VERIFY: a conflict is paged with no launch spent; a clean"
echo "              branch is verified and reviewed at the tip that will land"
echo "=========================================================================="
# main moves AFTER the Forge cut its branch and BEFORE the reap, exactly the
# o6ky.13 shape. The stub Forge creates marker-<sfx>.txt; a commit on main that
# also creates that file conflicts; a commit to other.txt does not.
r=$(mkfort s44 ok); unpoison "$r"; mk_launcher "$launcher" "$work/s44-fleet.sh" "$r" || exit 3
st="$work/s44-state"; mkdir -p "$st"; db="$work/s44.bd"
printf 'E2E-tso|open||fleet-safe\n' > "$db"
run_pass "$work/s44-fleet.sh" "$st" "$db" || true; wait_forge "$st" tso
printf 'main got here first\n' > "$r/marker-tso.txt"; git -C "$r" add marker-tso.txt; git -C "$r" commit -qm "main creates marker-tso.txt"
before="$(git -C "$r" rev-parse bead/tso)"
run_pass "$work/s44-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if grep -q 'E2E-tso: bead/tso CONFLICTS with main on marker-tso.txt' <<<"$out" && grep -q 'PAGED the Overseer' <<<"$out" \
   && ! grep -q '^E2E-tso ' "$r/warden-ranges" 2>/dev/null && ! grep -q 'running the host verifier' <<<"$out" \
   && [ "$(git -C "$r" rev-parse bead/tso)" = "$before" ] && [ "$(wstate "$st/workers/tso")" = needs-person ] \
   && grep -q '^E2E-tso|in_progress|justin|human' "$db" && ! merged_in "$r" tso; then   # Proofdelve ForgeOs-29j3g: a page assigns the Overseer
  ok "36b9: a branch that CONFLICTS with a moved main is PAGED before the verifier and before any Warden launch, naming the path; the branch is untouched, nothing merged, the bead carries human and not fleet-safe"
else no "36b9: the conflict was not caught before the review" "rc=$rc state=$(wstate "$st/workers/tso") ranges=[$(cat "$r/warden-ranges" 2>/dev/null)] db=$(cat "$db")
$(grep -E 'tso' "$st/out.txt" | tail -6)"; fi
# CLEAN: main moved on a different file; the branch is refreshed, verified at the
# refreshed tip (the stub verifier records the HEAD it ran at), reviewed on a
# three-dot range against a main it now contains, and lands.
r=$(mkfort s44b ok); unpoison "$r"; mk_launcher "$launcher" "$work/s44b-fleet.sh" "$r" || exit 3
st="$work/s44b-state"; mkdir -p "$st"; db="$work/s44b.bd"
printf 'E2E-tsp|open||fleet-safe\n' > "$db"
run_pass "$work/s44b-fleet.sh" "$st" "$db" || true; wait_forge "$st" tsp
printf 'unrelated\n' > "$r/other.txt"; git -C "$r" add other.txt; git -C "$r" commit -qm "main moves on other.txt"; moved="$(git -C "$r" rev-parse main)"
cut_tip="$(git -C "$r" rev-parse bead/tsp)"
run_pass "$work/s44b-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
vhead="$(grep -v postmerge "$r/verify-heads" 2>/dev/null | tail -1)"
if grep -q "E2E-tsp: refreshed .*tsp from main: ${cut_tip:0:12} -> " <<<"$out" \
   && [ -n "$vhead" ] && [ "$vhead" != "$cut_tip" ] && git -C "$r" merge-base --is-ancestor "$moved" "$vhead" \
   && grep -q '^E2E-tsp main...bead/tsp$' "$r/warden-ranges" && merged_in "$r" tsp && grep -q '^E2E-tsp|closed' "$db"; then
  ok "36b9: a CLEAN branch behind a moved main is refreshed in its worktree, verified AT THE REFRESHED TIP (a sha that contains main), reviewed on main...bead/X, and lands"
else no "36b9: the clean refresh path" "rc=$rc cut=$cut_tip verified_at=$vhead contains_main=$(git -C "$r" merge-base --is-ancestor "$moved" "${vhead:-HEAD}" && echo yes || echo no) ranges=[$(cat "$r/warden-ranges" 2>/dev/null)] merged=$(merged_in "$r" tsp && echo yes || echo no)
$(grep -E 'tsp' "$st/out.txt" | tail -8)"; fi
# THE INVERSION: the launcher before 36b9 spends the review on the conflicting
# branch and discovers the conflict at the merge -- o6ky.13 reproduced.
if [ -n "$pre_36b9" ] && [ -s "$pre_36b9" ]; then
  r=$(mkfort s44c ok); unpoison "$r"; mk_launcher "$pre_36b9" "$work/s44c-fleet.sh" "$r" || exit 3
  st="$work/s44c-state"; mkdir -p "$st"; db="$work/s44c.bd"
  printf 'E2E-tsq|open||fleet-safe\n' > "$db"
  run_pass "$work/s44c-fleet.sh" "$st" "$db" || true; wait_forge "$st" tsq
  printf 'main got here first\n' > "$r/marker-tsq.txt"; git -C "$r" add marker-tsq.txt; git -C "$r" commit -qm "main creates marker-tsq.txt"
  run_pass "$work/s44c-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
  if grep -q '^E2E-tsq ' "$r/warden-ranges" 2>/dev/null && grep -q 'merge into main failed and was aborted' <<<"$out"; then
    ok "RED: the pre-36b9 launcher verifies and REVIEWS the conflicting branch and finds the conflict only at the merge -- the o6ky.13 spent review reproduced -- so 44 can fail"
  else no "the pre-36b9 launcher did not reproduce the spent review" "ranges=[$(cat "$r/warden-ranges" 2>/dev/null)]
$(grep -E 'tsq' "$st/out.txt" | tail -6)"; fi
else
  skip "36b9 inversion" "FLEET_SH_PRE_36B9 not set (git show 025a52f:fort/scripts/fleet.sh)"
fi

echo
echo "=========================================================================="
echo "SCENARIO 45 — Proofdelve ForgeOs-b9mj round three. A CANDIDATE HELD BEHIND A PARKED"
echo "              MERGE IS A WAITING PASS, NOT A STALL; THE HOLD ENDS WHEN THE"
echo "              MERGE LANDS"
echo "=========================================================================="
# The Warden's blocking finding on ad911a7, reproduced at run level: bead tst
# (declared src/a/) lands into a DIRTY root, so its merge parks (deferred-merge,
# scenario 1's shape); bead tsu is undeclared (everything) and ready; no Forge
# is live. Under ad911a7 the third quiet pass HALTED the fleet as stalled.
# Now the run waits, says so once, and when the tree is cleaned the merge lands
# and tsu dispatches. FLEET_POLL=1, FLEET_STALL_PASSES=3 in the stub conf.
r=$(mkfort s45 ok); unpoison "$r"; mk_launcher "$launcher" "$work/s45-fleet.sh" "$r" || exit 3
st="$work/s45-state"; mkdir -p "$st"; db="$work/s45.bd"
printf 'E2E-tst|open||fleet-safe||src/a/\nE2E-tsu|open||fleet-safe\n' > "$db"
run_pass "$work/s45-fleet.sh" "$st" "$db" || true; wait_forge "$st" tst     # tst dispatched; tsu held behind the LIVE Forge
echo two >> "$r/subject.txt"                                                # dirty root: tst's merge will park
run_loop "$work/s45-fleet.sh" "$st" "$db" 12; rc=$?; out=$(cat "$st/out.txt")
if [ "$rc" -eq 124 ] && [ ! -e "$st/HALT" ] && [ "$(wstate "$st/workers/tst")" = deferred-merge ] \
   && [ "$(grep -c 'held behind a worker whose branch has not landed' "$st/out.txt")" -eq 1 ] \
   && ! grep -q 'stall 1/3' <<<"$out" && ! grep -q 'dispatched E2E-tsu' "$st/out.txt"; then
  ok "b9mj r3: with tst's merge PARKED and tsu held behind it, twelve seconds of quiet passes did NOT halt -- no HALT file, no stall count, the waiting sentence said once, tsu not dispatched beside the unlanded branch"
else no "b9mj r3: the held candidate stalled or dispatched" "rc=$rc halt=$([ -e "$st/HALT" ] && echo yes || echo no) tst=$(wstate "$st/workers/tst")
$(grep -E 'stall|held|HALT|dispatched|tsu' "$st/out.txt" | tail -8)"; fi
git -C "$r" checkout -- subject.txt                                           # the operator cleans the tree
run_loop "$work/s45-fleet.sh" "$st" "$db" 20; rc=$?; out=$(cat "$st/out.txt")
if merged_in "$r" tst && grep -q '^E2E-tst|closed' "$db" && grep -q 'dispatched E2E-tsu' <<<"$out" && [ ! -e "$st/HALT" ]; then
  ok "b9mj r3: once the tree is clean the parked merge LANDS, tst closes, and the held candidate tsu dispatches on the next pass -- the hold ended by itself"
else no "b9mj r3: the hold did not end when the merge landed" "rc=$rc merged=$(merged_in "$r" tst && echo yes || echo no) db=$(grep tst "$db")
$(grep -E 'tst|tsu|HALT' "$st/out.txt" | tail -8)"; fi
wait_forge "$st" tsu
# THE INVERSION: ad911a7 (round two, before this fix) halts the same fixture
# as stalled within the twelve seconds.
if [ -n "$pre_r3" ] && [ -s "$pre_r3" ]; then
  r=$(mkfort s45b ok); unpoison "$r"; mk_launcher "$pre_r3" "$work/s45b-fleet.sh" "$r" || exit 3
  st="$work/s45b-state"; mkdir -p "$st"; db="$work/s45b.bd"
  printf 'E2E-tst|open||fleet-safe||src/a/\nE2E-tsu|open||fleet-safe\n' > "$db"
  run_pass "$work/s45b-fleet.sh" "$st" "$db" || true; wait_forge "$st" tst
  echo two >> "$r/subject.txt"
  run_loop "$work/s45b-fleet.sh" "$st" "$db" 12; rc=$?
  # halt() writes the date and the REASON to the halt file; the reason's text
  # is "N consecutive passes changed no state", not the kind word (the Warden, round
  # three, note 1: an earlier spelling grepped for 'stalled' inside an
  # unparenthesised && chain, so only the out.txt half ever decided).
  if [ "$rc" -eq 70 ] && [ -e "$st/HALT" ] && grep -q 'consecutive passes changed no state' "$st/HALT" \
     && grep -q 'HALT: 3 consecutive passes' "$st/out.txt"; then
    ok "RED: the pre-fix launcher (ad911a7) HALTS the same fixture as stalled -- the Warden's finding reproduced by execution -- so scenario 45 can fail"
  else no "the pre-fix launcher did not false-halt" "rc=$rc halt=$([ -e "$st/HALT" ] && echo yes || echo no)
$(grep -E 'stall|HALT' "$st/out.txt" | tail -5)"; fi
else
  skip "b9mj r3 inversion" "FLEET_SH_PRE_R3 not set (git show ad911a7:fort/scripts/fleet.sh)"
fi

# ==========================================================================
# Proofdelve ForgeOs-ubgx — AN APPROVAL IS PINNED TO A CHANGE. Six scenarios, one per
# criterion on the bead plus the refresh cases. Written in the herestring form
# (`grep -q PATTERN <<<"$out"`) because bead/c815 is rewriting every
# `printf | grep -q` site in this file and will refresh against main after the
# sitting that added this block; keeping the block contiguous and at the end
# is what lets that refresh merge clean or conflict in exactly one place.
# ==========================================================================
# Run a bead through a Forge, the verifier and a review that ESCALATES; the
# tracker then reads open, unassigned, `human`, no fleet-safe, and the worker
# record holds the stored verdict. Prints "root|state|db".
run_to_escalate() { # $1 name, $2 sfx, $3 launcher-src
  local r st db
  r=$(mkfort "$1" ok); unpoison "$r"; mk_launcher "$3" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  wait_forge "$st" "$2"
  E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  printf '%s|%s|%s' "$r" "$st" "$db"
}
# The Overseer's Approve on the Keep, as Proofdelve ForgeOs-bwfv and the ubgx Keep half
# leave the tracker and the stream: human removed, fleet-safe restored, and a
# gate.approved whose payload pins the branch tip (or null). The line is
# written into the fort's OWN day file, which is where the fleet reads it; the
# stub emit.sh writes elsewhere.
# Since Proofdelve ForgeOs-ubgx.4 the Keep ALSO writes a pin line into its own audit in
# the Overseer store, and the fleet requires it: keep_approve writes both, as the
# Civ Keep does. stream_only_approve writes the stream line alone -- what a seat
# that can run emit.sh, and cannot write the store, is able to produce.
stream_only_approve() { # $1 root, $2 db, $3 sfx, $4 approvedSha as JSON ("<sha>" or null)
  local bead="E2E-$3"
  BD_STORE="$2" bd update "$bead" --remove-label human >/dev/null
  BD_STORE="$2" bd update "$bead" --assignee "" >/dev/null   # Proofdelve ForgeOs-29j3g: the Keep's Approve hands the bead back to the fleet
  BD_STORE="$2" bd update "$bead" --add-label fleet-safe >/dev/null
  printf '{"ts":"%s","actor":"justin","seat":"overseer","category":"gate.approved","target":"%s","detail":"%s: approve — approved","payload":{"approvedSha":%s,"branch":"bead/%s"}}\n' \
    "$(date -Is)" "$bead" "$bead" "$4" "$3" >> "$1/fort/events/events-$(date +%F).jsonl"
}
keep_pin() { # $1 sfx, $2 approvedSha as JSON -- what the Civ Keep writes on an Approve: an intent line and a pin line sharing one ts
  local ts; ts="$(date -u +%FT%T.%3NZ)"
  printf '{"ts":"%s","fort":"{{KEEP_ID}}","bead":"E2E-%s","action":"approve","option":null,"text":""}\n' "$ts" "$1" >> "$XDG_STATE_HOME/civ-keep/signatures.jsonl"
  printf '{"ts":"%s","fort":"{{KEEP_ID}}","bead":"E2E-%s","step":"pin","approvedSha":%s,"branch":"bead/%s"}\n' \
    "$ts" "$1" "$2" "$1" >> "$XDG_STATE_HOME/civ-keep/signatures.jsonl"
}
keep_decline() { # $1 sfx -- a later Decline on the Keep's desk: an intent line, no pin
  printf '{"ts":"%s","fort":"{{KEEP_ID}}","bead":"E2E-%s","action":"decline","option":null,"text":"not this"}\n' \
    "$(date -u +%FT%T.%3NZ)" "$1" >> "$XDG_STATE_HOME/civ-keep/signatures.jsonl"
}
keep_approve() { # $1 root, $2 db, $3 sfx, $4 approvedSha as JSON ("<sha>" or null)
  stream_only_approve "$@"; keep_pin "$3" "$4"
}
claims_of() { grep -c "^update E2E-$1 --claim" "$2.calls" 2>/dev/null; }   # bd claims = dispatches + signed landings; the -a field says which
pendings() { grep -c '^review.pending ' "$1/emitted" 2>/dev/null; }

echo
echo "=========================================================================="
echo "SCENARIO 46 — Proofdelve ForgeOs-ubgx. A SIGNED, UNCHANGED BRANCH LANDS WITHOUT A"
echo "              SECOND LAP; ANY CHANGE TO THE PATCH ROUTES TO REVIEW"
echo "=========================================================================="
# 46a — criterion 1. ESCALATE, approve at the tip, next pass MERGES: no second
# Forge claim, no second review.pending, one fleet.signed naming the sha.
IFS='|' read -r r st db <<< "$(run_to_escalate s46a uba "$launcher")"
tip="$(git -C "$r" rev-parse bead/uba)"
if [ "$(cat "$st/workers/uba/verdict" 2>/dev/null)" = ESCALATE ] && grep -q '^E2E-uba|open|justin|human$' "$db" && [ "$(pendings "$r")" -eq 1 ]; then
  ok "ubgx fixture: the review ESCALATED, the tracker reads open/assigned to justin/human (Proofdelve ForgeOs-29j3g), and the worker record stores the verdict ESCALATE"
else no "ubgx fixture did not escalate" "verdict=$(cat "$st/workers/uba/verdict" 2>/dev/null) db=$(cat "$db") pendings=$(pendings "$r")
$(tail -6 "$st/out.txt")"; fi
keep_approve "$r" "$db" uba "\"$tip\""
run_pass "$work/s46a-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if merged_in "$r" uba && grep -q '^E2E-uba|closed' "$db" && grep -q 'SIGNED LANDING' <<<"$out" \
   && [ "$(claims_of uba "$db")" -eq 2 ] && grep -q '^update E2E-uba --claim -a fleet ' "$db.calls" \
   && [ "$(pendings "$r")" -eq 1 ] && [ "$(dispatched_count "$st")" -eq 0 ] \
   && grep -q "^fleet.signed .*$tip" "$r/emitted" && grep -q '"storedVerdict":"ESCALATE"' "$r/emitted" \
   && grep -q '^close E2E-uba --reason=merged and closed by fort/scripts/fleet.sh on OVERSEER-SIGNED' "$db.calls" \
   && git -C "$r" log -1 --format=%B | grep -q "Overseer's recorded approval" && git -C "$r" log -1 --format=%B | grep -q "$tip"; then
  ok "ubgx 1: approved at its tip, the escalated branch MERGED and CLOSED on the next pass on OVERSEER-SIGNED -- no Forge dispatched (claim -a fleet, not {{FORGE_ID}}), no second review.pending, fleet.signed names the sha, the merge message names the approval"
else no "ubgx 1: the signed landing did not happen" "rc=$rc merged=$(merged_in "$r" uba && echo yes || echo no) db=$(grep uba "$db") claims=$(claims_of uba "$db") pendings=$(pendings "$r") dispatched=$(dispatched_count "$st")
$(grep -E 'uba|SIGNED' "$st/out.txt" | tail -8)"; fi

# 46b — criterion 2, THE RED CONTROL. The launcher before ubgx meets the same
# state and DISPATCHES A FORGE at the signed work: a second claim for {{FORGE_ID}}.
if [ -n "$pre_ubgx" ] && [ -s "$pre_ubgx" ]; then
  IFS='|' read -r r st db <<< "$(run_to_escalate s46b ubb "$pre_ubgx")"
  tip="$(git -C "$r" rev-parse bead/ubb)"
  keep_approve "$r" "$db" ubb "\"$tip\""
  E2E_FORGE_REUSE=1 run_pass "$work/s46b-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
  wait_forge "$st" ubb
  if grep -q 'dispatched E2E-ubb' <<<"$out" && [ "$(claims_of ubb "$db")" -eq 2 ] && grep -q '^update E2E-ubb --claim -a {{FORGE_ID}} ' "$db.calls" \
     && ! merged_in "$r" ubb && ! grep -q 'fleet.signed' "$r/emitted"; then
    ok "RED: the pre-ubgx launcher DISPATCHES A FORGE at the signed, unchanged branch (a second claim for {{FORGE_ID}}, nothing merged) -- the duplicate lap reproduced, so 46a can fail"
  else no "the pre-ubgx launcher did not reproduce the second lap" "rc=$rc claims=$(claims_of ubb "$db") merged=$(merged_in "$r" ubb && echo yes || echo no)
$(grep -E 'ubb' "$st/out.txt" | tail -6)"; fi
else
  skip "ubgx inversion" "FLEET_SH_PRE_UBGX not set (git show 4cfa84df:fort/scripts/fleet.sh)"
fi

# 46c — criterion 3, THE SAFETY PROPERTY. One commit on top of the approved sha
# and the signature covers nothing: the bead takes the ordinary path (a Forge,
# then the verifier, then a SECOND review) and does not merge on the approval.
IFS='|' read -r r st db <<< "$(run_to_escalate s46c ubc "$launcher")"
tip="$(git -C "$r" rev-parse bead/ubc)"
keep_approve "$r" "$db" ubc "\"$tip\""
printf 'after the signature\n' >> "$r-worktrees/ubc/subject.txt"; git -C "$r-worktrees/ubc" commit -qam "E2E-ubc: a commit after the approval"
E2E_FORGE_REUSE=1 E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s46c-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
wait_forge "$st" ubc
E2E_FORGE_REUSE=1 E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s46c-fleet.sh" "$st" "$db" || true; out2=$(cat "$st/out.txt")
if grep -q 'NOT landable on the signature (the branch has CHANGED since the approval' <<<"$out" && grep -q 'dispatched E2E-ubc' <<<"$out" \
   && ! merged_in "$r" ubc && ! grep -q '^E2E-ubc|closed' "$db" && ! grep -q 'fleet.signed' "$r/emitted" \
   && [ "$(pendings "$r")" -eq 2 ] && grep -q '^E2E-ubc|open|justin|human$' "$db"; then
  ok "ubgx 3: a commit ON TOP of the approved sha voids the signature -- the fleet says so, takes the ordinary path, a SECOND review runs (review.pending x2), the branch is NOT merged on the approval, and it is back on the Overseer's queue"
else no "ubgx 3: the post-approval commit did not void the signature" "rc=$rc merged=$(merged_in "$r" ubc && echo yes || echo no) pendings=$(pendings "$r") db=$(grep ubc "$db") signed=$(grep -c fleet.signed "$r/emitted")
$(grep -E 'ubc|SIGNED|CHANGED' "$st/out.txt" | tail -8)
$(grep -E 'ubc' <<<"$out2" | tail -4)"; fi

# 46d — a clean refresh that CHANGES THE PATCH routes to review with no Forge.
# The base carries shared.txt (20 lines); the Forge appends a line 21; after
# the approval main rewrites line 19. The merge is clean (line 20 separates
# them) and the branch's hunk now carries different context, so its patch-id
# against the new base differs from the approved one. Recomputed AFTER the
# refresh, the fleet must verify and REVIEW rather than merge on the signature.
r=$(mkfort s46d ok); unpoison "$r"; mk_launcher "$launcher" "$work/s46d-fleet.sh" "$r" || exit 3
st="$work/s46d-state"; mkdir -p "$st"; db="$work/s46d.bd"
seq -f 'line %g' 1 20 > "$r/shared.txt"; git -C "$r" add shared.txt; git -C "$r" commit -qm "base: shared.txt"
printf 'E2E-ubd|open||fleet-safe\n' > "$db"
E2E_FORGE_TOUCH=shared.txt E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s46d-fleet.sh" "$st" "$db" || true; wait_forge "$st" ubd
E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s46d-fleet.sh" "$st" "$db" || true
tip="$(git -C "$r" rev-parse bead/ubd)"
keep_approve "$r" "$db" ubd "\"$tip\""
sed -i '19s/.*/line 19 rewritten on main/' "$r/shared.txt"; git -C "$r" commit -qam "main rewrites line 19 of shared.txt"
E2E_WARDEN_TOKEN=APPROVE run_pass "$work/s46d-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if grep -q 'SIGNED LANDING' <<<"$out" && grep -q 'CHANGED the patch' <<<"$out" && grep -q 'ROUTING TO REVIEW' <<<"$out" \
   && [ "$(pendings "$r")" -eq 2 ] && [ "$(dispatched_count "$st")" -eq 0 ] && [ "$(claims_of ubd "$db")" -eq 2 ] \
   && merged_in "$r" ubd && grep -q '^E2E-ubd|closed' "$db" \
   && ! grep -q 'on OVERSEER-SIGNED' "$db.calls" && grep -q '^close E2E-ubd --reason=merged and closed by fort/scripts/fleet.sh on APPROVE' "$db.calls"; then
  ok "ubgx refresh: main moved into the signed hunk's context, the refresh merged clean and CHANGED the patch-id -- the fleet routed to REVIEW (no Forge, a second review.pending) and landed on the Warden's APPROVE, never on the signature"
else no "ubgx refresh: a patch-changing refresh did not route to review" "rc=$rc pendings=$(pendings "$r") dispatched=$(dispatched_count "$st") merged=$(merged_in "$r" ubd && echo yes || echo no) close=$(grep '^close E2E-ubd' "$db.calls" | cut -c1-90)
$(grep -E 'ubd|SIGNED|CHANGED|ROUTING' "$st/out.txt" | tail -8)"; fi

# 46e — a clean refresh that does NOT change the patch still lands on the
# signature: the tip moves (a SHA rule would never fire), the change is the
# same, and the verifier scores the REFRESHED tip.
IFS='|' read -r r st db <<< "$(run_to_escalate s46e ube "$launcher")"
tip="$(git -C "$r" rev-parse bead/ube)"
keep_approve "$r" "$db" ube "\"$tip\""
printf 'unrelated\n' > "$r/other.txt"; git -C "$r" add other.txt; git -C "$r" commit -qm "main moves on other.txt"; moved="$(git -C "$r" rev-parse main)"
run_pass "$work/s46e-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
vhead="$(grep -v postmerge "$r/verify-heads" 2>/dev/null | tail -1)"
if merged_in "$r" ube && grep -q '^E2E-ube|closed' "$db" && grep -q 'SIGNED LANDING' <<<"$out" && grep -q "E2E-ube: refreshed .*ube from main: ${tip:0:12} -> " <<<"$out" \
   && ! grep -q 'CHANGED the patch' <<<"$out" && [ "$(pendings "$r")" -eq 1 ] && [ "$(dispatched_count "$st")" -eq 0 ] \
   && [ -n "$vhead" ] && [ "$vhead" != "$tip" ] && git -C "$r" merge-base --is-ancestor "$moved" "$vhead" \
   && grep -q '^close E2E-ube --reason=merged and closed by fort/scripts/fleet.sh on OVERSEER-SIGNED' "$db.calls"; then
  ok "ubgx refresh: main moved on another file, the branch was refreshed (tip moved, patch-id unchanged), verified AT THE REFRESHED TIP, and landed on the signature -- same change, not same sha"
else no "ubgx refresh: the unchanged-patch refresh did not land on the signature" "rc=$rc merged=$(merged_in "$r" ube && echo yes || echo no) verified_at=$vhead tip=$tip pendings=$(pendings "$r")
$(grep -E 'ube|SIGNED|CHANGED' "$st/out.txt" | tail -8)"; fi

# 46f — criterion 4. A bead carrying fleet-escalated is not made dispatchable
# by an approval: dispatchable() refuses it before any signed question is asked.
IFS='|' read -r r st db <<< "$(run_to_escalate s46f ubf "$launcher")"
tip="$(git -C "$r" rev-parse bead/ubf)"
keep_approve "$r" "$db" ubf "\"$tip\""
BD_STORE="$db" bd update E2E-ubf --add-label fleet-escalated >/dev/null
run_pass "$work/s46f-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if grep -q 'skip E2E-ubf: escalated to the Mayor after repeated returns' <<<"$out" && ! grep -q 'SIGNED LANDING' <<<"$out" \
   && ! merged_in "$r" ubf && [ "$(claims_of ubf "$db")" -eq 1 ] && ! grep -q 'fleet.signed' "$r/emitted"; then
  ok "ubgx 4: fleet-escalated plus an approval is still refused by dispatchable() -- no signed question asked, nothing claimed, nothing merged"
else no "ubgx 4: fleet-escalated was made dispatchable by an approval" "rc=$rc claims=$(claims_of ubf "$db") merged=$(merged_in "$r" ubf && echo yes || echo no)
$(grep -E 'ubf' "$st/out.txt" | tail -5)"; fi

echo
echo "=========================================================================="
echo "SCENARIO 47 — Proofdelve ForgeOs-s2lx. THE ESCALATE BRANCH CHECKS ITS bd WRITE: a"
echo "              refused write is an incident naming the exit, never a"
echo "              fleet.returned asserting a label that is not there"
echo "=========================================================================="
# 47a — the write that puts the bead on the Overseer's queue (adds `human`) is
# refused. The record must say so: an incident with bd_exit, NO fleet.returned
# for the bead, the worker needs-person, and the tracker still claimed and
# still fleet-safe -- which is the truth the old event lied about.
r=$(mkfort s47a ok); unpoison "$r"; mk_launcher "$launcher" "$work/s47a-fleet.sh" "$r" || exit 3
st="$work/s47a-state"; mkdir -p "$st"; db="$work/s47a.bd"
printf 'E2E-sla|open||fleet-safe\n' > "$db"
E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s47a-fleet.sh" "$st" "$db" || true; wait_forge "$st" sla
E2E_WARDEN_TOKEN=ESCALATE E2E_BD_UPDATE_REFUSE_LABEL=human run_pass "$work/s47a-fleet.sh" "$st" "$db"; rc=$?; out=$(cat "$st/out.txt")
if grep -q '^incident Fleet recorded ESCALATE on E2E-sla but could NOT remove fleet-safe and apply human: the bd write failed (exit 1)' "$r/emitted" \
   && grep -q '"bd_exit":1' "$r/emitted" && ! grep -q '^fleet.returned E2E-sla' "$r/emitted" \
   && [ "$(wstate "$st/workers/sla")" = needs-person ] && grep -q '^E2E-sla|in_progress|{{FORGE_ID}}|fleet-safe$' "$db" \
   && [ "$(cat "$st/workers/sla/verdict" 2>/dev/null)" = ESCALATE ] && grep -q 'the bd write that puts it on the Overseer.s queue FAILED (exit 1)' <<<"$out"; then
  ok "s2lx: with the human-label write REFUSED, the ESCALATE branch emits an incident naming bd exit 1, emits NO fleet.returned, marks the worker needs-person, and the tracker reads what it is (still claimed, still fleet-safe)"
else no "s2lx: the refused write was not reported truthfully" "rc=$rc state=$(wstate "$st/workers/sla") db=$(cat "$db") emitted=$(grep -E 'sla' "$r/emitted" | cut -c1-120)
$(grep -E 'sla' "$st/out.txt" | tail -5)"; fi
# VACUITY: the same run with the write PERMITTED still emits fleet.returned and
# leaves the bead open/unassigned/human -- scenario 46a's fixture, asserted
# here on its own fort so a launcher that never emits fleet.returned cannot pass.
IFS='|' read -r r st db <<< "$(run_to_escalate s47v slb "$launcher")"
if grep -q '^fleet.returned E2E-slb escalated by review to the Overseer; fleet-safe removed, human label applied' "$r/emitted" \
   && ! grep -q '^incident Fleet recorded ESCALATE on E2E-slb' "$r/emitted" && grep -q '^E2E-slb|open|justin|human$' "$db" && [ "$(wstate "$st/workers/slb")" = settled ]; then
  ok "VACUITY: with the write permitted the branch still emits fleet.returned, no incident, and the tracker reads open/assigned to justin/human (Proofdelve ForgeOs-29j3g)"
else no "s2lx vacuity: the permitted write no longer records as before" "db=$(cat "$db") emitted=$(grep -E 'slb' "$r/emitted" | cut -c1-120)"; fi
# 47b — THE INVERSION. The launcher before the check emits fleet.returned
# "fleet-safe removed, human label applied" over a refused write.
if [ -n "$pre_s2lx" ] && [ -s "$pre_s2lx" ]; then
  r=$(mkfort s47b ok); unpoison "$r"; mk_launcher "$pre_s2lx" "$work/s47b-fleet.sh" "$r" || exit 3
  st="$work/s47b-state"; mkdir -p "$st"; db="$work/s47b.bd"
  printf 'E2E-sla|open||fleet-safe\n' > "$db"
  E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s47b-fleet.sh" "$st" "$db" || true; wait_forge "$st" sla
  E2E_WARDEN_TOKEN=ESCALATE E2E_BD_UPDATE_REFUSE_LABEL=human run_pass "$work/s47b-fleet.sh" "$st" "$db" || true
  if grep -q '^fleet.returned E2E-sla escalated by review to the Overseer; fleet-safe removed, human label applied' "$r/emitted" \
     && grep -q '^E2E-sla|in_progress|{{FORGE_ID}}|fleet-safe$' "$db"; then
    ok "RED: the pre-s2lx launcher emits fleet.returned 'fleet-safe removed, human label applied' while the tracker still reads claimed and fleet-safe -- the Warden's finding reproduced by execution, so 47a can fail"
  else no "the pre-s2lx launcher did not reproduce the false record" "db=$(cat "$db") emitted=$(grep -E 'sla' "$r/emitted" | cut -c1-120)"; fi
else
  skip "s2lx inversion" "FLEET_SH_PRE_S2LX not set (git show 4cfa84df:fort/scripts/fleet.sh serves)"
fi

echo
echo "=========================================================================="
echo "SCENARIO 48 — Proofdelve ForgeOs-ubgx, the fold of the Warden's 1.2 / 1.3 / 1.4 / 1.7. Each"
echo "              case runs against the shipped launcher and then against the"
echo "              pre-fold one (FLEET_SH_PRE_FOLD), where it must go the old way"
echo "=========================================================================="
keep_sign() { # $1 root, $2 db, $3 sfx, $4 category (gate.declined|decision.recorded) -- a later non-approve sign event, as the Keep emits it
  local bead="E2E-$3"
  printf '{"ts":"%s","actor":"justin","seat":"overseer","category":"%s","target":"%s","detail":"%s: %s — no","payload":null}\n' \
    "$(date -Is)" "$4" "$bead" "$bead" "${4#gate.}" >> "$1/fort/events/events-$(date +%F).jsonl"
}
# 48a — 1.3: a whitespace-only hand commit after the approval is a CHANGE.
# The stub Forge's by-<sfx>.txt line gains a trailing space (an ADDED line's
# whitespace, which patch-id without --verbatim strips). Shipped: not landable
# on the signature; pre-fold: lands on it.
ws_case() { # $1 name, $2 sfx, $3 launcher -> sets ws_out, ws_merged, ws_signed
  local r st db tip
  IFS='|' read -r r st db <<< "$(run_to_escalate "$1" "$2" "$3")"
  tip="$(git -C "$r" rev-parse "bead/$2")"; keep_approve "$r" "$db" "$2" "\"$tip\""
  printf '%s \n' "$2" > "$r-worktrees/$2/by-$2.txt"; git -C "$r-worktrees/$2" commit -qam "E2E-$2: whitespace only, after the approval"
  E2E_FORGE_REUSE=1 run_pass "$work/$1-fleet.sh" "$st" "$db" || true; ws_out=$(cat "$st/out.txt")
  ws_merged=$(merged_in "$r" "$2" && echo yes || echo no); ws_signed=$(grep -c '^fleet.signed' "$r/emitted")
}
ws_case s48a ubg "$launcher"
if [ "$ws_merged" = no ] && [ "$ws_signed" -eq 0 ] && grep -q 'NOT landable on the signature (the branch has CHANGED since the approval' <<<"$ws_out"; then
  ok "fold 1.3: a whitespace-only commit inside an added line AFTER the approval is a change -- not landed on the signature (patch-id --verbatim)"
else no "fold 1.3: whitespace-only post-approval commit landed on the signature" "merged=$ws_merged signed=$ws_signed
$(grep -E 'ubg' <<<"$ws_out" | tail -4)"; fi
if [ -n "$pre_fold" ] && [ -s "$pre_fold" ]; then
  ws_case s48ai ubk "$pre_fold"
  if [ "$ws_merged" = yes ] && [ "$ws_signed" -eq 1 ]; then
    ok "RED 1.3: the pre-fold launcher LANDS the whitespace-only post-approval commit on the signature -- the Warden's 1.3 reproduced, so 48a can fail"
  else no "the pre-fold launcher did not reproduce 1.3" "merged=$ws_merged signed=$ws_signed
$(grep -E 'ubk' <<<"$ws_out" | tail -4)"; fi
else skip "fold 1.3 inversion" "FLEET_SH_PRE_FOLD not set (git show ecd75295:fort/scripts/fleet.sh)"; fi

# 48b — 1.2: a hand commit BETWEEN the review and the approval. The Overseer
# then approves at the moved tip, so approved == tip by patch-id, but the
# reviewed tip differs. Shipped: refused, naming the review; pre-fold: lands.
rv_case() { # $1 name, $2 sfx, $3 launcher
  local r st db tip
  IFS='|' read -r r st db <<< "$(run_to_escalate "$1" "$2" "$3")"
  printf 'moved by hand after the review\n' >> "$r-worktrees/$2/subject.txt"; git -C "$r-worktrees/$2" commit -qam "E2E-$2: a hand commit after the ESCALATE, before the click"
  tip="$(git -C "$r" rev-parse "bead/$2")"; keep_approve "$r" "$db" "$2" "\"$tip\""
  # READ BEFORE THE PASS: the ordinary path's dispatch rm -rf's the worker dir.
  ws_reviewed="$(cat "$st/workers/$2/reviewed-sha" 2>/dev/null)"
  E2E_FORGE_REUSE=1 run_pass "$work/$1-fleet.sh" "$st" "$db" || true; ws_out=$(cat "$st/out.txt")
  ws_merged=$(merged_in "$r" "$2" && echo yes || echo no); ws_signed=$(grep -c '^fleet.signed' "$r/emitted")
}
rv_case s48b ubh "$launcher"
if [ "$ws_merged" = no ] && [ "$ws_signed" -eq 0 ] && [ -n "$ws_reviewed" ] && grep -q 'CHANGED between the review and the approval' <<<"$ws_out"; then
  ok "fold 1.2: the ESCALATE arm stored the reviewed tip, and a branch moved by hand between the review and the approval is NOT landed on the signature, naming both shas"
else no "fold 1.2: a change between review and approval landed on the signature" "merged=$ws_merged signed=$ws_signed reviewed=$ws_reviewed
$(grep -E 'ubh' <<<"$ws_out" | tail -4)"; fi
if [ -n "$pre_fold" ] && [ -s "$pre_fold" ]; then
  rv_case s48bi ubl "$pre_fold"
  if [ "$ws_merged" = yes ] && [ "$ws_signed" -eq 1 ] && [ -z "$ws_reviewed" ]; then
    ok "RED 1.2: the pre-fold launcher stores no reviewed tip and LANDS the hand-moved branch on the signature -- so 48b can fail"
  else no "the pre-fold launcher did not reproduce 1.2" "merged=$ws_merged signed=$ws_signed reviewed=$ws_reviewed"; fi
else skip "fold 1.2 inversion" "FLEET_SH_PRE_FOLD not set"; fi

# 48c — 1.4: an Approve followed by a Decline. fleet-safe stays (Decline does
# not remove it). Shipped: the newest sign event is not an approve, refused;
# pre-fold: the approve is still current and it lands.
dc_case() { # $1 name, $2 sfx, $3 launcher
  local r st db tip
  IFS='|' read -r r st db <<< "$(run_to_escalate "$1" "$2" "$3")"
  tip="$(git -C "$r" rev-parse "bead/$2")"; keep_approve "$r" "$db" "$2" "\"$tip\""
  sleep 1; keep_sign "$r" "$db" "$2" gate.declined
  E2E_FORGE_REUSE=1 run_pass "$work/$1-fleet.sh" "$st" "$db" || true; ws_out=$(cat "$st/out.txt")
  ws_merged=$(merged_in "$r" "$2" && echo yes || echo no); ws_signed=$(grep -c '^fleet.signed' "$r/emitted")
}
dc_case s48c ubi "$launcher"
if [ "$ws_merged" = no ] && [ "$ws_signed" -eq 0 ] && grep -q 'the newest sign event for E2E-ubi is gate.declined .* and not an approve, so the approval is superseded' <<<"$ws_out"; then
  ok "fold 1.4: an Approve followed by a Decline is NOT landed -- the newest sign event decides, only an approve counts, and the refusal NAMES the superseding event (the Warden 2.2)"
else no "fold 1.4: a declined-after-approve bead landed on the stale approval" "merged=$ws_merged signed=$ws_signed
$(grep -E 'ubi' <<<"$ws_out" | tail -4)"; fi
if [ -n "$pre_fold" ] && [ -s "$pre_fold" ]; then
  dc_case s48ci ubm "$pre_fold"
  if [ "$ws_merged" = yes ] && [ "$ws_signed" -eq 1 ]; then
    ok "RED 1.4: the pre-fold launcher reads gate.approved alone and LANDS after a later Decline -- so 48c can fail"
  else no "the pre-fold launcher did not reproduce 1.4" "merged=$ws_merged signed=$ws_signed"; fi
else skip "fold 1.4 inversion" "FLEET_SH_PRE_FOLD not set"; fi

# 48e — Proofdelve ForgeOs-jib0 (ruled 2026-11-14; Regent sitting 2026-11-16): ONLY THE
# KEEP'S OWN EVENTS ARE SIGN EVENTS. A Keep approve followed by a Mayor's
# decision.recorded (a transcription under the Mayor's own name). Shipped: the
# approval stands and the bead lands on the signature. Pre-jib0: the Mayor's
# event is the newest sign event, the approval reads superseded, no landing.
mayor_sign() { # $1 root, $2 sfx -- a decision.recorded as the MAYOR emits one
  printf '{"ts":"%s","actor":"{{MAYOR_ID}}","seat":"mayor","category":"decision.recorded","target":"E2E-%s","detail":"E2E-%s: transcribed from the session","payload":null}\n' \
    "$(date -Is)" "$2" "$2" >> "$1/fort/events/events-$(date +%F).jsonl"
}
md_case() { # $1 name, $2 sfx, $3 launcher, $4 who signs afterwards (mayor|keep)
  local r st db tip
  IFS='|' read -r r st db <<< "$(run_to_escalate "$1" "$2" "$3")"
  tip="$(git -C "$r" rev-parse "bead/$2")"; keep_approve "$r" "$db" "$2" "\"$tip\""
  sleep 1
  if [ "$4" = mayor ]; then mayor_sign "$r" "$2"; else keep_sign "$r" "$db" "$2" decision.recorded; fi
  E2E_FORGE_REUSE=1 run_pass "$work/$1-fleet.sh" "$st" "$db" || true; ws_out=$(cat "$st/out.txt")
  ws_merged=$(merged_in "$r" "$2" && echo yes || echo no); ws_signed=$(grep -c '^fleet.signed' "$r/emitted")
}
md_case s48e jba "$launcher" mayor
if [ "$ws_merged" = yes ] && [ "$ws_signed" -eq 1 ]; then
  ok "jib0: a Mayor decision.recorded after a Keep approve does NOT supersede it -- the bead lands on the signature"
else no "jib0: a Mayor transcription superseded a Keep approval" "merged=$ws_merged signed=$ws_signed
$(grep -E 'jba' <<<"$ws_out" | tail -4)"; fi
md_case s48ek jbb "$launcher" keep
if [ "$ws_merged" = no ] && [ "$ws_signed" -eq 0 ] && grep -q 'the newest sign event for E2E-jbb is decision.recorded .* and not an approve' <<<"$ws_out"; then
  ok "jib0 control: the KEEP'S OWN decision.recorded after its approve still supersedes -- the filter did not blind the fleet to the desk"
else no "jib0 control: a Keep decision.recorded after an approve no longer supersedes" "merged=$ws_merged signed=$ws_signed"; fi
pre_jib0="${FLEET_SH_PRE_JIB0:-}"
if [ -z "$pre_jib0" ] && git -C "$root" cat-file -e be7819b7b:fort/scripts/fleet.sh 2>/dev/null; then
  pre_jib0="$work/pre-jib0-fleet.sh"; git -C "$root" show be7819b7b:fort/scripts/fleet.sh > "$pre_jib0"
fi
if [ -n "$pre_jib0" ] && [ -s "$pre_jib0" ] && ! grep -q 'e.get("actor") != "justin"' "$pre_jib0"; then
  md_case s48ei jbc "$pre_jib0" mayor
  if [ "$ws_merged" = no ] && [ "$ws_signed" -eq 0 ] && grep -q 'the newest sign event for E2E-jbc is decision.recorded' <<<"$ws_out"; then
    ok "RED jib0: the pre-jib0 launcher lets the Mayor's decision.recorded supersede the Keep approve -- so 48e can fail"
  else no "the pre-jib0 launcher did not reproduce jib0" "merged=$ws_merged signed=$ws_signed"; fi
else skip "jib0 inversion" "no pre-jib0 launcher (FLEET_SH_PRE_JIB0, or git show be7819b7b:fort/scripts/fleet.sh)"; fi

# 48d — 1.7: a signed landing whose refresh CONFLICTS is paged, and the page
# names the claimant that actually holds the claim: the fleet actor.
cf_case() { # $1 name, $2 sfx, $3 launcher
  local r st db tip
  IFS='|' read -r r st db <<< "$(run_to_escalate "$1" "$2" "$3")"
  tip="$(git -C "$r" rev-parse "bead/$2")"; keep_approve "$r" "$db" "$2" "\"$tip\""
  printf 'main got here first\n' > "$r/marker-$2.txt"; git -C "$r" add "marker-$2.txt"; git -C "$r" commit -qm "main creates marker-$2.txt"
  run_pass "$work/$1-fleet.sh" "$st" "$db" || true; ws_out=$(cat "$st/out.txt")
  ws_page="$(cat "$st/logs/paged-E2E-$2.txt" 2>/dev/null)"; ws_state="$(wstate "$st/workers/$2")"
}
cf_case s48d ubj "$launcher"
if grep -q 'SIGNED LANDING' <<<"$ws_out" && grep -q 'CONFLICTS with main' <<<"$ws_out" && [ "$ws_state" = needs-person ] \
   && grep -q 'still claimed by the fleet actor' <<<"$ws_page" && ! grep -q 'Forge actor' <<<"$ws_page"; then
  ok "fold 1.7: a signed landing that conflicts on refresh is PAGED and the page says the bead is claimed by the fleet actor"
else no "fold 1.7: the conflict page on a signed landing misnames the claimant" "state=$ws_state
$(grep -E 'claimed by' <<<"$ws_page")"; fi
if [ -n "$pre_fold" ] && [ -s "$pre_fold" ]; then
  cf_case s48di ubn "$pre_fold"
  if [ "$ws_state" = needs-person ] && grep -q 'still claimed by the Forge actor' <<<"$ws_page"; then
    ok "RED 1.7: the pre-fold launcher's page says 'the Forge actor' for a bead the fleet actor claimed -- so 48d can fail"
  else no "the pre-fold launcher did not reproduce 1.7" "state=$ws_state
$(grep -E 'claimed by' <<<"$ws_page")"; fi
else skip "fold 1.7 inversion" "FLEET_SH_PRE_FOLD not set"; fi

echo "=========================================================================="
echo "SCENARIO 49 — Proofdelve ForgeOs-pbkk. THE POST-MERGE VERIFIER REQUIRES DOCKER BY"
echo "             CONSTRUCTION: its run carries VERIFY_REQUIRE_DOCKER=1 and the"
echo "             pre-review run does not"
echo "=========================================================================="
# warden.sh's HOST VERIFY cites the fleet's post-merge verify.pass as
# docker:true (Proofdelve ForgeOs-ehre). The verifier's Docker precheck only WARNS unless
# VERIFY_REQUIRE_DOCKER=1, so the claim held on an assumption (the Warden, B finding
# 5). The stub verifier here records the ENVIRONMENT it was run under, per
# call, and the property is asserted per call site: the post-merge worktree
# run sees the variable set to 1; the bead's pre-review worktree run does not.
pbkk_case() { # $1 name, $2 sfx, $3 launcher -> sets pb_pre pb_post
  local r st db
  r=$(mkfort "$1" ok); unpoison "$r"
  cat > "$r/fort/scripts/verify.sh" <<V
#!/bin/bash
printf '%s|%s\n' "\$PWD" "\${VERIFY_REQUIRE_DOCKER:-unset}" >> "$r/verify-env"
echo "VERIFIER GREEN in \$PWD"; exit 0
V
  git -C "$r" commit -qam 'stub verifier records its environment'
  mk_launcher "$3" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  run_pass "$work/$1-fleet.sh" "$st" "$db" || true; wait_forge "$st" "$2"
  run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  pb_out=$(cat "$st/out.txt")
  pb_pre="$(grep -F -- "-worktrees/$2|" "$r/verify-env" 2>/dev/null | tail -1 | cut -d'|' -f2)"
  pb_post="$(grep -F -- "-worktrees/postmerge-" "$r/verify-env" 2>/dev/null | tail -1 | cut -d'|' -f2)"
}
pbkk_case s49 pbk "$launcher"
if grep -q 'post-merge verifier GREEN' <<<"$pb_out" && [ "$pb_post" = 1 ]; then
  ok "49: the post-merge verifier ran with VERIFY_REQUIRE_DOCKER=1 -- the green warden.sh cites as docker:true means Docker by construction"
else no "49: the post-merge run did not require Docker" "post=[${pb_post:-none}]
$(grep -E 'post-merge|verifier' <<<"$pb_out" | tail -4)"; fi
if [ "$pb_pre" = unset ]; then
  ok "49: the pre-review verifier run is UNCHANGED (VERIFY_REQUIRE_DOCKER unset); the Warden reproduces that one herself"
else no "49: the pre-review run changed" "pre=[${pb_pre:-none}]"; fi
if [ -n "$pre_pbkk" ] && [ -s "$pre_pbkk" ]; then
  pbkk_case s49i pbl "$pre_pbkk"
  if grep -q 'post-merge verifier GREEN' <<<"$pb_out" && [ "$pb_post" = unset ]; then
    ok "RED: the pre-pbkk launcher runs the post-merge verifier with VERIFY_REQUIRE_DOCKER unset -- so 49 can fail"
  else no "the pre-pbkk launcher did not reproduce the gap" "post=[${pb_post:-none}]"; fi
else skip "pbkk inversion" "set FLEET_SH_PRE_PBKK to the launcher before this sitting (git show cb247897:fort/scripts/fleet.sh)"; fi

echo "=========================================================================="
echo "SCENARIO 50 — Proofdelve ForgeOs-fhak. A HALT PLACED WHILE THE RUN IS LIVE: the incident"
echo "             NAMES the Forges still holding launcher locks (measured, not"
echo "             bookkept), names none when none is held, and the halt is seen"
echo "             BEFORE the next claim, not after it"
echo "=========================================================================="
# 50a: exactly one launcher lock is held (a foreign flock with a lock.info
# naming its bead, the shape forge.sh leaves while live). The HALT is placed
# after the first pass has started; the incident must name that bead.
# 50b: the same run shape with NO lock held; the incident must name none and
# say so. A test with only 50b passes on an implementation that prints nothing
# (the bead's own warning), so 50a is the discriminating half.
wait_out() { # $1 state, $2 pattern, $3 tenths -> 0 when out.txt matches
  local i=0; while ! grep -q -- "$2" "$1/out.txt" 2>/dev/null && [ $i -lt "$3" ]; do sleep 0.1; i=$((i+1)); done
  grep -q -- "$2" "$1/out.txt" 2>/dev/null
}
halt_case() { # $1 name, $2 sfx, $3 launcher, $4 hold-lock(yes|no) -> sets hc_out hc_inc hc_rc
  local r st db holder=""
  r=$(mkfort "$1" ok); unpoison "$r"; mk_launcher "$3" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  mkdir -p "$r-worktrees/$2"
  if [ "$4" = yes ]; then
    printf '{"pid":1,"bead":"E2E-%s","model":"stub","started":"now"}' "$2" > "$r-worktrees/$2/.forge.lock.info"
    flock "$r-worktrees/$2/.forge.lock" sleep 60 & holder=$!; sleep 0.3
  fi
  ( FLEET_STATE="$st" BD_STORE="$db" E2E_FORGE_SLEEP=6 timeout 30 "$work/$1-fleet.sh" > "$st/out.txt" 2>&1; echo $? > "$st/rc" ) &
  local runner=$!
  if [ "$4" = yes ]; then wait_out "$st" "skip E2E-$2: a live launcher already holds" 100; else wait_out "$st" "dispatched E2E-$2" 100; fi
  : > "$st/HALT"
  wait "$runner" 2>/dev/null
  [ -n "$holder" ] && { kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; }
  hc_rc="$(cat "$st/rc" 2>/dev/null)"; hc_out="$(cat "$st/out.txt")"
  hc_inc="$(grep 'appeared while it was live' "$r/emitted" | tail -1)"
}
halt_case s50a hla "$launcher" yes
if grep -q 'FORGES STILL RUNNING under this halt' <<<"$hc_inc" && grep -q 'E2E-hla' <<<"$hc_inc" && grep -q '"in_flight":\["E2E-hla"\]' <<<"$hc_inc" \
   && grep -q 'E2E-hla -- the tree is NOT quiet' <<<"$hc_inc" && ! grep -q 'E2E-hla-- ' <<<"$hc_inc" \
   && ! grep -q 'Nothing further was dispatched or merged\.' <<<"$hc_inc"; then
  ok "50a: with one launcher lock held, the halt incident NAMES E2E-hla as still running (from the lock, not the fleet's own workers dir) and drops the idle claim"
else no "50a: the halt incident did not name the live Forge" "rc=$hc_rc inc=$hc_inc
$(grep -E 'HALT|IN FLIGHT|lock' <<<"$hc_out" | tail -5)"; fi
halt_case s50b hlb "$launcher" no
if grep -q 'No Forge lock is held at emit time (measured)' <<<"$hc_inc" && ! grep -q 'E2E-hlb' <<<"$hc_inc" && grep -q '"in_flight":\[\]' <<<"$hc_inc"; then
  ok "50b: with no lock held, the incident names NO bead and says the absence was measured (the negative half; passes vacuously alone, hence 50a)"
else no "50b: the no-lock incident is wrong" "rc=$hc_rc inc=$hc_inc"; fi
# 50c: THE 09-17 14:23:24 SHAPE. Two ready beads; the first's review takes 4s
# and the HALT lands during it. The fixed launcher sees the file at the next
# stopping() -- before the second bead's claim -- so the second stays OPEN and
# unclaimed and the first's merge PARKS ("the run is stopping"). The old
# launcher finishes the review, enters dispatch_pass, CLAIMS the second bead
# and launches its Forge, and only then reads the file.
claim_case() { # $1 name, $2 sfxA, $3 sfxB, $4 launcher -> sets cc_out cc_db cc_inc
  local r st db mark
  r=$(mkfort "$1" ok); unpoison "$r"; mk_launcher "$4" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"; mark="$work/$1.reviewing"
  printf 'E2E-%s|open||fleet-safe\nE2E-%s|open||fleet-safe\n' "$2" "$3" > "$db"
  # serial board: bead B is undeclared, so it waits while A's Forge is live and dispatches once A's branch has landed or been reaped
  run_pass "$work/$1-fleet.sh" "$st" "$db" || true; wait_forge "$st" "$2"
  ( FLEET_STATE="$st" BD_STORE="$db" E2E_WARDEN_MARK="$mark" E2E_WARDEN_SLEEP=4 timeout 30 "$work/$1-fleet.sh" > "$st/out.txt" 2>&1; echo $? > "$st/rc" ) &
  local runner=$!
  local i=0; while [ ! -e "$mark" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done
  : > "$st/HALT"       # placed DURING the review of A
  wait "$runner" 2>/dev/null
  cc_out="$(cat "$st/out.txt")"; cc_db="$(cat "$db")"; cc_inc="$(grep 'appeared while it was live' "$r/emitted" | tail -1)"
}
claim_case s50c hlc hld "$launcher"
if [ -n "$cc_inc" ] && ! grep -q 'dispatched E2E-hld' <<<"$cc_out" && grep -q '^E2E-hld|open|' <<<"$cc_db" \
   && grep -q 'NOT MERGED this pass' <<<"$cc_out" && grep -q 'the run is stopping' <<<"$cc_out"; then
  ok "50c: a HALT placed during A's review is seen BEFORE B's claim -- B stays open and unclaimed, A's merge PARKS as 'the run is stopping', and the incident fires (the 2026-09-17 14:23:24 shape closed)"
else no "50c: the halt was not honoured before the next claim" "inc=${cc_inc:+present} db=$(tr '\n' ' ' <<<"$cc_db")
$(grep -E 'dispatched|HALT|MERGED|stopping' <<<"$cc_out" | tail -6)"; fi
if [ -n "$pre_fhak" ] && [ -s "$pre_fhak" ]; then
  claim_case s50ci hle hlf "$pre_fhak"
  if grep -q 'dispatched E2E-hlf' <<<"$cc_out" && [ -n "$cc_inc" ]; then
    ok "RED 50c: the pre-fhak launcher CLAIMS and dispatches E2E-hlf after the review, then reports the halt -- the 09-17 shape reproduced, so 50c can fail"
  else no "the pre-fhak launcher did not reproduce the late claim" "inc=${cc_inc:+present}
$(grep -E 'dispatched|HALT' <<<"$cc_out" | tail -4)"; fi
  halt_case s50ai hlg "$pre_fhak" yes
  if grep -q 'Nothing further was dispatched or merged\.' <<<"$hc_inc" && ! grep -q 'E2E-hlg' <<<"$hc_inc"; then
    ok "RED 50a: the pre-fhak incident asserts idleness and names no held lock -- so 50a can fail"
  else no "the pre-fhak launcher did not reproduce the unmeasured sentence" "inc=$hc_inc"; fi
else skip "fhak inversions" "set FLEET_SH_PRE_FHAK to the launcher before this sitting (git show cb247897:fort/scripts/fleet.sh)"; fi

echo "=========================================================================="
echo "SCENARIO 51 — Proofdelve ForgeOs-lzvo. THE CEILING IS CARRIED ONCE, AT LOOP EXIT: a run"
echo "             that ends 'budget spent' writes exactly one carry, equal to"
echo "             its final forge_conc"
echo "=========================================================================="
# WHAT THIS DOES AND DOES NOT MEASURE. The Warden's finding 2 (025a52f) reasoned that
# budget_stop(), called mid-pass, carried a value a later governor_down in the
# same pass would make stale. Walked at run level while writing this scenario:
# the reap loop BREAKS at the budget (the feeq gate at its head), and
# dispatch_pass's budget_stop returns into the loop's own break, so no
# governor_down can follow a budget_stop inside one pass -- the stale step is
# unreachable on the shipped launcher, and a fixture built to produce it (two
# finished workers, the second with a 429 in its log, hard stop hit at the
# first) carried 2 on BOTH launchers. So this case pins the INVARIANT the code
# motion preserves (one carry per run, at exit, equal to the final ceiling); the
# RED-before for lzvo is in governor-harness ("budget_stop does NOT write the
# carry file"; "governor_init after the lock"), where the moved call site and
# the moved init are visible.
lzvo_case() { # $1 name, $2 launcher -> sets lz_carry lz_out lz_carries lz_final
  local r st db
  r=$(mkfort "$1" ok); unpoison "$r"
  sed -i 's/^FLEET_FORGE_START=1$/FLEET_FORGE_START=2/; s/^FLEET_HARD_STOP=6$/FLEET_HARD_STOP=2/' "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "conc 2, hard stop 2"
  mk_launcher "$2" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-cza|open||fleet-safe||src/a/\nE2E-czb|open||fleet-safe||src/b/\n' > "$db"
  E2E_FORGE_SLEEP=1 run_loop "$work/$1-fleet.sh" "$st" "$db" 30 || true
  lz_out="$(cat "$st/out.txt")"; lz_carry="$(cut -d'|' -f1 "$st/ceiling.last" 2>/dev/null)"; lz_carries="$(grep -c 'carry forge_conc=' "$st/ceiling.log" 2>/dev/null)"
  lz_final="$(grep -oE 'start forge_conc=[0-9]+|DOWN [0-9]+ -> [0-9]+|UP [0-9]+ -> [0-9]+' "$st/ceiling.log" | tail -1 | grep -oE '[0-9]+$')"
}
lzvo_case s51 "$launcher"
if grep -q 'budget spent' <<<"$lz_out" && [ "$lz_carries" = 1 ] && [ -n "$lz_carry" ] && [ "$lz_carry" = "$lz_final" ]; then
  ok "51: a run ending 'budget spent' (2 launches, hard stop 2) writes exactly ONE carry line, and ceiling.last equals the ceiling the log last reported ($lz_carry)"
else no "51: the carry is not one-per-run or not the final ceiling" "carry=[${lz_carry:-none}] carries=[$lz_carries] final=[${lz_final:-none}]
$(grep -E 'budget|carry|governor' <<<"$lz_out" | tail -5)"; fi
if grep -q 'carry forge_conc=' "$work/s51-state/ceiling.log" && [ "$(grep -n 'carry forge_conc=' "$work/s51-state/ceiling.log" | tail -1 | cut -d: -f1)" = "$(wc -l < "$work/s51-state/ceiling.log")" ]; then
  ok "51: the carry line is the LAST line of the run's ceiling.log -- nothing about the ceiling happens after it (the property 'carried at loop exit')"
else no "51: the carry is not the run's last ceiling event" "$(cat "$work/s51-state/ceiling.log")"; fi

echo "=========================================================================="
echo "SCENARIO 52 — Proofdelve ForgeOs-b26i. A STOPPING RUN SPENDS NO LADDER RUNG: a review"
echo "             that COMPLETED under SIGTERM with a token that will not parse"
echo "             does not launch rung 2 on a two-rung ladder"
echo "=========================================================================="
# Latent while FLEET_WARDEN_LADDER has one rung (fortkit-78o), so the fixture
# configures TWO (criterion 2). TERM lands during rung 1's review; the stub
# completes and records BOGUS; the ke5u fall-through reaches the ordinary
# handling, whose unparseable-token arm says `continue`. The old launcher then
# launched rung 2 while stopping. Criterion 3: the same case on a THREE-rung
# ladder, a correct variant of the configuration, must be green too.
b26i_case() { # $1 name, $2 sfx, $3 launcher, $4 ladder -> sets bi_out bi_state bi_launches bi_pending
  local r st db
  IFS='|' read -r r st db <<< "$(upto_review "$1" "$2" "$3")"
  sed -i "s/^FLEET_WARDEN_LADDER=\"stub\"$/FLEET_WARDEN_LADDER=\"$4\"/" "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "ladder: $4"
  grep -q "^FLEET_WARDEN_LADDER=\"$4\"$" "$r/fort/scripts/fleet.conf" || { echo "HARNESS REFUSES: the ladder substitution did not land" >&2; exit 3; }
  E2E_WARDEN_TOKEN=BOGUS signal_during_review "$1" TERM "$st" "$db" approve
  bi_out=$(cat "$st/out.txt"); bi_state="$(wstate "$st/workers/$2")"
  bi_launches="$(grep -c 'review starting on' <<<"$bi_out")"; bi_pending="$(grep -c 'review.pending' "$r/emitted")"
}
b26i_case s52 rga "$launcher" "stub stub2"
if grep -q 'COMPLETED FIRST and recorded BOGUS' <<<"$bi_out" && grep -q 'token could not be parsed' <<<"$bi_out" \
   && [ "$bi_launches" -eq 1 ] && [ "$bi_pending" -eq 1 ] && [ "$bi_state" = parked-review ] && grep -q 'no rung spent' <<<"$bi_out"; then
  ok "52: under TERM, a completed review whose token will not parse does NOT launch rung 2 -- one review.pending, worker parked-review, 'no rung spent' said"
else no "52: the stopping run spent a rung" "launches=$bi_launches pending=$bi_pending state=$bi_state
$(grep -E 'review starting|parsed|PARKED|rung' <<<"$bi_out" | tail -6)"; fi
b26i_case s52v rgb "$launcher" "stub stub2 stub3"
if [ "$bi_launches" -eq 1 ] && [ "$bi_pending" -eq 1 ] && [ "$bi_state" = parked-review ]; then
  ok "52 (correct variant, 8zb7 step 2): the same case on a THREE-rung ladder still launches exactly one review"
else no "52 variant: three rungs" "launches=$bi_launches pending=$bi_pending state=$bi_state"; fi
if [ -n "$pre_b26i" ] && [ -s "$pre_b26i" ]; then
  b26i_case s52i rgc "$pre_b26i" "stub stub2"
  if [ "$bi_launches" -eq 2 ] && [ "$bi_pending" -eq 2 ] && grep -q 'review starting on stub2, ladder rung 2' <<<"$bi_out"; then
    ok "RED: the pre-b26i launcher launches rung 2 (stub2) after the unparseable verdict under TERM -- the latent defect made live by a second rung, so 52 can fail"
  else no "the pre-b26i launcher did not reproduce the spent rung" "launches=$bi_launches pending=$bi_pending
$(grep -E 'review starting|parsed' <<<"$bi_out" | tail -4)"; fi
else skip "b26i inversion" "set FLEET_SH_PRE_B26I to the launcher before this sitting (git show 5aac33c2:fort/scripts/fleet.sh)"; fi

echo "=========================================================================="
echo "SCENARIO 53 — Proofdelve ForgeOs-uwj5 finding 2. HALT AND HARD-STOP STILL END A RUN"
echo "             WITH A FINISHED WORKER PRESENT: the reason is 'stopped' /"
echo "             'budget spent', never 'drained', and the worker is named"
echo "=========================================================================="
# dx34.18 criterion 3's third must-not-change clause was true because the halt
# check and the budget break sit ABOVE the drain check in the main loop, which
# The Warden verified by reading and no harness pinned. Pinned here by execution.
# 53a: a worker finishes, the HALT file appears before it is reaped: the file
# is placed the moment the Forge's exit file exists, which is inside pass 1's
# FLEET_POLL sleep, so pass 2's reap loop breaks on stopping() before taking it.
# 53b: FLEET_HARD_STOP=1 with two beads: the second worker is finished and
# unreaped when the budget ends the run.
r=$(mkfort s53a ok); unpoison "$r"; mk_launcher "$launcher" "$work/s53a-fleet.sh" "$r" || exit 3
st="$work/s53a-state"; mkdir -p "$st"; db="$work/s53a.bd"
printf 'E2E-uwa|open||fleet-safe\n' > "$db"
( FLEET_STATE="$st" BD_STORE="$db" timeout 30 "$work/s53a-fleet.sh" > "$st/out.txt" 2>&1; echo $? > "$st/rc" ) &
runner=$!
wait_out "$st" "dispatched E2E-uwa" 100; wait_forge "$st" uwa
: > "$st/HALT"
wait "$runner" 2>/dev/null
out="$(cat "$st/out.txt")"; ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
if grep -q '"reason":"stopped: the halt file appeared while the run was live"' <<<"$ended" && ! grep -q '"reason":"drained' <<<"$ended" \
   && grep -q 'E2E-uwa: FINISHED, NOT YET REAPED' <<<"$out" && [ -e "$st/workers/uwa/exit" ] && [ ! -s "$st/workers/uwa/state" ] && [ "$(cat "$st/rc")" = 70 ]; then
  ok "53a: a HALT placed while a Forge is live ends the run 'stopped: the halt file appeared' (rc 70), NOT 'drained', and the leftovers name the finished worker"
else no "53a: HALT with a finished worker" "rc=$(cat "$st/rc" 2>/dev/null) exit=$(cat "$st/workers/uwa/exit" 2>/dev/null) stored-state=[$(head -1 "$st/workers/uwa/state" 2>/dev/null)] ended=$ended
$(grep -E 'FINISHED|HALT|leaves' <<<"$out" | tail -4)"; fi
r=$(mkfort s53b ok); unpoison "$r"
sed -i 's/^FLEET_HARD_STOP=6$/FLEET_HARD_STOP=1/' "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "hard stop 1"
mk_launcher "$launcher" "$work/s53b-fleet.sh" "$r" || exit 3
st="$work/s53b-state"; mkdir -p "$st"; db="$work/s53b.bd"
printf 'E2E-uwb|open||fleet-safe\n' > "$db"
run_loop "$work/s53b-fleet.sh" "$st" "$db" 30; rc=$?; out="$(cat "$st/out.txt")"; ended="$(grep 'fleet.ended' "$r/emitted" | tail -1)"
if grep -q '"reason":"budget spent"' <<<"$ended" && ! grep -q '"reason":"drained' <<<"$ended" \
   && grep -qE 'E2E-uwb: (FINISHED, NOT YET REAPED|PARKED FOR BUDGET)' <<<"$out" && [ "$rc" -eq 0 ]; then
  ok "53b: a spent budget (hard stop 1) ends the run 'budget spent' (rc 0), NOT 'drained', with the finished worker named in the leftovers"
else no "53b: budget with a finished worker" "rc=$rc ended=$ended
$(grep -E 'budget|FINISHED|PARKED|leaves' <<<"$out" | tail -4)"; fi

echo "=========================================================================="
echo "SCENARIO 54 — Proofdelve ForgeOs-lv7x. THE MERGE-PARENT-OPEN WRITE IS REFUSED: the diff"
echo "             is landed, the worker needs a person, an incident is emitted,"
echo "             and fleet.parent-open is NOT"
echo "=========================================================================="
# The branch a2acdbe8 repaired (Proofdelve ForgeOs-stpx: report the write that happened)
# had no control, because the stub bd could not refuse one update selectively
# -- Proofdelve ForgeOs-8zb7 class A, the criticism the same docket levelled one branch
# over. E2E_BD_UPDATE_REFUSE_RMLABEL=fleet-safe refuses exactly that write.
lv7x_case() { # $1 name, $2 sfx, $3 launcher -> sets lv_merged lv_state lv_incident lv_popen lv_db
  local r st db
  r=$(mkfort "$1" ok); mk_launcher "$3" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  E2E_WARDEN_TOKEN=MERGE-PARENT-OPEN run_pass "$work/$1-fleet.sh" "$st" "$db" || true; wait_forge "$st" "$2"
  E2E_WARDEN_TOKEN=MERGE-PARENT-OPEN E2E_BD_UPDATE_REFUSE_RMLABEL=fleet-safe run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  lv_merged="$(merged_in "$r" "$2" && echo yes || echo no)"; lv_state="$(wstate "$st/workers/$2")"
  lv_incident="$(grep -c "incident Fleet merged E2E-$2 on MERGE-PARENT-OPEN and then could NOT set the parent open" "$r/emitted")"
  # the CATEGORY at column one, not the word: the incident's own detail says "no fleet.parent-open was emitted" (grep for the announcement, never for the word)
  lv_popen="$(grep -c '^fleet.parent-open ' "$r/emitted")"; lv_db="$(grep "^E2E-$2|" "$db")"
}
lv7x_case s54 lva "$launcher"
if [ "$lv_merged" = yes ] && [ "$lv_state" = needs-person ] && [ "$lv_incident" -eq 1 ] && [ "$lv_popen" -eq 0 ] && grep -q '|in_progress|{{FORGE_ID}}|fleet-safe' <<<"$lv_db"; then
  ok "54: with the parent-open write refused, the diff is MERGED, the worker is needs-person, one incident names the failed write (bd_exit), fleet.parent-open is NOT emitted, and the bead stays claimed and fleet-safe (the tracker state the incident describes)"
else no "54: the refused parent-open write is misreported" "merged=$lv_merged state=$lv_state incident=$lv_incident parent-open=$lv_popen db=$lv_db"; fi
if [ -n "$pre_lv7x" ] && [ -s "$pre_lv7x" ]; then
  lv7x_case s54i lvb "$pre_lv7x"
  if [ "$lv_merged" = yes ] && [ "$lv_state" = settled ] && [ "$lv_popen" -eq 1 ] && grep -q '|in_progress|{{FORGE_ID}}|fleet-safe' <<<"$lv_db"; then
    ok "RED: the pre-stpx launcher marks the worker settled and emits fleet.parent-open over a write that was refused (the bead is still claimed and fleet-safe) -- so 54 can fail"
  else no "the pre-stpx launcher did not reproduce the unconditional report" "merged=$lv_merged state=$lv_state parent-open=$lv_popen db=$lv_db"; fi
else skip "lv7x inversion" "set FLEET_SH_PRE_LV7X to the launcher before the stpx repair (git show a2acdbe8^:fort/scripts/fleet.sh)"; fi

echo "=========================================================================="
echo "SCENARIO 55 — Proofdelve ForgeOs-s49w, the fleet.sh half. A RUN WRITES ITS OUTCOME"
echo "             RECORD on the ordinary exit path: run, autostart, launches,"
echo "             reason, duration -- what the supervisor's back-off reads"
echo "=========================================================================="
outcome_case() { # $1 name, $2 sfx, $3 launcher -> sets oc_file oc_out
  local r st db
  r=$(mkfort "$1" ok); unpoison "$r"; mk_launcher "$3" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  FLEET_AUTOSTART={{FORT_SLUG}}-fleet-run-FIXTURE E2E_FORGE_SLEEP=1 run_loop "$work/$1-fleet.sh" "$st" "$db" 30 || true
  oc_out="$(cat "$st/out.txt")"; oc_file="$(cat "$st/last-run.outcome" 2>/dev/null)"
}
outcome_case s55 oca "$launcher"
oc_dur="$(grep -m1 '^duration_s=' <<<"$oc_file" | cut -d= -f2)"
if grep -q 'queue drained' <<<"$oc_out" && grep -q '^reason=drained$' <<<"$oc_file" && grep -q '^launches=2$' <<<"$oc_file" \
   && grep -q '^autostart={{FORT_SLUG}}-fleet-run-FIXTURE$' <<<"$oc_file" && [ "$oc_dur" -ge 0 ] 2>/dev/null && grep -q '^run=' <<<"$oc_file"; then
  ok "55: a drained run leaves last-run.outcome with reason=drained, launches=2 (one Forge, one review), the FLEET_AUTOSTART unit it was started under, a run id and a numeric duration ($oc_dur s)"
else no "55: the outcome record is missing or wrong" "file=[$(tr '\n' '|' <<<"$oc_file")]
$(grep -E 'drained|budget' <<<"$oc_out" | tail -2)"; fi
if [ -n "$pre_s49w" ] && [ -s "$pre_s49w" ]; then
  outcome_case s55i ocb "$pre_s49w"
  if grep -q 'queue drained' <<<"$oc_out" && [ -z "$oc_file" ]; then
    ok "RED: the pre-s49w launcher drains and writes NO outcome record -- so 55 can fail"
  else no "the pre-s49w launcher did not reproduce the absent record" "file=[$(tr '\n' '|' <<<"$oc_file")]"; fi
else skip "s49w inversion" "set FLEET_SH_PRE_S49W to the launcher before this sitting (git show 9eb4fb42:fort/scripts/fleet.sh)"; fi

echo "=========================================================================="
echo "SCENARIO 56 — Proofdelve ForgeOs-nz3u. A BEAD THAT DECLARES 'Deliverable: answer' AND"
echo "             whose Forge commits ONLY its handoff is verified, reviewed and"
echo "             LANDS; the same shape undeclared is RETURNED as before (ss9d)"
echo "=========================================================================="
# vky8's own shape (criterion 4): a branch one commit ahead of main, that commit
# the launcher's handoff stamp, nothing outside fort/handoffs/. Two forts, the
# same stub Forge, one bead each; the only difference is the seventh field of
# the tracker line. Criterion 3 side by side: the declared one proceeds, the
# undeclared one returns. Against the pre-nz3u launcher the declared one is
# returned too, which is the inversion.
answer_case() { # $1 name, $2 sfx, $3 launcher, $4 deliverable ("" = undeclared) -> sets an_merged an_state an_out an_db
  local r st db
  r=$(mkfort "$1" ok); unpoison "$r"; mk_launcher "$3" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  if [ -n "$4" ]; then printf 'E2E-%s|open||fleet-safe|||%s\n' "$2" "$4" > "$db"; else printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"; fi
  E2E_FORGE_HANDOFF_ONLY=1 run_pass "$work/$1-fleet.sh" "$st" "$db" || true; wait_forge "$st" "$2"
  E2E_FORGE_HANDOFF_ONLY=1 run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  an_out="$(cat "$st/out.txt")"; an_merged="$(merged_in "$r" "$2" && echo yes || echo no)"; an_state="$(wstate "$st/workers/$2")"; an_db="$(grep "^E2E-$2|" "$db")"
  an_product="$(git -C "$r" diff --name-only "main...bead/$2" -- . ':!fort/handoffs' 2>/dev/null | wc -l)"
}
answer_case s56a dla "$launcher" answer
if [ "$an_product" -eq 0 ] && [ "$an_merged" = yes ] && grep -q "Deliverable: answer" <<<"$an_out" && ! grep -q 'no product change' <<<"$an_out" && grep -q '|closed|' <<<"$an_db"; then
  ok "56: a DECLARED handoff-only bead (0 product paths on its branch) is verified, reviewed, LANDED and closed, and the pass names the declaration"
else no "56: the declared answer did not proceed" "product=$an_product merged=$an_merged state=$an_state db=$an_db
$(grep -E 'Deliverable|no product change|returned' <<<"$an_out" | head -3)"; fi
answer_case s56b dlb "$launcher" ""
# The tracker line is read AFTER the second pass, and that pass re-dispatches the
# returned bead (it is open and ready again), so `|open|` is not the state to
# assert; the return is asserted on the pass's own announcement and the counter.
if [ "$an_product" -eq 0 ] && [ "$an_merged" = no ] && grep -q 'no product change' <<<"$an_out" && grep -q 'returned to ready (1 of' <<<"$an_out" && grep -q 'fleet-return-1' <<<"$an_db"; then
  ok "56 (criterion 3, side by side): the SAME shape UNDECLARED is RETURNED 'no product change' with the return counter spent, never merged (the ss9d guard is not weakened)"
else no "56: the undeclared handoff-only bead was not returned as before" "product=$an_product merged=$an_merged state=$an_state db=$an_db
$(grep -E 'no product change|returned' <<<"$an_out" | head -3)"; fi
answer_case s56c dlc "$launcher" diff
if [ "$an_merged" = no ] && grep -q 'no product change' <<<"$an_out"; then
  ok "56: a bead declaring some OTHER word ('Deliverable: diff') is returned like an undeclared one -- only the literal 'answer' is consulted"
else no "56: a non-answer declaration let a handoff-only bead through" "merged=$an_merged db=$an_db"; fi
if [ -n "$pre_nz3u" ] && [ -s "$pre_nz3u" ]; then
  answer_case s56i dld "$pre_nz3u" answer
  if [ "$an_merged" = no ] && grep -q 'no product change' <<<"$an_out" && grep -q 'fleet-return-1' <<<"$an_db"; then
    ok "RED: the pre-nz3u launcher RETURNS the declared handoff-only bead 'no product change' (vky8's escalation, reproduced) -- so 56 can fail"
  else no "the pre-nz3u launcher did not reproduce the return" "merged=$an_merged db=$an_db"; fi
else skip "nz3u inversion" "set FLEET_SH_PRE_NZ3U to the launcher before this sitting (git show 93594250:fort/scripts/fleet.sh)"; fi

echo
echo "=========================================================================="
echo "SCENARIO 57 — Proofdelve ForgeOs-j3ga. THE PREFLIGHT REFUSAL DISCRIMINATES FOUR HALT"
echo "              FILES: absent, halt()-written, empty, whitespace-only"
echo "=========================================================================="
# THE DEFECT WAS ASYMMETRY, SO THE CASE IS A DISCRIMINATION AND NOT A STRING
# MATCH. `sed 's/^/    /'` prints nothing for a zero-byte file, and `touch` --
# the spelling this launcher's own startup line recommends -- creates exactly
# that, so the refusal told an operator to read a blank record. A change that
# cannot tell a written halt from an empty one has reproduced the defect with
# different words (the bead's criterion 3, in its own terms).
#
# THIS SCENARIO DELIBERATELY ASSERTS NOTHING ABOUT THE STOP PATH. The mid-run
# check, its operator_halt incident and the fleet.ended record were all correct
# on 2026-09-10 and are scenario 50's subject, not this one (criterion 5).
halt_case() { # $1 fixture, $2 sfx, $3 launcher, $4 halt-file content ("" = write nothing, "ABSENT" = no file)
  local rr sst ddb
  rr=$(mkfort "$1" ok); mk_launcher "$3" "$work/$1-fleet.sh" "$rr" || exit 3
  sst="$work/$1-state"; mkdir -p "$sst"; ddb="$work/$1.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$ddb"
  if [ "$4" != ABSENT ]; then printf '%s' "$4" > "$sst/HALT"; fi
  run_pass "$work/$1-fleet.sh" "$sst" "$ddb"; hc_rc=$?
  hc_out=$(cat "$sst/out.txt"); hc_state="$sst"
}
# The specimen is the shape halt() actually writes: a date and a reason on one
# line. Asserting it comes back VERBATIM is what stops this fix from replacing a
# working explanation with a generic one (criterion 2).
hj_written='2026-09-22 09:00 -08:00: HALT: post-merge verifier is RED at deadbeef'

halt_case s57a hj2 "$launcher" "$hj_written"
if [ "$hc_rc" -eq 64 ] && grep -qF "    $hj_written" <<<"$hc_out" \
   && ! grep -q 'carries no reason' <<<"$hc_out" \
   && grep -q 'Read the record, fix what halted it' <<<"$hc_out"; then
  ok "j3ga: a halt()-WRITTEN file still prints its date and reason verbatim, indented, with the original closing line (criterion 2)"
else no "j3ga: the written halt lost or gained an explanation" "rc=$hc_rc
$hc_out"; fi

halt_case s57b hj3 "$launcher" ""
if [ "$hc_rc" -eq 64 ] && grep -q 'this file is EMPTY: it carries no reason at all' <<<"$hc_out" \
   && grep -q 'AN EMPTY HALT FILE MEANS A PERSON PLACED IT' <<<"$hc_out" \
   && grep -q 'grep operator_halt' <<<"$hc_out" \
   && ! grep -q 'Read the record, fix what halted it' <<<"$hc_out"; then
  ok "j3ga: an EMPTY halt file says so, says what an empty file means, and names where the reason lives (criteria 1 and 3)"
else no "j3ga: the empty halt file still explained nothing" "rc=$hc_rc
$hc_out"; fi

# A PERSON'S FILE NEED NOT END IN A NEWLINE, AND halt()'S ALWAYS DOES. The
# fixture above is written with no trailing newline on purpose (printf '%s'),
# so this asserts the reason and the closing instruction land on SEPARATE
# lines. Without the guard, sed reproduces the missing newline faithfully and
# the two run together into one unreadable line -- measured, on the same
# person-written file the whole bead is about.
halt_case s57e hj6 "$launcher" "$hj_written"
if [ "$hc_rc" -eq 64 ] \
   && [ "$(grep -c "^    $hj_written\$" <<<"$hc_out")" -eq 1 ] \
   && grep -q '^  Read the record, fix what halted it' <<<"$hc_out"; then
  ok "j3ga: a person-written halt file with NO trailing newline still prints its reason and the closing instruction on separate lines"
else no "j3ga: the reason ran into the closing line" "rc=$hc_rc
$(printf '%s' "$hc_out" | cat -A | head -6)"; fi

# CRITERION 4. `touch` is the documented spelling, but an interrupted echo or a
# stray newline reaches the same place, and a refusal printing four spaces is
# the same failure. The fixture is deliberately not zero-byte.
halt_case s57c hj4 "$launcher" '   
	
'
if [ "$hc_rc" -eq 64 ] && grep -q 'this file is EMPTY: it carries no reason at all' <<<"$hc_out" \
   && ! grep -q 'Read the record, fix what halted it' <<<"$hc_out"; then
  ok "j3ga: a WHITESPACE-ONLY halt file reads as empty, not as a reason (criterion 4)"
else no "j3ga: whitespace was printed as an explanation" "rc=$hc_rc
$(printf '%s' "$hc_out" | cat -A | head -8)"; fi

# THE THIRD OUTCOME, AND IT IS THE VACUITY CONTROL. Without it the two cases
# above are equally satisfied by a launcher that refuses everything and prints
# both sentences -- the shape this fort keeps paying for. Its own fixture, its
# own tracker: a case whose meaning depends on another case's outcome is not a
# control.
halt_case s57d hj1 "$launcher" ABSENT
if [ "$hc_rc" -ne 64 ] && ! grep -q 'halt file is still present' <<<"$hc_out" \
   && grep -q 'dispatched E2E-hj1' <<<"$hc_out"; then
  ok "VACUITY: with NO halt file the identical fixture starts and dispatches -- the refusal is about the file, not about everything (criterion 3, third outcome)"
else no "j3ga: the no-file control did not start" "rc=$hc_rc
$hc_out"; fi
wait_forge "$hc_state" hj1

if [ -n "$pre_j3ga" ] && [ -s "$pre_j3ga" ]; then
  halt_case s57i hj5 "$pre_j3ga" ""
  # The discriminator is not "the sentence is missing" alone -- it is that the
  # pre-fix launcher prints the refusal header and then NOTHING, so the operator
  # is told to read a record that is blank. Both halves are asserted.
  if [ "$hc_rc" -eq 64 ] && grep -q 'halt file is still present' <<<"$hc_out" \
     && ! grep -q 'carries no reason' <<<"$hc_out" \
     && [ "$(grep -c '^    ' <<<"$hc_out")" -eq 0 ]; then
    ok "RED: the pre-j3ga launcher refuses on the EMPTY file, prints ZERO indented record lines, and still says 'Read the record' -- the defect reproduced, so the cases above can fail"
  else no "the pre-j3ga launcher did not reproduce the blank refusal" "rc=$hc_rc
$hc_out"; fi
else skip "j3ga inversion" "set FLEET_SH_PRE_J3GA to the launcher before this sitting (git show 86b51c37:fort/scripts/fleet.sh)"; fi

echo
echo "=========================================================================="
echo "SCENARIO 58 — Proofdelve ForgeOs-ohsy, the Warden's 1.5. A SIGNED LANDING INTERRUPTED BY"
echo "              Ctrl-C RESUMES AS A LANDING, NOT AS A SECOND REVIEW"
echo "=========================================================================="
# WHY A REAL PTY AND NOT `kill -TERM` (the same reason as scenario 5, from the
# other side). Under TERM bash defers the trap until the foreground command
# returns, so the stub verifier COMPLETES, returns 0, and the bead lands -- the
# path this scenario is not about. Ctrl-C through a pty reaches the whole
# foreground process group, kills the verifier outright, and is the only way to
# reach the arm where run_verifier failed AND signalled is true. That arm wrote
# `finished`, which resumes at verify-then-review: a Warden launch on the
# signed, UNCHANGED change, which on a gate-1 diff must ESCALATE again and
# costs the Overseer a SECOND CLICK on work he has already signed.
ctrlc_during_verify() { # $1 name, $2 state, $3 db
  local mark="$2/verify-started"; rm -f "$mark"
  E2E_VERIFY_MARK="$mark" E2E_VERIFY_SLEEP=5 FLEET_STATE="$2" BD_STORE="$3" \
  python3 - "$work/$1-fleet.sh" "$mark" "$2/out.txt" <<'PYPTY'
import os, pty, sys, time, select
launcher, mark, outp = sys.argv[1], sys.argv[2], sys.argv[3]
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["/bin/bash", launcher, "--once"])
buf = b""; sent = False; t0 = time.time()
while True:
    if not sent and os.path.exists(mark):
        os.write(fd, b"\x03"); sent = True
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try:
            d = os.read(fd, 4096)
        except OSError:
            break
        if not d: break
        buf += d
    if time.time() - t0 > 60: break
    if os.waitpid(pid, os.WNOHANG)[0]:
        try:
            while True:
                d = os.read(fd, 4096)
                if not d: break
                buf += d
        except OSError:
            pass
        break
open(outp, "wb").write(buf)
sys.stderr.write("pty sent-ctrl-c=%s\n" % sent)
PYPTY
  [ -e "$mark" ] || { echo "HARNESS REFUSES: the stub verifier never started in $1, so nothing was interrupted" >&2; exit 3; }
}

IFS='|' read -r r st db <<< "$(run_to_escalate s58a uwc "$launcher")"
tip="$(git -C "$r" rev-parse bead/uwc)"
keep_approve "$r" "$db" uwc "\"$tip\""
pend0="$(pendings "$r")"
ctrlc_during_verify s58a "$st" "$db"
out=$(cat "$st/out.txt")
if [ "$(wstate "$st/workers/uwc")" = parked-signed ] && grep -q 'SIGNED landing' <<<"$out" \
   && ! merged_in "$r" uwc && [ "$(pendings "$r")" -eq "$pend0" ]; then
  ok "ohsy: a signed landing whose verifier is killed by Ctrl-C parks as parked-signed, merges nothing, and spends no review launch"
else no "ohsy: the interrupted signed landing left the wrong state" "state=$(wstate "$st/workers/uwc") merged=$(merged_in "$r" uwc && echo yes || echo no) pendings=$(pendings "$r") (was $pend0)
$(grep -E 'uwc|SIGNED|STOPPED' "$st/out.txt" | tail -6)"; fi
# THE EVIDENCE THE rm -rf USED TO TAKE. Without it the resumed worker is one
# signed_landing_ready() can no longer recognise, whatever the resume point says.
if [ "$(cat "$st/workers/uwc/verdict" 2>/dev/null)" = ESCALATE ]; then
  ok "ohsy: the Warden's stored verdict SURVIVED the landing's worker-dir reset -- the review's evidence is not the landing's to destroy"
else no "ohsy: the stored verdict was destroyed by the landing" "verdict=$(cat "$st/workers/uwc/verdict" 2>/dev/null) files=$(ls "$st/workers/uwc")"; fi
# THE RESUME. It must LAND, and it must land the same way a fresh signed
# landing does: on OVERSEER-SIGNED, with no Forge and no second review.pending.
run_pass "$work/s58a-fleet.sh" "$st" "$db"; rc=$?; out2=$(cat "$st/out.txt")
if merged_in "$r" uwc && grep -q '^E2E-uwc|closed' "$db" && grep -q 'resuming the SIGNED LANDING' <<<"$out2" \
   && [ "$(pendings "$r")" -eq "$pend0" ] && [ "$(dispatched_count "$st")" -eq 0 ] \
   && grep -q '^close E2E-uwc --reason=merged and closed by fort/scripts/fleet.sh on OVERSEER-SIGNED' "$db.calls"; then
  ok "ohsy: the next pass RESUMES THE LANDING -- merged and closed on OVERSEER-SIGNED, no Forge dispatched, review.pending unchanged (no second click)"
else no "ohsy: the parked signed landing did not resume as a landing" "rc=$rc merged=$(merged_in "$r" uwc && echo yes || echo no) pendings=$(pendings "$r") (was $pend0) dispatched=$(dispatched_count "$st")
$(grep -E 'uwc|SIGNED|resuming' <<<"$out2" | tail -6)"; fi

# 58b — THE SAFETY PROPERTY. The resume does not TRUST the park: between the
# signal and the next pass the approval can be superseded. A Decline landing in
# the stream must send the bead back to the ordinary path, not land it.
IFS='|' read -r r st db <<< "$(run_to_escalate s58b uwe "$launcher")"
tip="$(git -C "$r" rev-parse bead/uwe)"
keep_approve "$r" "$db" uwe "\"$tip\""
ctrlc_during_verify s58b "$st" "$db"
if [ "$(wstate "$st/workers/uwe")" = parked-signed ]; then
  printf '{"ts":"%s","actor":"justin","seat":"overseer","category":"gate.declined","target":"E2E-uwe","detail":"declined after the park","payload":{}}\n' \
    "$(date -Is)" >> "$r/fort/events/events-$(date +%F).jsonl"
  run_pass "$work/s58b-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
  if grep -q 'signature no longer covers this tree' <<<"$out" && ! merged_in "$r" uwe \
     && [ "$(wstate "$st/workers/uwe")" = finished ] && ! grep -q 'on OVERSEER-SIGNED' "$db.calls"; then
    ok "ohsy: the resume RE-ASKS the three questions -- an approval superseded while the worker was parked sends it back to the ordinary path and lands nothing on the signature"
  else no "ohsy: the parked worker was landed on a stale signature" "merged=$(merged_in "$r" uwe && echo yes || echo no) state=$(wstate "$st/workers/uwe")
$(grep -E 'uwe|signature|SIGNED' "$st/out.txt" | tail -6)"; fi
else no "ohsy 58b fixture: the interrupt did not park" "state=$(wstate "$st/workers/uwe")"; fi

# 58c — THE RARER HALF the Warden named in the same finding. land() writes the verdict
# token BEFORE anything can defer, so a signed landing whose `git merge` fails
# goes back to the queue carrying OVERSEER-SIGNED -- the fleet's own token. Read
# as "not a signed bead" it took a full FORGE LAP over signed work.
# THE MERGE FAILURE IS REAL, NOT SIMULATED: an untracked file in $root that the
# branch also creates makes `git merge` refuse to overwrite it. It leaves no
# tracked source dirty, so landability still says yes and the merge is genuinely
# reached -- which is the only way to exercise the arm.
IFS='|' read -r r st db <<< "$(run_to_escalate s58c uwf "$launcher")"
tip="$(git -C "$r" rev-parse bead/uwf)"
keep_approve "$r" "$db" uwf "\"$tip\""
printf 'untracked, and the branch creates this path too\n' > "$r/by-uwf.txt"
run_pass "$work/s58c-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
if ! merged_in "$r" uwf && [ "$(cat "$st/workers/uwf/verdict" 2>/dev/null)" = OVERSEER-SIGNED ] \
   && grep -q 'fleet-return-1' "$db"; then
  ok "ohsy 58c fixture: the signed landing's merge FAILED and was aborted, the bead is back in the queue, and its stored verdict is now the fleet's own OVERSEER-SIGNED"
else no "ohsy 58c fixture: the merge did not fail as intended" "merged=$(merged_in "$r" uwf && echo yes || echo no) verdict=$(cat "$st/workers/uwf/verdict" 2>/dev/null) db=$(grep uwf "$db")
$(grep -E 'uwf|merge' "$st/out.txt" | tail -6)"; fi
rm -f "$r/by-uwf.txt"
E2E_FORGE_REUSE=1 run_pass "$work/s58c-fleet.sh" "$st" "$db" || true; out2=$(cat "$st/out.txt")
if merged_in "$r" uwf && grep -q 'SIGNED LANDING' <<<"$out2" && [ "$(dispatched_count "$st")" -eq 0 ] \
   && grep -q '^update E2E-uwf --claim -a fleet ' "$db.calls" \
   && [ "$(grep -c '^update E2E-uwf --claim -a {{FORGE_ID}} ' "$db.calls")" -eq 1 ] \
   && grep -q '^close E2E-uwf --reason=merged and closed by fort/scripts/fleet.sh on OVERSEER-SIGNED' "$db.calls"; then
  ok "ohsy: the returned bead is recognised as signed on the next pass and LANDS -- claimed by the fleet actor, no Forge lap over work the Overseer signed"
else no "ohsy: the returned signed bead took the ordinary path" "merged=$(merged_in "$r" uwf && echo yes || echo no) dispatched=$(dispatched_count "$st") forge_claims=$(grep -c '^update E2E-uwf --claim -a {{FORGE_ID}} ' "$db.calls") (1 = the original dispatch only)
$(grep -E 'uwf|SIGNED|dispatched' <<<"$out2" | tail -6)"; fi

# THE INVERSIONS. Both halves of the finding, against the launcher before it.
if [ -n "$pre_ohsy" ] && [ -s "$pre_ohsy" ]; then
  IFS='|' read -r r st db <<< "$(run_to_escalate s58i uwg "$pre_ohsy")"
  tip="$(git -C "$r" rev-parse bead/uwg)"
  keep_approve "$r" "$db" uwg "\"$tip\""
  pend0="$(pendings "$r")"
  ctrlc_during_verify s58i "$st" "$db"
  st_after="$(wstate "$st/workers/uwg")"
  run_pass "$work/s58i-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
  if [ "$st_after" = finished ] && [ "$(pendings "$r")" -gt "$pend0" ] \
     && ! grep -q 'on OVERSEER-SIGNED' "$db.calls"; then
    ok "RED: the pre-ohsy launcher parks the interrupted signed landing as 'finished' and the next pass spends a SECOND REVIEW LAUNCH on the signed, unchanged change (review.pending $pend0 -> $(pendings "$r")) -- the second click reproduced"
  else no "the pre-ohsy launcher did not reproduce the re-review" "state_after_interrupt=$st_after pendings=$(pendings "$r") (was $pend0)
$(grep -E 'uwg' "$st/out.txt" | tail -6)"; fi

  IFS='|' read -r r st db <<< "$(run_to_escalate s58j uwh "$pre_ohsy")"
  tip="$(git -C "$r" rev-parse bead/uwh)"
  keep_approve "$r" "$db" uwh "\"$tip\""
  printf 'untracked, and the branch creates this path too\n' > "$r/by-uwh.txt"
  run_pass "$work/s58j-fleet.sh" "$st" "$db" || true
  rm -f "$r/by-uwh.txt"
  E2E_FORGE_REUSE=1 run_pass "$work/s58j-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
  wait_forge "$st" uwh
  if grep -q 'dispatched E2E-uwh' <<<"$out" && grep -q '^update E2E-uwh --claim -a {{FORGE_ID}} ' "$db.calls"; then
    ok "RED: the pre-ohsy launcher DISPATCHES A FORGE at the returned signed bead (a claim for {{FORGE_ID}}) -- the rarer half of 1.5 reproduced"
  else no "the pre-ohsy launcher did not reproduce the Forge lap" "dispatched=$(grep -c 'dispatched E2E-uwh' <<<"$out") claims=$(grep '^update E2E-uwh --claim' "$db.calls" | tr '\n' ' ')
$(grep -E 'uwh' "$st/out.txt" | tail -6)"; fi
else skip "ohsy inversions" "set FLEET_SH_PRE_OHSY to the launcher before this item (git show f9fec86c:fort/scripts/fleet.sh)"; fi

echo
echo "=========================================================================="
echo "SCENARIO 59 — Proofdelve ForgeOs-1kak, the Warden's 1.6. A SIGNED BEAD QUEUED BEHIND A LIVE"
echo "              FORGE AT CONCURRENCY 1 LANDS IN THE SAME PASS"
echo "=========================================================================="
# THE BEAD'S OWN NAMED CASE, verbatim: "a signed bead queued behind a live Forge
# at concurrency 1 must land in the same pass". dispatch_pass() returned before
# any signed question when slots <= 0, and `[ n -lt slots ] || break` could end
# the loop before the signed bead was reached -- so at forge_conc 1-2, the
# ceiling this fleet actually runs at, a landing that needs no Forge waited for
# one.
#
# THE FIXTURE HOLDS THE SLOT WITH A REAL DISPATCH, not with a counter: sgb's
# stub Forge sleeps through the next pass, so live_forges() genuinely reports 1
# of 1 and the run genuinely has nothing to dispatch with.
signed_conc_case() {  # $1 name, $2 signed sfx, $3 slow sfx, $4 launcher
  local rr sst ddb ttip
  IFS='|' read -r rr sst ddb <<< "$(run_to_escalate "$1" "$2" "$4")"
  ttip="$(git -C "$rr" rev-parse "bead/$2")"
  printf 'E2E-%s|open||fleet-safe\n' "$3" >> "$ddb"
  # Pass 1: the slow bead takes the only slot. The signed bead is still `human`
  # here, so the approval cannot be what lets it through.
  E2E_FORGE_SLEEP=15 run_pass "$work/$1-fleet.sh" "$sst" "$ddb" || true
  # THE APPROVAL ARRIVES WHILE THE SLOT IS HELD, which is the whole shape.
  keep_approve "$rr" "$ddb" "$2" "\"$ttip\""
  run_pass "$work/$1-fleet.sh" "$sst" "$ddb" || true
  sc_r="$rr"; sc_st="$sst"; sc_db="$ddb"; sc_out="$(cat "$sst/out.txt")"
}

signed_conc_case s59 sga sgb "$launcher"
# `running` IS DERIVED FROM THE FILESYSTEM, NOT STORED, so wstate() -- which
# reads the stored token -- is empty for a live worker and cannot be used here.
# The worker directory with no exit file is the fact; the run's own reap line is
# the corroboration.
if [ -d "$sc_st/workers/sgb" ] && [ ! -e "$sc_st/workers/sgb/exit" ] \
   && grep -q 'E2E-sgb: RUNNING' <<<"$sc_out"; then
  ok "1kak fixture: the slow bead's Forge is LIVE through the pass, so the only slot at concurrency 1 is genuinely held"
else no "1kak fixture: the slot was not held" "worker=$([ -d "$sc_st/workers/sgb" ] && echo present || echo absent) exit=$([ -e "$sc_st/workers/sgb/exit" ] && echo written || echo none)
$(grep -E 'sgb|dispatched|slot' <<<"$sc_out" | tail -5)"; fi
if merged_in "$sc_r" sga && grep -q 'SIGNED LANDING' <<<"$sc_out" \
   && grep -q '^E2E-sga|closed' "$sc_db" && [ "$(dispatched_count "$sc_st")" -eq 0 ] \
   && grep -q '^close E2E-sga --reason=merged and closed by fort/scripts/fleet.sh on OVERSEER-SIGNED' "$sc_db.calls"; then
  ok "1kak: the signed bead LANDED in the same pass with every Forge slot taken -- merged and closed on OVERSEER-SIGNED, nothing dispatched"
else no "1kak: the signed bead waited for a slot it does not use" "merged=$(merged_in "$sc_r" sga && echo yes || echo no) dispatched=$(dispatched_count "$sc_st") db=$(grep sga "$sc_db")
$(grep -E 'sga|SIGNED|slot' <<<"$sc_out" | tail -6)"; fi
wait_forge "$sc_st" sgb

# VACUITY, ON ITS OWN FIXTURE. Without it every assertion above is equally
# satisfied by a launcher that ignores the slot gate altogether, which would be
# a worse bug than the one being fixed: the co-dispatch limit is what keeps two
# Forges off one tree.
r=$(mkfort s59b ok); unpoison "$r"; mk_launcher "$launcher" "$work/s59b-fleet.sh" "$r" || exit 3
st="$work/s59b-state"; mkdir -p "$st"; db="$work/s59b.bd"
printf 'E2E-sgc|open||fleet-safe\nE2E-sgd|open||fleet-safe\n' > "$db"
E2E_FORGE_SLEEP=8 run_pass "$work/s59b-fleet.sh" "$st" "$db" || true
E2E_FORGE_SLEEP=8 run_pass "$work/s59b-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
if [ "$(dispatched_count "$st")" -eq 0 ] && [ -d "$st/workers/sgc" ] && [ ! -e "$st/workers/sgc/exit" ] \
   && [ ! -d "$st/workers/sgd" ]; then
  ok "VACUITY: an ORDINARY bead behind the same live Forge at concurrency 1 is NOT dispatched -- the slot gate still binds everything that needs a slot"
else no "1kak: the slot gate stopped binding ordinary dispatch" "dispatched=$(dispatched_count "$st") sgc_worker=$([ -d "$st/workers/sgc" ] && echo present || echo absent) sgc_exit=$([ -e "$st/workers/sgc/exit" ] && echo written || echo none) sgd_worker=$([ -d "$st/workers/sgd" ] && echo present || echo absent)
$(grep -E 'sgc|sgd|slot' <<<"$out" | tail -5)"; fi
wait_forge "$st" sgc

if [ -n "$pre_1kak" ] && [ -s "$pre_1kak" ]; then
  signed_conc_case s59i sge sgf "$pre_1kak"
  if ! merged_in "$sc_r" sge && ! grep -q 'SIGNED LANDING' <<<"$sc_out" \
     && grep -q '^E2E-sge|open' "$sc_db"; then
    ok "RED: the pre-1kak launcher does NOT land the signed bead while the slot is held -- it returns at the slot gate before the signed question is asked, so the case above can fail"
  else no "the pre-1kak launcher did not reproduce the wait" "merged=$(merged_in "$sc_r" sge && echo yes || echo no) db=$(grep sge "$sc_db")
$(grep -E 'sge|SIGNED|slot' <<<"$sc_out" | tail -6)"; fi
  wait_forge "$sc_st" sgf
else skip "1kak inversion" "set FLEET_SH_PRE_1KAK to the launcher before this item (git show 9e09cabf:fort/scripts/fleet.sh)"; fi

echo
echo "=========================================================================="
echo "SCENARIO 60 — Proofdelve ForgeOs-yz7w, the Warden's 2.3. THE REVIEWED TIP IS THE TIP AT"
echo "              LAUNCH, NOT WHATEVER THE BRANCH IS WHEN THE REVIEW RETURNS"
echo "=========================================================================="
# The Warden's range is main...bead/X and git resolves it when warden.sh runs,
# so the branch she read is the branch AS IT STOOD THEN. The ESCALATE arm used
# to re-resolve bead/X after warden.sh returned and after the bd write. The
# window is small and a HAND is what fits through it -- and a hand moving a bead
# branch is not hypothetical: it is the documented lw8x remedy, a person merging
# main into the branch. Recording the later tip as "the tip she reviewed" would
# make a later signed landing compare the Overseer's approval against a change
# she never saw, and the record would look right.
r=$(mkfort s60 ok); unpoison "$r"; mk_launcher "$launcher" "$work/s60-fleet.sh" "$r" || exit 3
st="$work/s60-state"; mkdir -p "$st"; db="$work/s60.bd"
printf 'E2E-rva|open||fleet-safe\n' > "$db"
E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s60-fleet.sh" "$st" "$db" || true
wait_forge "$st" rva
tip_before="$(git -C "$r" rev-parse bead/rva)"
E2E_WARDEN_TOKEN=ESCALATE E2E_WARDEN_MOVE_BRANCH=1 run_pass "$work/s60-fleet.sh" "$st" "$db" || true
tip_after="$(git -C "$r" rev-parse bead/rva)"
recorded="$(cat "$st/workers/rva/reviewed-sha" 2>/dev/null || echo NONE)"
# THE FIXTURE ASSERTION FIRST: if the branch did not actually move, the case
# below is satisfied by any launcher at all and measures nothing.
if [ "$tip_after" != "$tip_before" ]; then
  ok "yz7w fixture: a hand moved bead/rva WHILE the review was running (${tip_before:0:12} -> ${tip_after:0:12})"
else no "yz7w fixture: the branch did not move, so nothing was measured" "tip=$tip_before"; fi
if [ "$recorded" = "$tip_before" ]; then
  ok "yz7w: the recorded reviewed-sha is the tip the Warden was LAUNCHED on (${tip_before:0:12}), not the tip the branch reached while she worked"
else no "yz7w: the reviewed tip was captured after the review" "recorded=${recorded:0:12} launched_on=${tip_before:0:12} after=${tip_after:0:12}"; fi
# AND THE ORDINARY PATH IS UNTOUCHED: a review nobody interferes with still
# records the tip it reviewed. Its own fixture, because the case above leaves a
# branch that has moved.
r2=$(mkfort s60b ok); unpoison "$r2"; mk_launcher "$launcher" "$work/s60b-fleet.sh" "$r2" || exit 3
st2="$work/s60b-state"; mkdir -p "$st2"; db2="$work/s60b.bd"
printf 'E2E-rvb|open||fleet-safe\n' > "$db2"
E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s60b-fleet.sh" "$st2" "$db2" || true
wait_forge "$st2" rvb
E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s60b-fleet.sh" "$st2" "$db2" || true
if [ "$(cat "$st2/workers/rvb/reviewed-sha" 2>/dev/null)" = "$(git -C "$r2" rev-parse bead/rvb)" ]; then
  ok "VACUITY: with nothing moving the branch, the recorded reviewed-sha still equals the branch tip -- the capture was moved earlier, not switched off"
else no "yz7w: the undisturbed case stopped recording the tip" "recorded=$(cat "$st2/workers/rvb/reviewed-sha" 2>/dev/null) tip=$(git -C "$r2" rev-parse bead/rvb)"; fi

if [ -n "$pre_yz7w" ] && [ -s "$pre_yz7w" ]; then
  r3=$(mkfort s60i ok); unpoison "$r3"; mk_launcher "$pre_yz7w" "$work/s60i-fleet.sh" "$r3" || exit 3
  st3="$work/s60i-state"; mkdir -p "$st3"; db3="$work/s60i.bd"
  printf 'E2E-rvc|open||fleet-safe\n' > "$db3"
  E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s60i-fleet.sh" "$st3" "$db3" || true
  wait_forge "$st3" rvc
  pre_tip="$(git -C "$r3" rev-parse bead/rvc)"
  E2E_WARDEN_TOKEN=ESCALATE E2E_WARDEN_MOVE_BRANCH=1 run_pass "$work/s60i-fleet.sh" "$st3" "$db3" || true
  post_tip="$(git -C "$r3" rev-parse bead/rvc)"
  pre_rec="$(cat "$st3/workers/rvc/reviewed-sha" 2>/dev/null || echo NONE)"
  if [ "$post_tip" != "$pre_tip" ] && [ "$pre_rec" = "$post_tip" ]; then
    ok "RED: the pre-yz7w launcher records the MOVED tip (${post_tip:0:12}) as the tip the Warden reviewed, when she was launched on ${pre_tip:0:12} -- the window reproduced, so the case above can fail"
  else no "the pre-yz7w launcher did not reproduce the late capture" "recorded=${pre_rec:0:12} launched_on=${pre_tip:0:12} after=${post_tip:0:12}"; fi
else skip "yz7w inversion" "set FLEET_SH_PRE_YZ7W to the launcher before this item (git show 5824a861:fort/scripts/fleet.sh)"; fi

echo
echo "=========================================================================="
echo "SCENARIO 61 — Proofdelve ForgeOs-vee4w. A sign-to-land BEAD NEVER LANDS ON A WARDEN"
echo "              VERDICT ALONE; IT LANDS ON THE OVERSEER'S SIGNATURE, DOING"
echo "              WHAT THE WARDEN DECIDED"
echo "=========================================================================="
# Dispatch, then review on token $3; the fixture bead carries sign-to-land
# unless $4 says otherwise. Prints "root|state|db".
run_to_hold() { # $1 name, $2 sfx, $3 Warden token, $4 labels, $5 launcher-src
  local r st db
  r=$(mkfort "$1" ok); unpoison "$r"; mk_launcher "$5" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-%s|open||%s\n' "$2" "$4" > "$db"
  E2E_WARDEN_TOKEN="$3" run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  wait_forge "$st" "$2"
  E2E_WARDEN_TOKEN="$3" run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  printf '%s|%s|%s' "$r" "$st" "$db"
}
# 61a -- APPROVE on a sign-to-land bead is HELD, then lands on the signature.
IFS='|' read -r r st db <<< "$(run_to_hold s61a vka APPROVE fleet-safe,sign-to-land "$launcher")"
tip="$(git -C "$r" rev-parse bead/vka 2>/dev/null)"
if ! merged_in "$r" vka && grep -q '^E2E-vka|open|justin|sign-to-land,human$' "$db" \
   && [ "$(cat "$st/workers/vka/verdict" 2>/dev/null)" = ESCALATE ] && [ "$(cat "$st/workers/vka/warden-verdict" 2>/dev/null)" = APPROVE ] \
   && [ "$(cat "$st/workers/vka/reviewed-sha" 2>/dev/null)" = "$tip" ] \
   && grep -q '^fleet.returned .*"hold":"sign-to-land"' "$r/emitted" && grep -q 'HELD for the Overseer' "$st/out.txt"; then
  ok "vee4w 1: APPROVE on a sign-to-land bead is HELD -- not merged, open/unassigned/human, stored ESCALATE with the Warden's APPROVE and the reviewed tip kept beside it"
else no "vee4w 1: APPROVE landed or was not held" "merged=$(merged_in "$r" vka && echo yes || echo no) db=$(cat "$db") verdict=$(cat "$st/workers/vka/verdict" 2>/dev/null) wv=$(cat "$st/workers/vka/warden-verdict" 2>/dev/null)
$(grep -E 'vka|HELD' "$st/out.txt" | tail -6)"; fi
keep_approve "$r" "$db" vka "\"$tip\""
run_pass "$work/s61a-fleet.sh" "$st" "$db"; rc=$?
if merged_in "$r" vka && grep -q '^E2E-vka|closed' "$db" && grep -q 'SIGNED LANDING' "$st/out.txt" \
   && grep -q '^close E2E-vka --reason=merged and closed by fort/scripts/fleet.sh on OVERSEER-SIGNED' "$db.calls" \
   && [ "$(pendings "$r")" -eq 1 ] && [ "$(dispatched_count "$st")" -eq 0 ]; then
  ok "vee4w 1: signed at its tip, the held bead lands and closes on OVERSEER-SIGNED with no second Forge and no second review"
else no "vee4w 1: the signed landing of the held bead did not happen" "rc=$rc merged=$(merged_in "$r" vka && echo yes || echo no) db=$(cat "$db") pendings=$(pendings "$r")
$(grep -E 'vka|SIGNED' "$st/out.txt" | tail -6)"; fi

# 61b -- APPROVE-WITH-FINDINGS: held, then the signed landing still files the follow-up.
IFS='|' read -r r st db <<< "$(run_to_hold s61b vkb APPROVE-WITH-FINDINGS fleet-safe,sign-to-land "$launcher")"
tip="$(git -C "$r" rev-parse bead/vkb 2>/dev/null)"
held_ok=no; ! merged_in "$r" vkb && grep -q '^E2E-vkb|open|justin|sign-to-land,human$' "$db" && held_ok=yes
keep_approve "$r" "$db" vkb "\"$tip\""
run_pass "$work/s61b-fleet.sh" "$st" "$db" || true
if [ "$held_ok" = yes ] && merged_in "$r" vkb && grep -q '^E2E-vkb|closed' "$db" && grep -q '^create ' "$db.calls" \
   && grep -q '^E2E-fu1|' "$db" && grep -q 'findings carried to E2E-fu1' "$st/workers/vkb/state"; then
  ok "vee4w 2: APPROVE-WITH-FINDINGS is held, and the signed landing still files the Warden's follow-up (findings carried to E2E-fu1)"
else no "vee4w 2: the findings were lost or the bead landed unsigned" "held=$held_ok merged=$(merged_in "$r" vkb && echo yes || echo no) db=$(cat "$db") state=$(head -1 "$st/workers/vkb/state" 2>/dev/null)"; fi

# 61c -- MERGE-PARENT-OPEN: held, then the signed landing merges and leaves the parent OPEN.
IFS='|' read -r r st db <<< "$(run_to_hold s61c vkc MERGE-PARENT-OPEN fleet-safe,sign-to-land "$launcher")"
tip="$(git -C "$r" rev-parse bead/vkc 2>/dev/null)"
held_ok=no; ! merged_in "$r" vkc && grep -q '^E2E-vkc|open|justin|sign-to-land,human$' "$db" && held_ok=yes
keep_approve "$r" "$db" vkc "\"$tip\""
run_pass "$work/s61c-fleet.sh" "$st" "$db" || true
if [ "$held_ok" = yes ] && merged_in "$r" vkc && ! grep -q '^E2E-vkc|closed' "$db" && grep -q '^fleet.parent-open ' "$r/emitted" \
   && ! grep -q '^close E2E-vkc' "$db.calls"; then
  ok "vee4w 3: MERGE-PARENT-OPEN is held, and the signed landing merges and leaves the parent OPEN -- a signature does not turn her 'do not close' into a close"
else no "vee4w 3: the parent was closed or the bead landed unsigned" "held=$held_ok merged=$(merged_in "$r" vkc && echo yes || echo no) db=$(cat "$db") close=$(grep -c '^close E2E-vkc' "$db.calls")"; fi

# 61d -- VACUITY: the identical fixture WITHOUT the label merges on the review pass.
IFS='|' read -r r st db <<< "$(run_to_hold s61d vkd APPROVE fleet-safe "$launcher")"
if merged_in "$r" vkd && grep -q '^E2E-vkd|closed' "$db" && ! grep -q 'HELD for the Overseer' "$st/out.txt"; then
  ok "VACUITY: the same bead without sign-to-land merges and closes on the Warden's APPROVE, so the hold is about the label"
else no "the unlabelled control did not land" "merged=$(merged_in "$r" vkd && echo yes || echo no) db=$(cat "$db")"; fi

# 61e -- FAIL CLOSED: bd will not answer show at the moment of landing.
r=$(mkfort s61e ok); unpoison "$r"; mk_launcher "$launcher" "$work/s61e-fleet.sh" "$r" || exit 3
st="$work/s61e-state"; mkdir -p "$st"; db="$work/s61e.bd"
printf 'E2E-vke|open||fleet-safe,sign-to-land\n' > "$db"
run_pass "$work/s61e-fleet.sh" "$st" "$db" || true; wait_forge "$st" vke
: > "$db.show-null"
run_pass "$work/s61e-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
rm -f "$db.show-null"
if ! merged_in "$r" vke && grep -q 'bd would not say what labels the bead carries' <<<"$out" && [ "$(wstate "$st/workers/vke")" = deferred-merge ]; then
  ok "vee4w fail-closed: when bd will not say what labels the bead carries, nothing merges and the merge is deferred"
else no "vee4w fail-closed: an unreadable bead was merged or not deferred" "merged=$(merged_in "$r" vke && echo yes || echo no) state=$(wstate "$st/workers/vke")
$(grep -E 'vke|NOT MERGED' <<<"$out" | tail -5)"; fi
run_pass "$work/s61e-fleet.sh" "$st" "$db" || true
if ! merged_in "$r" vke && grep -q '^E2E-vke|open|justin|sign-to-land,human$' "$db"; then
  ok "vee4w fail-closed: with bd answering again, the deferred merge resumes INTO the hold, not into a merge"
else no "vee4w fail-closed: the resumed merge landed unsigned" "merged=$(merged_in "$r" vke && echo yes || echo no) db=$(cat "$db")"; fi

# 61f -- RED: the launcher before vee4w merges a sign-to-land bead on MERGE-PARENT-OPEN.
if [ -n "$pre_vee4w" ] && [ -s "$pre_vee4w" ]; then
  IFS='|' read -r r st db <<< "$(run_to_hold s61f vkf MERGE-PARENT-OPEN fleet-safe,sign-to-land "$pre_vee4w")"
  if merged_in "$r" vkf && ! grep -q 'HELD for the Overseer' "$st/out.txt"; then
    ok "RED: the pre-vee4w launcher MERGES a sign-to-land bead on MERGE-PARENT-OPEN with no signature -- the Proofdelve ForgeOs-etmwb miss reproduced, so 61a-c can fail"
  else no "the pre-vee4w launcher did not reproduce the unsigned merge" "merged=$(merged_in "$r" vkf && echo yes || echo no) db=$(cat "$db")"; fi
else skip "vee4w inversion" "set FLEET_SH_PRE_VEE4W to the launcher before this item (git show dae80d8e:fort/scripts/fleet.sh)"; fi

# ROUND TWO, criterion 6 (the Warden's finding 1; the Overseer chose a positive
# marker). These cases switch the stub's default classification OFF, so the
# bead carries exactly the labels its fixture line names.
# 61g -- an UNCLASSIFIED fleet-safe bead is never dispatched.
r=$(mkfort s61g ok); unpoison "$r"; mk_launcher "$launcher" "$work/s61g-fleet.sh" "$r" || exit 3
st="$work/s61g-state"; mkdir -p "$st"; db="$work/s61g.bd"
printf 'E2E-vkg|open||fleet-safe\n' > "$db"
E2E_BD_CLASSIFY=off run_pass "$work/s61g-fleet.sh" "$st" "$db" || true; out=$(cat "$st/out.txt")
if ! grep -q 'dispatched E2E-vkg' <<<"$out" && grep -q 'skip E2E-vkg: unclassified' <<<"$out" \
   && grep -q '^E2E-vkg|open||fleet-safe$' "$db" && ! grep -q '^update E2E-vkg --claim' "$db.calls"; then
  ok "vee4w criterion 6: a fleet-safe bead carrying neither sign-to-land nor lands-on-review is NOT dispatched, the skip names it unclassified, nothing is claimed"
else no "vee4w criterion 6: an unclassified bead was dispatched" "db=$(cat "$db")
$(grep -E 'vkg' <<<"$out" | tail -4)"; fi
# 61h -- a bead that loses its classification after dispatch is HELD at land(),
# classified sign-to-land on the way past, and lands on his signature.
r=$(mkfort s61h ok); unpoison "$r"; mk_launcher "$launcher" "$work/s61h-fleet.sh" "$r" || exit 3
st="$work/s61h-state"; mkdir -p "$st"; db="$work/s61h.bd"
printf 'E2E-vkh|open||fleet-safe\n' > "$db"
run_pass "$work/s61h-fleet.sh" "$st" "$db" || true; wait_forge "$st" vkh
E2E_BD_CLASSIFY=off run_pass "$work/s61h-fleet.sh" "$st" "$db" || true
tip="$(git -C "$r" rev-parse bead/vkh 2>/dev/null)"
if ! merged_in "$r" vkh && grep -q '^E2E-vkh|open|justin|human,sign-to-land$' "$db" && grep -q 'UNCLASSIFIED' "$st/out.txt" \
   && grep -q '"unclassified":true' "$r/emitted"; then
  ok "vee4w criterion 6: an unclassified bead reaching land() on APPROVE is HELD, not merged, and is labelled sign-to-land on the way past"
else no "vee4w criterion 6: an unclassified bead landed at land()" "merged=$(merged_in "$r" vkh && echo yes || echo no) db=$(cat "$db")
$(grep -E 'vkh|HELD' "$st/out.txt" | tail -4)"; fi
keep_approve "$r" "$db" vkh "\"$tip\""
E2E_BD_CLASSIFY=off run_pass "$work/s61h-fleet.sh" "$st" "$db" || true
if merged_in "$r" vkh && grep -q '^E2E-vkh|closed' "$db" && git -C "$r" log -1 --format=%B | grep -q 'Warden verdict APPROVE, HELD by the signature hold' \
   && ! git -C "$r" log -1 --format=%B | grep -q 'Stored Warden verdict ESCALATE'; then
  ok "vee4w: the held bead lands on his signature, and the merge message names the Warden's real verdict (APPROVE), not ESCALATE"
else no "vee4w: the signed landing of the unclassified-then-held bead failed or misrecorded" "merged=$(merged_in "$r" vkh && echo yes || echo no) db=$(cat "$db")
$(git -C "$r" log -1 --format=%B | head -6)"; fi
# 61i -- RED for criterion 6: the round-one launcher dispatches and MERGES the
# unclassified bead on APPROVE.
if [ -n "$pre_vee4w_r2" ] && [ -s "$pre_vee4w_r2" ]; then
  r=$(mkfort s61i ok); unpoison "$r"; mk_launcher "$pre_vee4w_r2" "$work/s61i-fleet.sh" "$r" || exit 3
  st="$work/s61i-state"; mkdir -p "$st"; db="$work/s61i.bd"
  printf 'E2E-vki|open||fleet-safe\n' > "$db"
  E2E_BD_CLASSIFY=off run_pass "$work/s61i-fleet.sh" "$st" "$db" || true; wait_forge "$st" vki
  E2E_BD_CLASSIFY=off run_pass "$work/s61i-fleet.sh" "$st" "$db" || true
  if merged_in "$r" vki; then
    ok "RED: the round-one launcher dispatches and MERGES an unclassified bead on APPROVE -- criterion 6 reproduced, so 61g and 61h can fail"
  else no "the round-one launcher did not reproduce the unclassified merge" "db=$(cat "$db")"; fi
else skip "vee4w round-two inversion" "set FLEET_SH_PRE_VEE4W_R2 to the round-one launcher (git show a1ecc348:fort/scripts/fleet.sh)"; fi
# 61j -- a bead ESCALATED before the marker existed (no classification label)
# lands on his signature: the signed landing skips the classification check
# (the Warden, round two, finding 1). Escalated with the stub's default classification
# on, which the store line does not record; landed with it off.
IFS='|' read -r r st db <<< "$(run_to_escalate s61j vkj "$launcher")"
tip="$(git -C "$r" rev-parse bead/vkj 2>/dev/null)"
keep_approve "$r" "$db" vkj "\"$tip\""
E2E_BD_CLASSIFY=off run_pass "$work/s61j-fleet.sh" "$st" "$db" || true
if grep -q '^E2E-vkj|open||fleet-safe$\|^E2E-vkj|closed' "$db" && merged_in "$r" vkj && grep -q '^E2E-vkj|closed' "$db" && grep -q 'SIGNED LANDING' "$st/out.txt"; then
  ok "vee4w: a bead escalated before the marker, carrying no classification, lands on his signature -- the signed landing skips the classification check"
else no "vee4w: the legacy escalated bead did not land on the signature" "merged=$(merged_in "$r" vkj && echo yes || echo no) db=$(cat "$db")
$(grep -E 'vkj' "$st/out.txt" | tail -4)"; fi
if [ -n "$pre_vee4w_r3" ] && [ -s "$pre_vee4w_r3" ]; then
  IFS='|' read -r r st db <<< "$(run_to_escalate s61k vkk "$pre_vee4w_r3")"
  tip="$(git -C "$r" rev-parse bead/vkk 2>/dev/null)"
  keep_approve "$r" "$db" vkk "\"$tip\""
  E2E_BD_CLASSIFY=off run_pass "$work/s61k-fleet.sh" "$st" "$db" || true
  if ! merged_in "$r" vkk && grep -q 'skip E2E-vkk: unclassified' "$st/out.txt"; then
    ok "RED: the round-two launcher refuses the same signed bead as unclassified -- the Warden's round-two finding 1 reproduced"
  else no "the round-two launcher did not reproduce the refused signed landing" "merged=$(merged_in "$r" vkk && echo yes || echo no)
$(grep -E 'vkk' "$st/out.txt" | tail -4)"; fi
else skip "vee4w round-three inversion" "set FLEET_SH_PRE_VEE4W_R3 to the round-two launcher (git show 2869ad0d:fort/scripts/fleet.sh)"; fi

echo
echo "=========================================================================="
echo "SCENARIO 62 — Proofdelve ForgeOs-ubgx.4. A SIGNED LANDING NEEDS THE KEEP'S OWN RECORD,"
echo "              NOT ONLY A gate.approved IN THE SEAT-WRITABLE STREAM"
echo "=========================================================================="
# 62a -- the forgery: a gate.approved at the tip with no Keep record. Refused,
# with the reason naming the missing record, and nothing dispatched over it.
IFS='|' read -r r st db <<< "$(run_to_escalate s62a kpa "$launcher")"
tip="$(git -C "$r" rev-parse bead/kpa 2>/dev/null)"
stream_only_approve "$r" "$db" kpa "\"$tip\""
run_pass "$work/s62a-fleet.sh" "$st" "$db" || true
if ! merged_in "$r" kpa && ! grep -q '^E2E-kpa|closed' "$db" && grep -q 'no Keep record in the Overseer store pins it' "$st/out.txt"; then
  ok "ubgx.4: a gate.approved in the stream with no Keep record is REFUSED -- not merged, not closed, and the run says the Keep record is missing"
else no "ubgx.4: a stream-only approval landed" "merged=$(merged_in "$r" kpa && echo yes || echo no) db=$(grep kpa "$db")
$(grep -E 'kpa' "$st/out.txt" | tail -4)"; fi
# 62b -- positive control, its own worker, identical except for the pin: the
# stream line AND the Keep's pin line, and it lands. (Not the 62a worker: a
# refused signed landing falls to the ordinary path and that same pass hands
# the bead back to a Forge, so 62a's worker is no longer escalated -- the safe
# direction for a forged approval, and unchanged by this edict.)
IFS='|' read -r r st db <<< "$(run_to_escalate s62b kpd "$launcher")"
tip="$(git -C "$r" rev-parse bead/kpd 2>/dev/null)"
stream_only_approve "$r" "$db" kpd "\"$tip\""; keep_pin kpd "\"$tip\""
run_pass "$work/s62b-fleet.sh" "$st" "$db" || true
if merged_in "$r" kpd && grep -q '^E2E-kpd|closed' "$db" && grep -q 'SIGNED LANDING' "$st/out.txt"; then
  ok "ubgx.4: the same fixture WITH the Keep's pin line naming the same sha LANDS (the refusal in 62a was about the record, nothing else)"
else no "ubgx.4: a Keep-corroborated approval did not land" "merged=$(merged_in "$r" kpd && echo yes || echo no) db=$(grep kpd "$db")
$(grep -E 'kpd' "$st/out.txt" | tail -4)"; fi
# 62d -- a pin for a DIFFERENT sha does not corroborate (a stale record is not this approval)
IFS='|' read -r r st db <<< "$(run_to_escalate s62d kpb "$launcher")"
tip="$(git -C "$r" rev-parse bead/kpb 2>/dev/null)"
stream_only_approve "$r" "$db" kpb "\"$tip\""; keep_pin kpb '"0000000000000000000000000000000000000000"'
run_pass "$work/s62d-fleet.sh" "$st" "$db" || true
if ! merged_in "$r" kpb && grep -q 'no Keep record in the Overseer store pins it' "$st/out.txt"; then
  ok "ubgx.4: a Keep pin naming a different sha does not corroborate the stream's approval"
else no "ubgx.4: a mismatched pin corroborated" "merged=$(merged_in "$r" kpb && echo yes || echo no)"; fi
# 62e -- the Warden's A2: he approved at the tip on the Keep, then DECLINED there; a
# forged newer approve in the stream names the once-approved sha. The Keep's
# newest decision is decline, so nothing lands.
IFS='|' read -r r st db <<< "$(run_to_escalate s62e kpe "$launcher")"
tip="$(git -C "$r" rev-parse bead/kpe 2>/dev/null)"
keep_pin kpe "\"$tip\""; sleep 0.01; keep_decline kpe
stream_only_approve "$r" "$db" kpe "\"$tip\""
run_pass "$work/s62e-fleet.sh" "$st" "$db" || true
if ! merged_in "$r" kpe && grep -q 'NEWEST decision' "$st/out.txt"; then
  ok "ubgx.4 A2: a Decline on the Keep after the approve wins over a forged newer stream approve naming the once-approved sha -- not merged"
else no "ubgx.4 A2: an approval the Keep had overtaken landed" "merged=$(merged_in "$r" kpe && echo yes || echo no)
$(grep -E 'kpe' "$st/out.txt" | tail -4)"; fi
# 62f -- the pre-cutover route: no intent for the bead on any desk, and the
# snapshot carries (bead, sha). It lands; with another sha in the snapshot it would not.
IFS='|' read -r r st db <<< "$(run_to_escalate s62f kpf "$launcher")"
tip="$(git -C "$r" rev-parse bead/kpf 2>/dev/null)"
printf '{"fort":"{{KEEP_ID}}","bead":"E2E-kpf","approvedSha":"%s","source":"fixture snapshot"}\n' "$tip" >> "$XDG_STATE_HOME/civ-keep/legacy-approvals.jsonl"
stream_only_approve "$r" "$db" kpf "\"$tip\""
run_pass "$work/s62f-fleet.sh" "$st" "$db" || true
if merged_in "$r" kpf && grep -q 'SIGNED LANDING' "$st/out.txt"; then
  ok "ubgx.4 cutover: an approval in the pre-cutover snapshot, with no Keep decision since, lands on the stream approval"
else no "ubgx.4 cutover: the snapshot route did not land" "merged=$(merged_in "$r" kpf && echo yes || echo no)
$(grep -E 'kpf' "$st/out.txt" | tail -4)"; fi
# 62c -- RED: the launcher before ubgx.4 lands the stream-only approval.
if [ -n "$pre_ubgx4" ] && [ -s "$pre_ubgx4" ]; then
  IFS='|' read -r r st db <<< "$(run_to_escalate s62c kpc "$pre_ubgx4")"
  tip="$(git -C "$r" rev-parse bead/kpc 2>/dev/null)"
  stream_only_approve "$r" "$db" kpc "\"$tip\""
  run_pass "$work/s62c-fleet.sh" "$st" "$db" || true
  if merged_in "$r" kpc; then
    ok "RED: the launcher before ubgx.4 LANDS an approval only the stream carries -- the forgery route reproduced, so 62a can fail"
  else no "the pre-ubgx.4 launcher did not land the stream-only approval" "db=$(grep kpc "$db")"; fi
else skip "ubgx.4 inversion" "set FLEET_SH_PRE_UBGX4 to the pre-sitting launcher (git show 4d60791c:fort/scripts/fleet.sh)"; fi

echo
echo "=========================================================================="
echo "SCENARIO 63 — Proofdelve ForgeOs-e2rbu, owt37, a13g8. THE RECORDS SAY WHAT HAPPENED,"
echo "              AND EVERY BEAD LEAVING THE FLEET HAS AN OWNER"
echo "=========================================================================="
# The labels the Mayor's session start reads, taken from her seat file's inbox
# query rather than recalled (covenant 8.4's rule for constraint lists).
mayor_inbox="$(grep -m1 -oE 'bd list --label-any [a-z0-9,-]+' "$root/fort/seats/mayor.md" | sed 's/.*--label-any //')"
in_mayor_inbox() { local l; for l in ${2//,/ }; do case ",$mayor_inbox," in *",$l,"*) return 0 ;; esac; done; return 1; }
# 63a -- e2rbu: MERGE-PARENT-OPEN names the next owner.
IFS='|' read -r r st db <<< "$(run_to_hold s63a rda MERGE-PARENT-OPEN fleet-safe "$launcher")"
labels="$(grep '^E2E-rda|' "$db" | cut -d'|' -f4)"
if merged_in "$r" rda && grep -q '^E2E-rda|open||' "$db" && [[ ",$labels," == *,mayor-lane,* ]] && [[ ",$labels," != *,fleet-safe,* ]]; then
  ok "e2rbu 1: MERGE-PARENT-OPEN merges, leaves the parent open and unassigned, removes fleet-safe and ADDS mayor-lane (labels: $labels)"
else no "e2rbu 1: the parent was left with no owner" "merged=$(merged_in "$r" rda && echo yes || echo no) db=$(grep '^E2E-rda|' "$db")"; fi
if [ -n "$mayor_inbox" ] && in_mayor_inbox x "$labels"; then
  ok "e2rbu 2: the parent is in a queue the Mayor's session start reads (fort/seats/mayor.md: --label-any $mayor_inbox)"
else no "e2rbu 2: the parent is in NO queue the Mayor reads at session start" "labels '$labels' vs her inbox '${mayor_inbox:-could not parse}'"; fi
if grep -q '^fleet.parent-open .*mayor-lane' "$r/emitted"; then ok "e2rbu: fleet.parent-open says where the bead went"
else no "e2rbu: fleet.parent-open is silent about the routing" "$(grep '^fleet.parent-open' "$r/emitted" | head -1 | cut -c1-160)"; fi
# 63b -- owt37: a HELD sign-to-land bead with APPROVE-WITH-FINDINGS, signed:
# the follow-up title and bead.closed name the Warden's token.
IFS='|' read -r r st db <<< "$(run_to_hold s63b rdb APPROVE-WITH-FINDINGS fleet-safe,sign-to-land "$launcher")"
tip="$(git -C "$r" rev-parse bead/rdb 2>/dev/null)"; keep_approve "$r" "$db" rdb "\"$tip\""
run_pass "$work/s63b-fleet.sh" "$st" "$db" || true
title="$(grep -m1 '^create .*E2E-rdb' "$db.calls" | grep -oE 'fleet-merged review of E2E-rdb \([^)]*\)')"
closed="$(grep -m1 '^bead.closed .*E2E-rdb' "$r/emitted" | cut -c1-200)"
if merged_in "$r" rdb && grep -q 'APPROVE-WITH-FINDINGS, landed on the Overseer' <<<"$title" && grep -q 'closed E2E-rdb on APPROVE-WITH-FINDINGS, landed on the Overseer' <<<"$closed"; then
  ok "owt37 1: the held AWF bead's signed landing titles its follow-up and announces bead.closed with APPROVE-WITH-FINDINGS, not OVERSEER-SIGNED"
else no "owt37 1: the records still name the route instead of the verdict" "title='$title' closed='$closed'"; fi
# 63c -- owt37: held MERGE-PARENT-OPEN, signed: follow-up title and fleet.parent-open name it.
IFS='|' read -r r st db <<< "$(run_to_hold s63c rdc MERGE-PARENT-OPEN fleet-safe,sign-to-land "$launcher")"
tip="$(git -C "$r" rev-parse bead/rdc 2>/dev/null)"; keep_approve "$r" "$db" rdc "\"$tip\""
run_pass "$work/s63c-fleet.sh" "$st" "$db" || true
title="$(grep -m1 '^create .*E2E-rdc' "$db.calls" | grep -oE 'fleet-merged review of E2E-rdc \([^)]*\)')"
popen="$(grep -m1 '^fleet.parent-open .*E2E-rdc' "$r/emitted" | cut -c1-200)"
if merged_in "$r" rdc && grep -q 'MERGE-PARENT-OPEN, landed on the Overseer' <<<"$title" && grep -q 'E2E-rdc on MERGE-PARENT-OPEN, landed on the Overseer' <<<"$popen"; then
  ok "owt37 2: the held MERGE-PARENT-OPEN bead's signed landing names MERGE-PARENT-OPEN in the follow-up title and fleet.parent-open"
else no "owt37 2: the records still name the route instead of the verdict" "title='$title' parent-open='$popen'"; fi
# 63d -- owt37 criterion 4 / a13g8: an ESCALATE-then-signed landing keeps saying
# OVERSEER-SIGNED (its true route) and fleet.signed announces storedVerdict ESCALATE.
IFS='|' read -r r st db <<< "$(run_to_escalate s63d rdd "$launcher")"
tip="$(git -C "$r" rev-parse bead/rdd 2>/dev/null)"; keep_approve "$r" "$db" rdd "\"$tip\""
run_pass "$work/s63d-fleet.sh" "$st" "$db" || true
if merged_in "$r" rdd && grep -q '^bead.closed .*closed E2E-rdd on OVERSEER-SIGNED' "$r/emitted" && grep -q '^fleet.signed .*E2E-rdd.*"storedVerdict":"ESCALATE"' "$r/emitted"; then
  ok "owt37 4 / a13g8: ESCALATE-then-signed closes on OVERSEER-SIGNED and fleet.signed announces storedVerdict ESCALATE -- unchanged where it was true"
else no "owt37 4 / a13g8: the ESCALATE route's records changed" "$(grep -E '^(bead.closed|fleet.signed) .*E2E-rdd' "$r/emitted" | cut -c1-160)"; fi
# 63e -- a13g8: a signed landing whose merge FAILED comes round with a stored
# OVERSEER-SIGNED; fleet.signed must announce THAT, not the literal ESCALATE.
IFS='|' read -r r st db <<< "$(run_to_escalate s63e rde "$launcher")"
tip="$(git -C "$r" rev-parse bead/rde 2>/dev/null)"; keep_approve "$r" "$db" rde "\"$tip\""
printf 'untracked, and the branch creates this path too\n' > "$r/by-rde.txt"
run_pass "$work/s63e-fleet.sh" "$st" "$db" || true
rm -f "$r/by-rde.txt"
E2E_FORGE_REUSE=1 run_pass "$work/s63e-fleet.sh" "$st" "$db" || true
last_signed="$(grep '^fleet.signed .*E2E-rde' "$r/emitted" | tail -1)"
if merged_in "$r" rde && grep -q '"storedVerdict":"OVERSEER-SIGNED"' <<<"$last_signed" && grep -q 'The stored verdict is OVERSEER-SIGNED' <<<"$last_signed"; then
  ok "a13g8 2: the resumed signed landing announces storedVerdict OVERSEER-SIGNED in payload and prose, and still merges"
else no "a13g8 2: fleet.signed announced a verdict the worker did not have" "merged=$(merged_in "$r" rde && echo yes || echo no) $(printf '%s' "$last_signed" | grep -oE 'storedVerdict[^,]*')"; fi
# 63f -- the churn note: the run records landings for the supervisor.
if grep -q '^landings=1$' "$st/last-run.outcome" 2>/dev/null; then ok "owt37 churn: a run that merged one bead records landings=1 in last-run.outcome"
else no "owt37 churn: landings not recorded" "$(tr '\n' ' ' < "$st/last-run.outcome" 2>/dev/null)"; fi
# 63g -- a13g8 criterion 3, EXECUTED (the Warden D1): a variant of THIS launcher with
# the literal ESCALATE restored in fleet.signed must fail 63e's assertion.
lit="$work/fleet-a13g8-literal.sh"
# shellcheck disable=SC2016  # sed and grep PATTERNS: the $ names the launcher's own variable, literally
sed 's/"storedVerdict\\":\\"\$stored_v\\"/"storedVerdict\\":\\"ESCALATE\\"/; s/The stored verdict is \$stored_v/The stored verdict is ESCALATE/' "$launcher" > "$lit"
# shellcheck disable=SC2016  # a grep PATTERN, literal
if [ "$(grep -c 'stored_v' "$lit")" -lt "$(grep -c 'stored_v' "$launcher")" ] && ! grep -q 'storedVerdict\\":\\"\$stored_v' "$lit"; then
  IFS='|' read -r r st db <<< "$(run_to_escalate s63g rdh "$lit")"
  tip="$(git -C "$r" rev-parse bead/rdh 2>/dev/null)"; keep_approve "$r" "$db" rdh "\"$tip\""
  printf 'untracked, and the branch creates this path too\n' > "$r/by-rdh.txt"
  run_pass "$work/s63g-fleet.sh" "$st" "$db" || true
  rm -f "$r/by-rdh.txt"
  E2E_FORGE_REUSE=1 run_pass "$work/s63g-fleet.sh" "$st" "$db" || true
  last_signed="$(grep '^fleet.signed .*E2E-rdh' "$r/emitted" | tail -1)"
  if merged_in "$r" rdh && grep -q '"storedVerdict":"ESCALATE"' <<<"$last_signed"; then
    ok "RED a13g8: with the literal restored, the resumed landing announces storedVerdict ESCALATE over a stored OVERSEER-SIGNED -- 63e's assertion would fail on it"
  else no "RED a13g8: the literal variant did not reproduce" "$(printf '%s' "$last_signed" | grep -oE 'storedVerdict[^,]*')"; fi
else no "RED a13g8" "the literal-restored variant could not be generated (sed matched nothing)"; fi
# RED arms against the launcher before this item.
if [ -n "$pre_d" ] && [ -s "$pre_d" ]; then
  IFS='|' read -r r st db <<< "$(run_to_hold s63r rdf MERGE-PARENT-OPEN fleet-safe "$pre_d")"
  if grep -q '^E2E-rdf|open||$' "$db"; then ok "RED e2rbu: the pre-D launcher leaves a MERGE-PARENT-OPEN parent with NO label -- in no queue any seat reads"
  else no "RED e2rbu: the pre-D launcher did not reproduce" "$(grep '^E2E-rdf|' "$db")"; fi
  IFS='|' read -r r st db <<< "$(run_to_hold s63s rdg APPROVE-WITH-FINDINGS fleet-safe,sign-to-land "$pre_d")"
  tip="$(git -C "$r" rev-parse bead/rdg 2>/dev/null)"; keep_approve "$r" "$db" rdg "\"$tip\""
  run_pass "$work/s63s-fleet.sh" "$st" "$db" || true
  if grep -q 'fleet-merged review of E2E-rdg (OVERSEER-SIGNED)' "$db.calls"; then ok "RED owt37: the pre-D launcher titles the held AWF follow-up '(OVERSEER-SIGNED)' -- Proofdelve ForgeOs-5rc4g's shape reproduced"
  else no "RED owt37: the pre-D launcher did not reproduce" "$(grep -m1 '^create .*E2E-rdg' "$db.calls" | cut -c1-160)"; fi
else skip "record-defect inversions" "set FLEET_SH_PRE_D to the launcher before item D (git show 74b1382b:fort/scripts/fleet.sh)"; fi

echo "=========================================================================="
echo "SCENARIO 64 — Proofdelve ForgeOs-uwjme. Freed Forge slots refill BETWEEN completion"
echo "              steps; they do not wait for the serial lane to drain."
echo "=========================================================================="
# THE MEASURED DEFECT, AT RUN LEVEL. reap_pass() took every finished worker
# through host verify, review, merge and post-merge verify, and dispatch_pass()
# ran only after the whole lane drained: 93 min of zero dispatch after a hard
# stop (run 20261015T020202) and ~50 min in-run (20261015T091807), with 27 beads
# ready. The fixture is that shape at concurrency 2: two Forges finish, two more
# beads wait, and the property is ORDER IN THE RUN'S OWN LOG -- the third bead
# is dispatched before the SECOND finished bead lands. Today's launcher reaps
# both first and only then dispatches, so 64a is RED against it (64r).
# Disjoint Touches lines, so the touch-set guard is not what serialises them.
uw_fixture() { # $1 name, $2 db lines, [$3 launcher] -> sets r st db
  b9mj_fixture "$1" "$2" "${3:-$launcher}"
  sed -i 's/^FLEET_HARD_STOP=6$/FLEET_HARD_STOP=12/' "$r/fort/scripts/fleet.conf"; git -C "$r" commit -qam "budget 12" >/dev/null
}
uw_line() { grep -n -m1 -F "$2" "$1/out.txt" 2>/dev/null | cut -d: -f1; }   # $1 state, $2 fixed text -> first line number, or nothing
uw_before() { # $1 state, $2 earlier text, $3 later text -> 0 when both appear and the first comes first
  local a b; a="$(uw_line "$1" "$2")"; b="$(uw_line "$1" "$3")"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}
uw_db='E2E-uja|open||fleet-safe||docs/a/\nE2E-ujb|open||fleet-safe||docs/b/\nE2E-ujc|open||fleet-safe||docs/c/\nE2E-ujd|open||fleet-safe||docs/d/\n'
uw_fixture s64a "$uw_db"
run_loop "$work/s64a-fleet.sh" "$st" "$db" 90 || true
if uw_before "$st" '  dispatched E2E-ujc' 'E2E-ujb: merged to main'; then
  ok "uwjme: with two finished workers in the lane and two beads ready, the third bead is dispatched BEFORE the second finished bead lands (line $(uw_line "$st" '  dispatched E2E-ujc') < line $(uw_line "$st" 'E2E-ujb: merged to main'))"
else no "uwjme: dispatch waited for the completion lane to drain" "$(grep -nE 'dispatched E2E|merged to main|refill' "$st/out.txt" | head -12)"; fi
# VACUITY: interleaving must not cost a landing. All four land, each once.
nm=0; for s in uja ujb ujc ujd; do merged_in "$r" "$s" && nm=$((nm + 1)); done
if [ "$nm" -eq 4 ] && [ "$(grep -c 'merged to main' "$st/out.txt")" -eq 4 ]; then
  ok "uwjme: all four beads merged exactly once with dispatch interleaved into the lane"
else no "uwjme: interleaving lost or doubled a landing" "merged=$nm lines=$(grep -c 'merged to main' "$st/out.txt")
$(grep -nE 'dispatched E2E|merged to main|returned|NEEDS' "$st/out.txt" | head -16)"; fi
if grep -q 'refill: [0-9]* Forge slot(s) free before E2E-uja is taken in hand' "$st/out.txt"; then
  ok "uwjme (c): the first refill runs BEFORE the first finished worker is taken in hand, so carried workers no longer hold back dispatch"
else no "uwjme (c): no refill before the first worker was taken in hand" "$(grep -n 'refill' "$st/out.txt" | head -5)"; fi

# 64b THE IN-HAND WORKER HOLDS ITS TOUCH SET. ujg overlaps uje; ujh is disjoint.
# While uje is in the lane its branch has not landed, so ujg must wait for it,
# and ujh must not wait for anything.
uw_db2='E2E-uje|open||fleet-safe||docs/e/\nE2E-ujf|open||fleet-safe||docs/f/\nE2E-ujg|open||fleet-safe||docs/e/x.md\nE2E-ujh|open||fleet-safe||docs/h/\n'
uw_fixture s64b "$uw_db2"
run_loop "$work/s64b-fleet.sh" "$st" "$db" 90 || true
if uw_before "$st" 'E2E-uje: merged to main' '  dispatched E2E-ujg' \
   && uw_before "$st" '  dispatched E2E-ujh' 'E2E-uje: merged to main'; then
  ok "uwjme: an overlapping bead waits until the in-hand worker it overlaps has landed, while a disjoint one dispatches into the lane"
else no "uwjme: the touch-set guard and the refill disagree" "$(grep -nE 'dispatched E2E|merged to main|skip E2E-ujg' "$st/out.txt" | head -12)"; fi
# 64c RED, GENERATED: the same launcher with ONLY the in-hand term removed from
# the touch-set guard must dispatch ujg while uje is still in the lane.
noih="$work/fleet-uwjme-no-inhand.sh"
# shellcheck disable=SC2016  # a sed PATTERN: the $ names the launcher's own text, literally
sed 's/ && \[ "\$(worker_state "\$d")" != in-hand \]; then continue; fi/; then continue; fi/' "$launcher" > "$noih"
# The guard asks only that this launcher HAS a refill: an earlier draft pinned
# the call-site count at 3, and the fold of the Warden's finding 1 removed one site
# correctly and turned this control into a false "could not be generated".
if ! cmp -s "$launcher" "$noih" && grep -q '^refill_slots() {' "$noih"; then
  uw_fixture s64c "$uw_db2" "$noih"
  run_loop "$work/s64c-fleet.sh" "$st" "$db" 90 || true
  if uw_before "$st" '  dispatched E2E-ujg' 'E2E-uje: merged to main'; then
    ok "RED uwjme: without the in-hand term, the overlapping bead is dispatched while the worker it overlaps is still unlanded in the lane -- 64b discriminates"
  else no "RED uwjme: the no-in-hand variant did not reproduce" "$(grep -nE 'dispatched E2E|merged to main' "$st/out.txt" | head -12)"; fi
else no "RED uwjme in-hand" "the no-in-hand variant could not be generated (sed matched nothing, or the launcher has no refill)"; fi
# 64r RED against the launcher before this sitting, derived from git rather than
# asked for, so the verifier runs it too. bd26dbd2 is main when the sitting
# began; the derived file is asserted to carry the defect (no refill) before it
# is believed, because an abbreviated sha resolving elsewhere would make the
# inversion pass for the wrong reason.
pre_uw="${FLEET_SH_PRE_UWJME:-}"
if [ -z "$pre_uw" ]; then
  pre_uw="$work/fleet-pre-uwjme.sh"
  for cand in "$(dirname "$launcher")/../.." "$root" "$PWD"; do
    git -C "$cand" show bd26dbd2:fort/scripts/fleet.sh > "$pre_uw" 2>/dev/null && break
  done
fi
if [ -s "$pre_uw" ] && ! grep -q 'refill_slots' "$pre_uw" && grep -q '^dispatch_pass() {' "$pre_uw"; then
  uw_fixture s64r "$uw_db" "$pre_uw"
  run_loop "$work/s64r-fleet.sh" "$st" "$db" 90 || true
  if uw_before "$st" 'E2E-ujb: merged to main' '  dispatched E2E-ujc'; then
    ok "RED uwjme: the pre-sitting launcher lands BOTH finished workers before it dispatches the third bead -- the serial lane starves dispatch, as measured"
  else no "RED uwjme: the pre-sitting launcher did not reproduce" "$(grep -nE 'dispatched E2E|merged to main' "$st/out.txt" | head -12)"; fi
else skip "uwjme inversion" "could not derive the pre-sitting launcher (git show bd26dbd2:fort/scripts/fleet.sh), or it already has refill_slots"; fi

echo "=========================================================================="
echo "SCENARIO 65 — Proofdelve ForgeOs-asad6 step 2. A launch waits for memory; the wait is"
echo "              not a stall; and a second launch reserves for the first."
echo "=========================================================================="
# The harness exports a GENEROUS FLEET_MEMINFO for every scenario (see the head),
# so the gate never decides an older case on this host's real memory. These
# point it at crafted files instead. The arithmetic lives in the governor
# harness; this is the run-level half: what the run does with a refusal.
mkmem() { printf 'MemTotal: 32673396 kB\nMemAvailable: %s kB\nSwapTotal: 8388604 kB\nSwapFree: 8388604 kB\n' "$2" > "$1"; }
# 65a LOW MEMORY: nothing is claimed, the run keeps polling, and the stall
# detector does not halt it -- memory returns without anyone acting.
b9mj_fixture s65a 'E2E-mga|open||fleet-safe||docs/a/\n'
mkmem "$work/mem-low" 4194304
FLEET_MEMINFO="$work/mem-low" run_loop "$work/s65a-fleet.sh" "$st" "$db" 10; rc=$?
if [ "$rc" -eq 124 ] && ! grep -q '  dispatched E2E-mga' "$st/out.txt" \
   && grep -q 'dispatch waits: memory: MemAvailable 4096 MiB is below the 13312 MiB' "$st/out.txt" \
   && grep -q 'waiting: startable work is held for memory' "$st/out.txt" \
   && [ ! -e "$st/HALT" ] && ! grep -q '^stall [0-9]' <<<"$(sed 's/^[0-9:]*  //' "$st/out.txt")" \
   && [ "$(grep -c '^E2E-mga|open||fleet-safe' "$db")" -eq 1 ]; then
  ok "asad6: at 4 GiB available nothing is claimed or dispatched, the run keeps polling (timeout 124), the wait is said, and the stall detector neither counts nor halts"
else no "asad6: the low-memory run" "rc=$rc halt=$([ -e "$st/HALT" ] && echo yes || echo no)
$(grep -nE 'dispatch|wait|stall|HALT' "$st/out.txt" | head -8)
$(cat "$db")"; fi
# 65b RED, GENERATED: the same launcher with the gate's one call disabled must
# dispatch under the same memory -- so 65a is the gate, not something else.
nogate="$work/fleet-asad6-nogate.sh"
# shellcheck disable=SC2016  # a sed PATTERN: the $ names the launcher's own text, literally
sed 's/if ! memwhy="\$(mem_gate_why)"; then/if false; then/' "$launcher" > "$nogate"
if ! cmp -s "$launcher" "$nogate"; then
  b9mj_fixture s65b 'E2E-mgb|open||fleet-safe||docs/b/\n' "$nogate"
  FLEET_MEMINFO="$work/mem-low" run_pass "$work/s65b-fleet.sh" "$st" "$db" || true
  if grep -q '  dispatched E2E-mgb' "$st/out.txt"; then
    ok "RED asad6: with the gate's call disabled, the same 4 GiB host dispatches -- 65a discriminates"
  else no "RED asad6: the no-gate variant did not dispatch" "$(grep -nE 'dispatch|skip' "$st/out.txt" | head -5)"; fi
  wait_forge "$st" mgb
else no "RED asad6" "the no-gate variant could not be generated (sed matched nothing)"; fi
# 65c THE FIRST LAUNCH RESERVES FOR ITSELF. At ~15 GiB the first launch clears
# (13312 MiB) and the second waits (15872 MiB: the first is now a young Forge),
# in ONE pass at concurrency 2 with disjoint touch sets.
b9mj_fixture s65c 'E2E-mgc|open||fleet-safe||docs/c/\nE2E-mgd|open||fleet-safe||docs/d/\n'
mkmem "$work/mem-15g" 15360000
E2E_FORGE_SLEEP=3 FLEET_MEMINFO="$work/mem-15g" run_pass "$work/s65c-fleet.sh" "$st" "$db" || true
if [ "$(dispatched_count "$st")" -eq 1 ] && grep -q 'dispatch waits: memory: MemAvailable 15000 MiB is below the 15872 MiB' "$st/out.txt"; then
  ok "asad6: at 15000 MiB one Forge dispatches and the second waits, because the first is a young Forge that has not built yet"
else no "asad6: the young-Forge reservation at run level" "dispatched=$(dispatched_count "$st")
$(grep -nE 'dispatch' "$st/out.txt" | head -5)"; fi
wait_forge "$st" mgc

# 65d FOLD of the Warden's finding 2: with two finished workers in the lane and memory
# short, the refills at every step ask the gate again, and the wait is said ONCE
# in that pass, with ONE ceiling.log line.
b9mj_fixture s65d 'E2E-mge|open||fleet-safe||docs/e/\nE2E-mgf|open||fleet-safe||docs/f/\nE2E-mgg|open||fleet-safe||docs/g/\n'
run_pass "$work/s65d-fleet.sh" "$st" "$db" || true
wait_forge "$st" mge; wait_forge "$st" mgf
FLEET_MEMINFO="$work/mem-low" run_pass "$work/s65d-fleet.sh" "$st" "$db" || true
w="$(grep -c 'dispatch waits: memory' "$st/out.txt" || true)"; c="$(grep -c 'MEMGATE refuse' "$st/ceiling.log" 2>/dev/null || true)"
if [ "$(grep -c 'refill:' "$st/out.txt" || true)" -ge 2 ] && [ "$w" -eq 1 ] && [ "$c" -eq 1 ] && ! grep -q '  dispatched E2E-mgg' "$st/out.txt"; then
  ok "9dqa6 fold 2: with the lane refilling at every step and memory short, the wait is said once in the pass and logged once to ceiling.log ($(grep -c 'refill:' "$st/out.txt") refills)"
else no "9dqa6 fold 2: the memory wait repeats within one pass" "refills=$(grep -c 'refill:' "$st/out.txt") waits=$w ceiling=$c
$(grep -nE 'refill|waits|dispatched' "$st/out.txt" | head -8)"; fi

echo "=========================================================================="
echo "SCENARIO 66 — Proofdelve ForgeOs-xu0mj. A NEEDS A PERSON record whose bead is CLOSED"
echo "              is settled; a live one is still said, once per pass."
echo "=========================================================================="
# Two planted workers, both stopped deliberately by an earlier run: xca's bead a
# person has since CLOSED (76uob.3's shape), xcb's is still in progress (2.8's
# shape: a real conflict nobody has answered). Criterion 4 is the first half,
# criterion 5 -- the falsifying arm -- is the second, and without it the first
# is indistinguishable from having broken the warning.
xu_plant() { # $1 state dir, $2 sfx, $3 why
  mkdir -p "$1/workers/$2"; printf 'E2E-%s\n' "$2" > "$1/workers/$2/bead"; printf '0\n' > "$1/workers/$2/exit"
  printf 'needs-person|OLDRUN|%s\n' "$3" > "$1/workers/$2/state"
}
xu_fixture() { # $1 name, [$2 launcher] -> sets r st db
  b9mj_fixture "$1" 'E2E-xca|closed||fleet-safe\nE2E-xcb|in_progress|{{FORGE_ID}}|fleet-safe\n' "${2:-$launcher}"
  xu_plant "$st" xca "the merge STANDS on main and the post-merge verifier is RED"
  xu_plant "$st" xcb "bead/xcb conflicts with main on src/X.cs"
}
xu_fixture s66a
run_pass "$work/s66a-fleet.sh" "$st" "$db" || true; out1=$(cat "$st/out.txt")
run_pass "$work/s66a-fleet.sh" "$st" "$db" || true; out2=$(cat "$st/out.txt")
if [ "$(wstate "$st/workers/xca")" = settled ] && grep -q 'E2E-xca: worker record SETTLED' <<<"$out1" \
   && ! grep -q 'E2E-xca: NEEDS A PERSON' <<<"$out1$out2" && ! grep -q 'E2E-xca' <<<"$out2" \
   && grep -q '^needs-person|OLDRUN|the merge STANDS.*superseded by run' "$st/workers/xca/state-history"; then
  ok "xu0mj 4: a record whose bead is CLOSED is settled once, its old line kept in state-history, and the next full pass says nothing about it at all"
else no "xu0mj 4: the closed bead's record" "state=$(wstate "$st/workers/xca") hist=[$(cat "$st/workers/xca/state-history" 2>/dev/null)]
pass1: $(grep -n 'E2E-xca' <<<"$out1" | head -3)
pass2: $(grep -n 'E2E-xca' <<<"$out2" | head -3)"; fi
# The per-pass WARNING is the line with no indent after the clock; the run's
# closing roll-call (report_leftovers) indents each worker it lists and is said
# once per RUN, so it is counted separately rather than read as a repeat.
xu_warn() { grep -cE '^[0-9:]+  E2E-xcb: NEEDS A PERSON' <<<"$1"; }
xu_roll() { grep -cE '^[0-9:]+    E2E-xcb: NEEDS A PERSON' <<<"$1"; }
if [ "$(wstate "$st/workers/xcb")" = needs-person ] \
   && [ "$(xu_warn "$out1")" -eq 1 ] && [ "$(xu_warn "$out2")" -eq 1 ] \
   && [ "$(xu_roll "$out1")" -eq 1 ] && [ "$(xu_roll "$out2")" -eq 1 ]; then
  ok "xu0mj 5: a record whose bead is still IN PROGRESS keeps its state and is still WARNED -- exactly once per pass in each of two passes, and named in each run's closing roll-call"
else no "xu0mj 5: the live record" "state=$(wstate "$st/workers/xcb") warn=$(xu_warn "$out1")/$(xu_warn "$out2") roll=$(xu_roll "$out1")/$(xu_roll "$out2")
$(grep -n 'E2E-xcb' <<<"$out1" | head -4)"; fi
# 66r RED against the pre-sitting launcher (derived in scenario 64): it warns
# about the closed bead's record on every pass and never settles it.
if [ -s "${pre_uw:-}" ] && ! grep -q 'settle_answered_workers' "$pre_uw"; then
  xu_fixture s66r "$pre_uw"
  run_pass "$work/s66r-fleet.sh" "$st" "$db" || true
  if grep -q 'E2E-xca: NEEDS A PERSON' "$st/out.txt" && [ "$(wstate "$st/workers/xca")" = needs-person ]; then
    ok "RED xu0mj: the pre-sitting launcher still warns NEEDS A PERSON for a bead a person has closed, and leaves the record as it was"
  else no "RED xu0mj: the pre-sitting launcher did not reproduce" "$(grep -n 'E2E-xca' "$st/out.txt" | head -3)"; fi
else skip "xu0mj inversion" "the pre-sitting launcher was not derived in scenario 64"; fi

echo "=========================================================================="
echo "SCENARIO 67 — Proofdelve ForgeOs-s1reg. VERIFY ONCE: a merge whose tree IS the tree"
echo "              the host verify passed (full tier, Docker) runs no second"
echo "              verify; a merge after main moved, or after a Docker-less"
echo "              host verify, runs the post-merge verify as before."
echo "=========================================================================="
# The stub verifier writes VERIFY_RESULT_FILE the way verify-impl.sh does on a
# pass (commit, TREE, tier, docker, clean). $3 = the docker value it reports;
# $4 = 1 to have "the Mayor" commit to main WHILE the host verify runs, which is
# the main-moved case. Every verifier call records where it ran and its tier.
vo_case() { # $1 name, $2 sfx, $3 docker true|false, $4 move 0|1, [$5 launcher] -> sets vo_out vo_post vo_tier vo_r vo_db
  local r st db
  r=$(mkfort "$1" ok); unpoison "$r"
  cat > "$r/fort/scripts/verify.sh" <<V
#!/bin/bash
printf '%s|%s\n' "\$PWD" "\${VERIFY_TIER:-unset}" >> "$r/verify-env"
if [ -n "\${VERIFY_RESULT_FILE:-}" ]; then
  printf '{"result":"pass","tier":"%s","docker":$3,"commit":"%s","tree":"%s","dirtyAtStart":false,"commitAtEnd":"x","dirtyAtEnd":false,"headMoved":false,"skippedSteps":[]}\n' \
    "\${VERIFY_TIER:-full}" "\$(git rev-parse HEAD)" "\$(git rev-parse 'HEAD^{tree}')" > "\$VERIFY_RESULT_FILE"
fi
case "\$PWD" in *-worktrees/postmerge-*) ;; *-worktrees/*)
  if [ "$4" = 1 ]; then echo moved >> "$r/mayor.txt"; git -C "$r" add mayor.txt; git -C "$r" -c user.name=M -c user.email=m@m commit -qm "a Mayor commit while the host verify runs"; fi ;;
esac
echo "VERIFIER GREEN in \$PWD"; exit 0
V
  # A NIGHTLY THAT RAN TWO HOURS AGO (Proofdelve ForgeOs-s1reg finding 3): without one the
  # launcher refuses every reuse, which is 67d's subject and nobody else's.
  if [ -z "${VO_NO_NIGHTLY:-}" ]; then
    printf '{"ts":"%s","actor":"fleet","seat":"fleet","category":"progress","detail":"Nightly full verify GREEN","payload":{"nightly":true,"ran":true,"result":"green"}}\n' \
      "$(date -d '-2 hours' -Iseconds)" > "$r/fort/events/events-$(date -d '-2 hours' +%F).jsonl"
    git -C "$r" add fort/events
  fi
  git -C "$r" commit -qam 'stub verifier writes a result file'
  mk_launcher "${5:-$launcher}" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  run_pass "$work/$1-fleet.sh" "$st" "$db" || true; wait_forge "$st" "$2"
  run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  vo_out=$(cat "$st/out.txt"); vo_r="$r"; vo_db="$db"
  vo_post="$(grep -c -F -- "-worktrees/postmerge-" "$r/verify-env" 2>/dev/null || true)"
  vo_tier="$(grep -F -- "-worktrees/$2|" "$r/verify-env" 2>/dev/null | tail -1 | cut -d'|' -f2)"
}
# 67a THE CASE THAT MUST REUSE.
vo_case s67a vo1 true 0
if merged_in "$vo_r" vo1 && [ "${vo_post:-0}" -eq 0 ] && [ "$vo_tier" = full ] \
   && grep -q 'E2E-vo1: post-merge verify REUSED' <<<"$vo_out" \
   && grep -q '^verify.pass Post-merge verify REUSED at .*"reused":true,"verifiedTree":"[0-9a-f]\{40\}"' "$vo_r/emitted" \
   && grep -q '^E2E-vo1|closed' "$vo_db"; then
  ok "s1reg 1: merged tree == verified tree (full tier, Docker): NO second verify ran, a reused verify.pass names verifiedTree, the bead closed"
else no "s1reg 1: the reuse case" "merged=$(merged_in "$vo_r" vo1 && echo y || echo n) post=$vo_post tier=$vo_tier
$(grep -nE 'post-merge|REUSED|RUNS' <<<"$vo_out" | head -5)
$(grep -n 'REUSED' "$vo_r/emitted" | head -2)"; fi
# 67b MAIN MOVED between the host verify and the merge.
vo_case s67b vo2 true 1
if merged_in "$vo_r" vo2 && [ "${vo_post:-0}" -eq 1 ] \
   && grep -q 'E2E-vo2: post-merge verify RUNS: .*main moved' <<<"$vo_out" \
   && grep -q 'E2E-vo2: post-merge verifier GREEN' <<<"$vo_out" && ! grep -q 'REUSED' "$vo_r/emitted"; then
  ok "s1reg 1: main moved during the host verify: the post-merge verify RAN (once), and the record says why"
else no "s1reg 1: the main-moved case" "merged=$(merged_in "$vo_r" vo2 && echo y || echo n) post=$vo_post
$(grep -nE 'post-merge|REUSED|RUNS' <<<"$vo_out" | head -5)"; fi
# 67c A DOCKER-LESS host verify is never the post-merge pass (the narrowing).
vo_case s67c vo3 false 0
if merged_in "$vo_r" vo3 && [ "${vo_post:-0}" -eq 1 ] && grep -q 'E2E-vo3: post-merge verify RUNS: .*Docker did not run' <<<"$vo_out"; then
  ok "s1reg narrowing: a host verify without Docker is not reused; the post-merge verify ran"
else no "s1reg narrowing" "post=$vo_post $(grep -nE 'post-merge|RUNS' <<<"$vo_out" | head -3)"; fi
# 67d NO NIGHTLY IN THE STREAM (Proofdelve ForgeOs-s1reg finding 3): the same perfect host
# verify as 67a is NOT reused, the post-merge verify runs, and the record says why.
VO_NO_NIGHTLY=1 vo_case s67d vo5 true 0
if merged_in "$vo_r" vo5 && [ "${vo_post:-0}" -eq 1 ] && grep -q 'E2E-vo5: post-merge verify RUNS: .*no nightly backstop: ' <<<"$vo_out" \
   && ! grep -q 'REUSED' "$vo_r/emitted"; then
  ok "s1reg-3: with no nightly that ran, a full Docker host verify is not reused; the post-merge verify ran and the record names the backstop"
else no "s1reg-3: the no-nightly case" "merged=$(merged_in "$vo_r" vo5 && echo y || echo n) post=$vo_post
$(grep -nE 'post-merge|REUSED|RUNS|tier' <<<"$vo_out" | head -5)"; fi
# 67r RED against the launcher before this sitting, derived from git (7fee1a6b
# is main when the sitting began) and asserted to lack the reuse before it is
# believed: it runs the post-merge verify on the 67a fixture.
pre_vo="${FLEET_SH_PRE_S1REG:-}"
if [ -z "$pre_vo" ]; then
  pre_vo="$work/fleet-pre-s1reg.sh"
  for cand in "$(dirname "$launcher")/../.." "$root" "$PWD"; do
    git -C "$cand" show 7fee1a6b:fort/scripts/fleet.sh > "$pre_vo" 2>/dev/null && break
  done
fi
if [ -s "$pre_vo" ] && ! grep -q 'verified_reusable' "$pre_vo" && grep -q '^land() {' "$pre_vo"; then
  vo_case s67r vo4 true 0 "$pre_vo"
  if merged_in "$vo_r" vo4 && [ "${vo_post:-0}" -eq 1 ]; then
    ok "RED s1reg: the pre-sitting launcher runs a second, post-merge verify of the identical tree -- 67a discriminates"
  else no "RED s1reg: the pre-sitting launcher did not reproduce" "post=$vo_post"; fi
else skip "s1reg inversion" "could not derive the pre-sitting launcher (git show 7fee1a6b:fort/scripts/fleet.sh), or it already has verified_reusable"; fi

echo "=========================================================================="
echo "SCENARIO 68 — Proofdelve ForgeOs-29j3g. WHOSE MOVE = THE ASSIGNEE: an ESCALATE and a"
echo "              signature hold are ASSIGNED to the Overseer with one ASK line;"
echo "              his Approve hands the bead back to the fleet, which lands it."
echo "=========================================================================="
IFS='|' read -r r st db <<< "$(run_to_escalate s68a aj1 "$launcher")"
if grep -q '^E2E-aj1|open|justin|human$' "$db" && grep -q '^ASK: sign -- the Warden returned ESCALATE' "$db.comments"; then
  ok "29j3g: an ESCALATE leaves the bead assigned to justin with ONE ASK line saying what he is asked"
else no "29j3g: the ESCALATE hand-off" "db=$(grep aj1 "$db") asks=$(cat "$db.comments" 2>/dev/null)"; fi
tip="$(git -C "$r" rev-parse bead/aj1)"
keep_approve "$r" "$db" aj1 "\"$tip\""
run_pass "$work/s68a-fleet.sh" "$st" "$db" || true
if merged_in "$r" aj1 && grep -q '^E2E-aj1|closed' "$db"; then
  ok "29j3g: after his Approve (assignee cleared, fleet-safe back) the signed landing claims and lands it -- the dispatch path is unchanged for an unassigned fleet-safe bead"
else no "29j3g: the approved bead did not land" "db=$(grep aj1 "$db") $(grep -E 'aj1|SIGNED|skip' "$st/out.txt" | tail -4)"; fi
IFS='|' read -r r st db <<< "$(run_to_hold s68b aj2 APPROVE fleet-safe,sign-to-land "$launcher")"
if grep -q '^E2E-aj2|open|justin|sign-to-land,human$' "$db" && grep -q '^ASK: sign -- the Warden returned APPROVE and it carries sign-to-land' "$db.comments"; then
  ok "29j3g: a signature hold leaves the bead assigned to justin with an ASK line naming the Warden's verdict"
else no "29j3g: the hold hand-off" "db=$(grep aj2 "$db") asks=$(cat "$db.comments" 2>/dev/null)"; fi
# RED, GENERATED: the same launcher with the ESCALATE write's assignee blanked
# leaves the bead unassigned -- off his board -- so 68a's first case discriminates.
noassign="$work/fleet-29j3g-noassign.sh"
# shellcheck disable=SC2016  # a sed PATTERN: the $ names the launcher's own text, literally
sed 's/--status open --assignee "$(overseer_assignee)" --actor "$fleet_actor" >\/dev\/null 2>&1 || erc=\$?/--status open --assignee "" --actor "$fleet_actor" >\/dev\/null 2>\&1 || erc=$?/' "$launcher" > "$noassign"
if ! cmp -s "$launcher" "$noassign"; then
  IFS='|' read -r r st db <<< "$(run_to_escalate s68r aj3 "$noassign")"
  if grep -q '^E2E-aj3|open||human$' "$db"; then
    ok "RED 29j3g: with the assignee blanked the escalated bead is unassigned -- not on his board -- so 68a discriminates"
  else no "RED 29j3g: the blanked variant did not reproduce" "db=$(grep aj3 "$db")"; fi
else no "RED 29j3g" "the blanked variant could not be generated (sed matched nothing)"; fi

echo
echo "=========================================================================="
echo "SCENARIO 69 — Proofdelve ForgeOs-jfqu4.7. A SIGNED LANDING GOES FIRST IN THE PASS:"
echo "              it lands before the completion lane verifies a finished bead."
echo "=========================================================================="
# Measured 2026-10-21: two beads the Overseer signed at 10:04 had not landed by
# 11:2x, because phase 1 ran only in the full dispatch pass AFTER reap_pass, and
# reap_pass spent the hour on the completion lane. Fixture: sg1 escalated and
# then approved; sg2 a second bead whose Forge has FINISHED (unreaped). One pass:
# the SIGNED LANDING line for sg1 must come before the host-verifier line for sg2.
sg_order() { # $1 name, $2 launcher-src, $3 sfx-signed, $4 sfx-finished -> "signed-first" | "lane-first" | "missing: ..."
  local r st db tip out ls lv
  IFS='|' read -r r st db <<< "$(run_to_escalate "$1" "$3" "$2")"
  printf 'E2E-%s|open||fleet-safe\n' "$4" >> "$db"
  E2E_FORGE_SLEEP=0 run_pass "$work/$1-fleet.sh" "$st" "$db" || true
  wait_forge "$st" "$4"
  tip="$(git -C "$r" rev-parse "bead/$3")"
  keep_approve "$r" "$db" "$3" "\"$tip\""
  run_pass "$work/$1-fleet.sh" "$st" "$db" || true; out="$(cat "$st/out.txt")"
  ls="$(grep -n "E2E-$3: SIGNED LANDING" <<<"$out" | head -1 | cut -d: -f1)"
  lv="$(grep -n "E2E-$4: running the host verifier" <<<"$out" | head -1 | cut -d: -f1)"
  if [ -z "$ls" ] || [ -z "$lv" ]; then printf 'missing: signed-line=%s verify-line=%s | %s' "${ls:-none}" "${lv:-none}" "$(grep -E "$3|$4" <<<"$out" | tail -5 | tr '\n' '|')"; return; fi
  if [ "$ls" -lt "$lv" ]; then echo signed-first; else echo lane-first; fi
}
got="$(sg_order s69a "$launcher" sg1 sg2)"
if [ "$got" = signed-first ]; then ok "jfqu4.7: a signed landing lands at the TOP of the pass, before the completion lane verifies a finished bead"
else no "jfqu4.7: signed landing first in the pass" "$got"; fi
# RED, GENERATED: drop the signed-first call and phase 1 runs only at the foot.
nosigned="$work/fleet-jfqu47-nosigned.sh"
sed '/^  in_dispatch=1; dispatch_pass signed; in_dispatch=0$/d' "$launcher" > "$nosigned"
if ! cmp -s "$launcher" "$nosigned"; then
  got="$(sg_order s69r "$nosigned" sg3 sg4)"
  if [ "$got" = lane-first ]; then ok "RED jfqu4.7: without the signed-first call the lane verifies the finished bead before the signed one lands -- 69a discriminates"
  else no "RED jfqu4.7: the variant did not reproduce lane-first" "$got"; fi
else no "RED jfqu4.7" "the no-signed-first variant could not be generated (sed matched nothing)"; fi

echo
echo "=========================================================================="
echo "SCENARIO 70 — Proofdelve ForgeOs-0x25g (a). A DECLINE AFTER ESCALATE, RE-RELEASED"
echo "              WITHOUT A LAP, IS HANDED TO THE MAYOR ONCE, NOT LOOPED ON."
echo "=========================================================================="
# Measured 2026-10-20 on Proofdelve ForgeOs-2md9d.4.49.2: Decline, relabel fleet-safe, and
# "taking the ordinary path" every pass for twenty minutes. Fixture: ESCALATE,
# Approve at the tip, then a Decline in the stream, then the Mayor's relabel.
decl_fixture() { # $1 name, $2 sfx, $3 launcher-src -> "root|state|db" after the relabel
  local r st db tip
  IFS='|' read -r r st db <<< "$(run_to_escalate "$1" "$2" "$3")"
  tip="$(git -C "$r" rev-parse "bead/$2")"; keep_approve "$r" "$db" "$2" "\"$tip\""
  sleep 1
  printf '{"ts":"%s","actor":"justin","seat":"overseer","category":"gate.declined","target":"E2E-%s","detail":"declined: not this","payload":{}}\n' \
    "$(date -Is)" "$2" >> "$r/fort/events/events-$(date +%F).jsonl"
  BD_STORE="$db" bd update "E2E-$2" --remove-label human >/dev/null
  BD_STORE="$db" bd update "E2E-$2" --assignee "" >/dev/null
  # The stub's labels are a list, not a set, and keep_approve already added
  # fleet-safe: take it off first so the relabel leaves exactly one.
  BD_STORE="$db" bd update "E2E-$2" --remove-label fleet-safe >/dev/null
  BD_STORE="$db" bd update "E2E-$2" --add-label fleet-safe >/dev/null
  printf '%s|%s|%s' "$r" "$st" "$db"
}
IFS='|' read -r r st db <<< "$(decl_fixture s70a dc1 "$launcher")"
run_pass "$work/s70a-fleet.sh" "$st" "$db" || true; out="$(cat "$st/out.txt")"
rec="$(grep '^E2E-dc1|' "$db")"
if grep -q 'E2E-dc1: DECLINED by the Overseer after ESCALATE and NOT landable on the signature (.*gate.declined' <<<"$out" && ! merged_in "$r" dc1 \
   && grep -q '|{{MAYOR_ID}}|' <<<"$rec" && grep -q 'fleet-escalated' <<<"$rec" && ! grep -q 'fleet-safe' <<<"$rec" \
   && [ "$(dispatched_count "$st")" -eq 0 ] && grep -q 'File a LAP bead carrying the Decline note' "$db.comments"; then
  ok "0x25g: a Declined ESCALATE bead re-released without a lap is NOT dispatched or landed; fleet-safe comes off, it goes to the Mayor with a comment saying to file a lap"
else no "0x25g: the Decline guard" "rec=$rec dispatched=$(dispatched_count "$st") $(grep -E 'dc1' <<<"$out" | tail -4 | tr '\n' '|')"; fi
run_pass "$work/s70a-fleet.sh" "$st" "$db" || true
if ! grep -q 'E2E-dc1' "$st/out.txt"; then ok "0x25g: said ONCE -- the next pass does not mention the bead at all (no loop)"
else no "0x25g: the bead is still being looped on" "$(grep dc1 "$st/out.txt" | tail -3 | tr '\n' '|')"; fi
# RED, GENERATED: without the guard the same fixture loops on the ordinary path.
noguard="$work/fleet-0x25g-noguard.sh"
# shellcheck disable=SC2016  # a sed PATTERN: the $ names the launcher's own text
sed 's/^    if \[ "\$signed_rc2" -eq 1 \] && \[ "\${signed_superseded_by%% \*}" = gate.declined \]; then$/    if false; then/' "$launcher" > "$noguard"
if ! cmp -s "$launcher" "$noguard"; then
  IFS='|' read -r r st db <<< "$(decl_fixture s70r dc2 "$noguard")"
  run_pass "$work/s70r-fleet.sh" "$st" "$db" || true
  if grep -q 'E2E-dc2: escalated and signed but NOT landable' "$st/out.txt" && grep -q 'fleet-safe' <<<"$(grep '^E2E-dc2|' "$db")"; then
    ok "RED 0x25g: without the guard the declined bead stays fleet-safe and takes 'the ordinary path' -- the 4.49.2 loop, so 70a discriminates"
  else no "RED 0x25g: the no-guard variant did not reproduce the loop" "$(grep dc2 "$st/out.txt" | tail -3 | tr '\n' '|') rec=$(grep '^E2E-dc2|' "$db")"; fi
else no "RED 0x25g" "the no-guard variant could not be generated (sed matched nothing)"; fi

echo
echo "=========================================================================="
echo "SCENARIO 71 — Proofdelve ForgeOs-9srgz A4. fleet.sh --review-only: a Workbench session"
echo "             branch, built by no Forge, gets host verify, ONE Warden launch at"
echo "             the front of the reap order, and merge or escalate; findings go"
echo "             back to the Workbench ({{WORKBENCH_ID}}), never to a Forge"
echo "=========================================================================="
wb_fixture() { # $1 name, $2 sfx, $3 launcher-src, $4 labels -> "root|state|db"
  local r st db
  r=$(mkfort "$1" ok); unpoison "$r"; mk_launcher "$3" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  git -C "$r" worktree add -q "$r-worktrees/$2" -b "bead/$2" >/dev/null 2>&1
  printf 'workbench sitting line for %s\n' "$2" > "$r-worktrees/$2/wb-$2.txt"
  git -C "$r-worktrees/$2" add -A >/dev/null; git -C "$r-worktrees/$2" commit -qm "E2E-$2: the sitting's work"
  printf 'E2E-%s|in_progress|{{WORKBENCH_ID}}|%s\n' "$2" "$4" > "$db"
  printf '%s|%s|%s' "$r" "$st" "$db"
}
enqueue() { # $1 launcher copy, $2 state, $3 db, $4 bead -> rc; output in $2/enq.txt
  FLEET_STATE="$2" BD_STORE="$3" "$1" --review-only "$4" > "$2/enq.txt" 2>&1
}
# 71a -- APPROVE: merged and closed, no claim, no Forge.
IFS='|' read -r r st db <<< "$(wb_fixture s71a wba "$launcher" workbench)"
enqueue "$work/s71a-fleet.sh" "$st" "$db" E2E-wba; erc=$?
if [ "$erc" -eq 0 ] && [ -e "$st/workers/wba/review-only" ] && [ "$(cat "$st/workers/wba/exit" 2>/dev/null)" = 0 ] \
   && grep -q '^fleet.handed .*"review_only":true' "$r/emitted"; then
  ok "9srgz A4: --review-only queues a worker record (review-only marker, exit 0) and emits fleet.handed"
else no "9srgz A4: enqueue" "rc=$erc $(cat "$st/enq.txt") files=$(find "$st/workers/wba" -maxdepth 1 -printf "%f ")"; fi
run_pass "$work/s71a-fleet.sh" "$st" "$db" || true
if merged_in "$r" wba && grep -q '^E2E-wba|closed' "$db" && ! grep -q '^update E2E-wba --claim' "$db.calls" \
   && ! grep -q 'dispatched E2E-wba' "$st/out.txt" && [ ! -e "$st/workers/wba/forge.log" ] \
   && grep -q 'E2E-wba: a Workbench session branch queued for ONE review' "$st/out.txt" \
   && grep -q -- "-worktrees/wba" "$r/verify-calls" && grep -q '^E2E-wba ' "$r/warden-ranges"; then
  ok "9srgz A4 approve: host verify in the session worktree, one Warden review, merged and closed; never claimed, never dispatched to a Forge"
else no "9srgz A4 approve" "merged=$(merged_in "$r" wba && echo yes || echo no) rec=$(grep '^E2E-wba|' "$db") $(grep -E 'wba' "$st/out.txt" | tail -5 | tr '\n' '|')"; fi
# 71b -- ESCALATE: held for the Overseer like any bead.
IFS='|' read -r r st db <<< "$(wb_fixture s71b wbe "$launcher" workbench)"
enqueue "$work/s71b-fleet.sh" "$st" "$db" E2E-wbe >/dev/null
E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s71b-fleet.sh" "$st" "$db" || true
if ! merged_in "$r" wbe && grep -q '^E2E-wbe|open|justin|' "$db" && [ "$(cat "$st/workers/wbe/verdict" 2>/dev/null)" = ESCALATE ]; then
  ok "9srgz A4 escalate: the session branch is HELD for the Overseer (not merged, assigned justin, ESCALATE stored)"
else no "9srgz A4 escalate" "merged=$(merged_in "$r" wbe && echo yes || echo no) rec=$(grep '^E2E-wbe|' "$db") $(grep -E 'wbe' "$st/out.txt" | tail -4 | tr '\n' '|')"; fi
# 71c -- REQUEST-CHANGES: back to {{WORKBENCH_ID}}, fleet-safe off, no return counter, never a Forge.
rc_case() { # $1 name, $2 sfx, $3 launcher -> sets rcr rcst rcdb
  IFS='|' read -r rcr rcst rcdb <<< "$(wb_fixture "$1" "$2" "$3" workbench,fleet-safe)"
  enqueue "$work/$1-fleet.sh" "$rcst" "$rcdb" "E2E-$2" >/dev/null
  E2E_WARDEN_TOKEN=REQUEST-CHANGES run_pass "$work/$1-fleet.sh" "$rcst" "$rcdb" || true
}
rc_case s71c wbr "$launcher"
rec="$(grep '^E2E-wbr|' "$rcdb")"
if ! merged_in "$rcr" wbr && [ "$rec" = "E2E-wbr|open|{{WORKBENCH_ID}}|workbench" ] \
   && grep -q '^fleet.returned .*"to_workbench":true' "$rcr/emitted" && grep -q 'HAND-BACK TO THE WORKBENCH' "$rcdb.comments"; then
  ok "9srgz A4 request-changes: handed back to the Workbench -- open, assigned {{WORKBENCH_ID}}, fleet-safe removed, no fleet-return counter, comment and event say so"
else no "9srgz A4 request-changes" "rec=$rec $(grep -E 'wbr' "$rcst/out.txt" | tail -4 | tr '\n' '|')"; fi
run_pass "$work/s71c-fleet.sh" "$rcst" "$rcdb" || true
if ! grep -q 'dispatched E2E-wbr' "$rcst/out.txt" && ! grep -q '^update E2E-wbr --claim' "$rcdb.calls"; then
  ok "9srgz A4 request-changes: the next pass does not dispatch a Forge on the handed-back bead"
else no "9srgz A4: a Forge was dispatched on a Workbench branch" "$(grep wbr "$rcst/out.txt" | tail -3 | tr '\n' '|')"; fi
# RED, GENERATED: without the hand-back the same fixture goes to the ready queue.
nohb="$work/fleet-9srgz-nohandback.sh"
python3 - "$launcher" "$nohb" <<'PY'
import sys
t = open(sys.argv[1]).read()
old = '''  if worker_review_only "$state/workers/${bead##*-}"; then
    workbench_hand_back "$bead" "$reason" "$evidence"
    return 0
  fi
'''
open(sys.argv[2], 'w').write(t.replace(old, '', 1) if t.count(old) == 1 else t)
PY
if ! cmp -s "$launcher" "$nohb"; then
  rc_case s71cr wbs "$nohb"
  rec="$(grep '^E2E-wbs|' "$rcdb")"
  if [ "$rec" != "E2E-wbs|open|{{WORKBENCH_ID}}|workbench" ] && grep -q 'fleet-return-1' <<<"$rec"; then
    ok "RED 9srgz A4: without the hand-back the bead goes to the ready queue (rec=$rec), so 71c discriminates"
  else no "RED 9srgz A4: the no-hand-back variant did not reproduce the Forge return" "rec=$rec"; fi
else no "RED 9srgz A4 hand-back" "the variant could not be generated (block not found)"; fi
# 71e -- FRONT OF THE REAP ORDER, ahead of a Forge that finished first.
fo_case() { # $1 name, $2 launcher -> sets fost
  local db
  IFS="|" read -r _ fost db <<< "$(wb_fixture "$1" wbo "$2" workbench)"
  printf 'E2E-ooo|open||fleet-safe\n' >> "$db"
  run_pass "$work/$1-fleet.sh" "$fost" "$db" || true
  wait_forge "$fost" ooo; sleep 1
  enqueue "$work/$1-fleet.sh" "$fost" "$db" E2E-wbo >/dev/null
  run_pass "$work/$1-fleet.sh" "$fost" "$db" || true
}
fo_case s71e "$launcher"
if uw_before "$fost" 'E2E-wbo: a Workbench session branch queued' 'E2E-ooo: Forge exited'; then
  ok "9srgz A4: the review-only branch is reaped AHEAD of an ordinary Forge completion that finished earlier"
else no "9srgz A4 front of order" "$(grep -E 'wbo|ooo' "$fost/out.txt" | tail -6 | tr '\n' '|')"; fi
nofront="$work/fleet-9srgz-nofront.sh"
sed '/if worker_review_only "\$d"; then tier=1; prio=0; fi/d' "$launcher" > "$nofront"
if ! cmp -s "$launcher" "$nofront"; then
  fo_case s71er "$nofront"
  if uw_before "$fost" 'E2E-ooo: Forge exited' 'E2E-wbo: a Workbench session branch queued'; then
    ok "RED 9srgz A4: without the tier the earlier Forge completion goes first, so 71e discriminates"
  else no "RED 9srgz A4 front of order" "$(grep -E 'wbo|ooo' "$fost/out.txt" | tail -6 | tr '\n' '|')"; fi
else no "RED 9srgz A4 front of order" "the variant could not be generated (sed matched nothing)"; fi
# 71f -- THE ENQUEUE REFUSES what it must not queue.
IFS='|' read -r r st db <<< "$(wb_fixture s71f wbx "$launcher" workbench)"
FORT_MASKED=forge enqueue "$work/s71f-fleet.sh" "$st" "$db" E2E-wbx; m1=$?
FORT_MASKED=workbench enqueue "$work/s71f-fleet.sh" "$st" "$db" E2E-wbx; m2=$?
printf 'uncommitted\n' >> "$r-worktrees/wbx/wb-wbx.txt"
enqueue "$work/s71f-fleet.sh" "$st" "$db" E2E-wbx; d1=$?
git -C "$r-worktrees/wbx" checkout -q -- wb-wbx.txt
sed -i 's/^E2E-wbx|in_progress|/E2E-wbx|closed|/' "$db"
enqueue "$work/s71f-fleet.sh" "$st" "$db" E2E-wbx; c1=$?
sed -i 's/^E2E-wbx|closed|/E2E-wbx|in_progress|/' "$db"
FORT_MASKED=mayor enqueue "$work/s71f-fleet.sh" "$st" "$db" E2E-wbx; ok1=$?
if [ "$m1" -eq 77 ] && [ "$m2" -eq 77 ] && [ "$d1" -eq 66 ] && [ "$c1" -eq 66 ] && [ "$ok1" -eq 0 ] && [ -e "$st/workers/wbx/review-only" ]; then
  ok "9srgz A4: --review-only refuses inside the Forge and Workbench masks (77), on uncommitted changes (66) and on a closed bead (66), and queues from the Mayor's mask (0)"
else no "9srgz A4 enqueue refusals" "forge=$m1 workbench=$m2 dirty=$d1 closed=$c1 mayor=$ok1"; fi
FORT_MASKED=mayor enqueue "$work/s71f-fleet.sh" "$st" "$db" E2E-wbx; q2=$?
if [ "$q2" -eq 75 ]; then ok "9srgz A4: a second --review-only does not replace a worker already queued (75)"
else no "9srgz A4: re-queue over a live worker" "rc=$q2 $(cat "$st/enq.txt")"; fi

echo
echo "=========================================================================="
echo "SCENARIO 72 — Proofdelve ForgeOs-9srgz A5 (the Overseer's corrected Q2: keep running)."
echo "             While a Workbench sitting is live the fleet keeps dispatching;"
echo "             the touch-set guard HOLDS a fleet bead whose files overlap the"
echo "             sitting's live set (branch diff + uncommitted paths), names why,"
echo "             dispatches a disjoint one, and a held run never halts as stalled"
echo "=========================================================================="
wb_fake_live() { # $1 state, $2 worktree -> starts a process whose argv0 is workbench.sh, writes the marker, prints its pid
  ( exec -a workbench.sh sleep 300 ) >/dev/null 2>&1 &
  local p=$!
  printf 'pid=%s\nbead=E2E-wbl\nworktree=%s\nstarted=%s\n' "$p" "$2" "$(date -Is)" > "$1/workbench.live"
  printf '%s' "$p"
}
gd_case() { # $1 name, $2 launcher, $3 bd lines, $4 committed path ("" = none), $5 uncommitted path ("" = none) -> sets gdr gdst gddb gdpid
  gdr=$(mkfort "$1" ok); unpoison "$gdr"; mk_launcher "$2" "$work/$1-fleet.sh" "$gdr" || exit 3
  gdst="$work/$1-state"; mkdir -p "$gdst"; gddb="$work/$1.bd"
  git -C "$gdr" worktree add -q "$gdr-worktrees/wbl" -b bead/wbl >/dev/null 2>&1
  if [ -n "$4" ]; then mkdir -p "$gdr-worktrees/wbl/$(dirname "$4")"; echo wb > "$gdr-worktrees/wbl/$4"
    git -C "$gdr-worktrees/wbl" add -A >/dev/null; git -C "$gdr-worktrees/wbl" commit -qm "E2E-wbl: sitting work"; fi
  if [ -n "$5" ]; then mkdir -p "$gdr-worktrees/wbl/$(dirname "$5")"; echo wip > "$gdr-worktrees/wbl/$5"; fi
  printf '%b' "$3" > "$gddb"
  gdpid="$(wb_fake_live "$gdst" "$gdr-worktrees/wbl")"
}
gd_stop() { kill "$gdpid" 2>/dev/null; wait "$gdpid" 2>/dev/null; }
# 72a -- committed overlap held and named; a disjoint bead dispatches in the same pass.
gd_case s72a "$launcher" 'E2E-pov|open||fleet-safe||web/\nE2E-pdj|open||fleet-safe||src/\n' web/x.txt ""
run_pass "$work/s72a-fleet.sh" "$gdst" "$gddb" || true
if grep -q 'skip E2E-pov: HELD -- its touch set overlaps the live Workbench sitting E2E-wbl on web/' "$gdst/out.txt" \
   && grep -q '  dispatched E2E-pdj' "$gdst/out.txt" && ! grep -q '  dispatched E2E-pov' "$gdst/out.txt"; then
  ok "9srgz A5: an overlapping bead (web/ vs the sitting's committed web/x.txt) is HELD with a named reason, and a disjoint bead (src/) dispatches in the same pass"
else no "9srgz A5 overlap/disjoint" "$(grep -E 'pov|pdj|Workbench' "$gdst/out.txt" | tail -4 | tr '\n' '|')"; fi
FLEET_STATE="$gdst" BD_STORE="$gddb" "$work/s72a-fleet.sh" --status > "$gdst/status.txt" 2>&1
if grep -q 'WORKBENCH:   a sitting is live (bead pid: E2E-wbl' "$gdst/status.txt"; then ok "9srgz A5: --status names the live sitting"
else no "9srgz A5: --status" "$(head -6 "$gdst/status.txt" | tr '\n' '|')"; fi
wait_forge "$gdst" pdj; gd_stop
# 72b -- an UNCOMMITTED path in the sitting's worktree holds too.
gd_case s72b "$launcher" 'E2E-puc|open||fleet-safe||docs/\n' "" docs/u.md
run_pass "$work/s72b-fleet.sh" "$gdst" "$gddb" || true
if grep -q 'skip E2E-puc: HELD -- its touch set overlaps the live Workbench sitting E2E-wbl on docs/' "$gdst/out.txt" && [ "$(dispatched_count "$gdst")" -eq 0 ]; then
  ok "9srgz A5: an uncommitted path in the sitting's worktree (docs/u.md) holds an overlapping bead"
else no "9srgz A5 uncommitted overlap" "$(grep -E 'puc|Workbench' "$gdst/out.txt" | tail -3 | tr '\n' '|')"; fi
# 72c -- a run of held passes with no Forge live is WAITING, never a stall.
timeout 15 env FLEET_STATE="$gdst" BD_STORE="$gddb" "$work/s72b-fleet.sh" > "$gdst/loop.txt" 2>&1
if [ ! -e "$gdst/HALT" ] && ! grep -q '^[0-9:]*  stall [0-9]' "$gdst/loop.txt" && grep -q "held by the live Workbench sitting's touch set; not a stall" "$gdst/loop.txt"; then
  ok "9srgz A5: ~15 s of held passes with no Forge live (FLEET_STALL_PASSES=3, FLEET_POLL=1) write no HALT and count no stall"
else no "9srgz A5 held loop" "halt=$([ -e "$gdst/HALT" ] && echo yes || echo no) $(grep -E 'stall|waiting' "$gdst/loop.txt" | tail -3 | tr '\n' '|')"; fi
# 72d -- the sitting ends: the held bead dispatches (a stale marker holds nothing).
gd_stop
run_pass "$work/s72b-fleet.sh" "$gdst" "$gddb" || true
if [ "$(dispatched_count "$gdst")" -eq 1 ]; then ok "9srgz A5: once the sitting's process is gone the held bead dispatches (a stale marker holds nothing)"
else no "9srgz A5: no release" "$(grep -E 'puc|HELD' "$gdst/out.txt" | tail -3 | tr '\n' '|')"; fi
wait_forge "$gdst" puc
# 72e -- a live pid that is not workbench.sh (pid reuse) holds nothing.
gd_case s72e "$launcher" 'E2E-pru|open||fleet-safe||web/\n' web/x.txt ""; gd_stop
sleep 300 & np=$!; sed -i "s/^pid=.*/pid=$np/" "$gdst/workbench.live"
run_pass "$work/s72e-fleet.sh" "$gdst" "$gddb" || true
kill "$np" 2>/dev/null; wait "$np" 2>/dev/null
if [ "$(dispatched_count "$gdst")" -eq 1 ]; then ok "9srgz A5: a marker naming a live pid that is not workbench.sh (pid reuse) holds nothing"
else no "9srgz A5: pid reuse" "$(grep -E 'pru|HELD' "$gdst/out.txt" | tail -3 | tr '\n' '|')"; fi
wait_forge "$gdst" pru
# 72f -- a live sitting that has changed NOTHING holds nothing, even an undeclared bead.
gd_case s72f "$launcher" 'E2E-pnd|open||fleet-safe\n' "" ""
run_pass "$work/s72f-fleet.sh" "$gdst" "$gddb" || true
if [ "$(dispatched_count "$gdst")" -eq 1 ] && ! grep -q 'HELD' "$gdst/out.txt"; then
  ok "9srgz A5: a live sitting with an empty set holds nothing, even an undeclared (everything) bead -- an empty set is not 'everything'"
else no "9srgz A5: empty set" "$(grep -E 'pnd|HELD' "$gdst/out.txt" | tail -3 | tr '\n' '|')"; fi
wait_forge "$gdst" pnd; gd_stop
# RED, GENERATED: without the Workbench clause in the guard the overlapping bead dispatches mid-sitting.
noguard9="$work/fleet-9srgz-noguard.sh"
python3 - "$launcher" "$noguard9" <<'PY'
import sys
t = open(sys.argv[1]).read()
old = '  if [ -s "$state/.touches-workbench" ] && pair='
open(sys.argv[2], 'w').write(t.replace(old, '  if false && pair=', 1) if t.count(old) == 1 else t)
PY
if ! cmp -s "$launcher" "$noguard9"; then
  gd_case s72r "$noguard9" 'E2E-pgr|open||fleet-safe||web/\n' web/x.txt ""
  run_pass "$work/s72r-fleet.sh" "$gdst" "$gddb" || true
  if grep -q '  dispatched E2E-pgr' "$gdst/out.txt"; then ok "RED 9srgz A5: without the guard's Workbench clause the overlapping bead is dispatched during the sitting, so 72a discriminates"
  else no "RED 9srgz A5 guard" "$(grep -E 'pgr|HELD' "$gdst/out.txt" | tail -3 | tr '\n' '|')"; fi
  wait_forge "$gdst" pgr; gd_stop
else no "RED 9srgz A5 guard" "the variant could not be generated"; fi
# RED, GENERATED: without the waiting clause a held run halts as stalled.
nowait9="$work/fleet-9srgz-nowait.sh"
python3 - "$launcher" "$nowait9" <<'PY'
import sys
t = open(sys.argv[1]).read()
old = '  if [ "${pass_workbench_held:-0}" -gt 0 ]; then\n    # Proofdelve ForgeOs-9srgz A5'
open(sys.argv[2], 'w').write(t.replace(old, '  if false; then\n    # Proofdelve ForgeOs-9srgz A5', 1) if t.count(old) == 1 else t)
PY
if ! cmp -s "$launcher" "$nowait9"; then
  gd_case s72w "$nowait9" 'E2E-pgw|open||fleet-safe||docs/\n' "" docs/u.md
  timeout 15 env FLEET_STATE="$gdst" BD_STORE="$gddb" "$work/s72w-fleet.sh" > "$gdst/loop.txt" 2>&1; gd_stop
  if [ -e "$gdst/HALT" ]; then ok "RED 9srgz A5: without the waiting clause the held run HALTS as stalled, so 72c discriminates"
  else no "RED 9srgz A5 waiting clause" "$(grep -E 'stall' "$gdst/loop.txt" | tail -2 | tr '\n' '|')"; fi
else no "RED 9srgz A5 waiting clause" "the variant could not be generated"; fi
# --- FOLD of the Warden's docket-review findings 1 and 2 (Proofdelve ForgeOs-9srgz) ---
# 72h -- the poll does not rewrite the sitting's index (finding 1): a stat-stale
# tracked file makes a plain `git status` refresh and rewrite the index; with
# GIT_OPTIONAL_LOCKS=0 it reads without writing.
ix_case() { # $1 name, $2 launcher -> sets ixb ixa (index mtimes before/after a pass)
  gd_case "$1" "$2" 'E2E-pix|open||fleet-safe||web/\n' web/x.txt ""
  local ix; ix="$(git -C "$gdr-worktrees/wbl" rev-parse --git-path index)"
  case "$ix" in /*) ;; *) ix="$gdr-worktrees/wbl/$ix" ;; esac
  sleep 1.1; touch "$gdr-worktrees/wbl/subject.txt"
  ixb="$(stat -c %.9Y "$ix" 2>/dev/null)"; sleep 1.1
  run_pass "$work/$1-fleet.sh" "$gdst" "$gddb" || true
  ixa="$(stat -c %.9Y "$ix" 2>/dev/null)"; gd_stop
}
ix_case s72h "$launcher"
if [ -n "$ixb" ] && [ "$ixb" = "$ixa" ] && grep -q 'skip E2E-pix: HELD' "$gdst/out.txt"; then
  ok "9srgz fold 1: the guard's per-pass status read leaves the sitting's index untouched (no index.lock taken under the Workbench)"
else no "9srgz fold 1: the poll rewrote the index" "before=$ixb after=$ixa"; fi
nolock9="$work/fleet-9srgz-nolock.sh"
# shellcheck disable=SC2016  # a sed PATTERN: the $ names the launcher's own text
sed 's/^  GIT_OPTIONAL_LOCKS=0 git -C "\$wt" status/  git -C "$wt" status/' "$launcher" > "$nolock9"
if ! cmp -s "$launcher" "$nolock9"; then
  ix_case s72hr "$nolock9"
  if [ "$ixb" != "$ixa" ]; then ok "RED 9srgz fold 1: without GIT_OPTIONAL_LOCKS=0 the poll REWRITES the sitting's index, so 72h discriminates"
  else no "RED 9srgz fold 1" "the index was not rewritten without the variable (before=$ixb after=$ixa)"; fi
else no "RED 9srgz fold 1" "the variant could not be generated"; fi
# 72i -- a COMMITTED rename holds a bead declaring the OLD name (finding 2, --no-renames).
rn_case() { # $1 name, $2 launcher, $3 commit 1|0 -> leaves the run's output in $gdst
  gd_case "$1" "$2" 'E2E-prn|open||fleet-safe||subject.txt\n' "" ""
  mkdir -p "$gdr-worktrees/wbl/moved"; git -C "$gdr-worktrees/wbl" mv subject.txt moved/subject.txt
  [ "$3" = 1 ] && git -C "$gdr-worktrees/wbl" commit -qm "E2E-wbl: rename"
  run_pass "$work/$1-fleet.sh" "$gdst" "$gddb" || true; gd_stop
}
rn_case s72i "$launcher" 1
if grep -q 'skip E2E-prn: HELD -- its touch set overlaps the live Workbench sitting E2E-wbl on subject.txt' "$gdst/out.txt"; then
  ok "9srgz fold 2: a bead declaring the old name of a file the sitting RENAMED (committed) is held"
else no "9srgz fold 2 committed rename" "$(grep -E 'prn|HELD' "$gdst/out.txt" | tail -3 | tr '\n' '|')"; fi
nonr9="$work/fleet-9srgz-renames.sh"
sed 's/ diff --name-only --no-renames -z / diff --name-only -z /' "$launcher" > "$nonr9"
if ! cmp -s "$launcher" "$nonr9"; then
  rn_case s72ir "$nonr9" 1
  if grep -q '  dispatched E2E-prn' "$gdst/out.txt"; then ok "RED 9srgz fold 2: with rename detection the old name drops out and the bead dispatches, so 72i discriminates"
  else no "RED 9srgz fold 2 committed rename" "$(grep -E 'prn|HELD' "$gdst/out.txt" | tail -3 | tr '\n' '|')"; fi
  wait_forge "$gdst" prn
else no "RED 9srgz fold 2 committed rename" "the variant could not be generated"; fi
# 72j -- a STAGED (uncommitted) rename holds the old name too (porcelain -z, both fields).
rn_case s72j "$launcher" 0
if grep -q 'skip E2E-prn: HELD -- its touch set overlaps the live Workbench sitting E2E-wbl on subject.txt' "$gdst/out.txt"; then
  ok "9srgz fold 2: a staged rename in the sitting's worktree holds a bead declaring the old name"
else no "9srgz fold 2 staged rename" "$(grep -E 'prn|HELD' "$gdst/out.txt" | tail -3 | tr '\n' '|')"; fi
noold9="$work/fleet-9srgz-noold.sh"
python3 - "$launcher" "$noold9" <<'PY'
import sys
t = open(sys.argv[1]).read()
old = "IFS= read -r -d '' old && printf '%s\\n' \"$old\""
open(sys.argv[2], 'w').write(t.replace(old, "IFS= read -r -d '' old", 1) if t.count(old) == 1 else t)
PY
if ! cmp -s "$launcher" "$noold9"; then
  rn_case s72jr "$noold9" 0
  if grep -q '  dispatched E2E-prn' "$gdst/out.txt"; then ok "RED 9srgz fold 2: without the porcelain record's second field the staged rename's old name drops out, so 72j discriminates"
  else no "RED 9srgz fold 2 staged rename" "$(grep -E 'prn|HELD' "$gdst/out.txt" | tail -3 | tr '\n' '|')"; fi
  wait_forge "$gdst" prn
else no "RED 9srgz fold 2 staged rename" "the variant could not be generated"; fi
# 72k -- a non-ASCII uncommitted path (which plain porcelain would quote) holds.
gd_case s72k "$launcher" 'E2E-pna|open||fleet-safe||docs/\n' "" "docs/é.md"
run_pass "$work/s72k-fleet.sh" "$gdst" "$gddb" || true; gd_stop
if grep -q 'skip E2E-pna: HELD -- its touch set overlaps the live Workbench sitting E2E-wbl on docs/' "$gdst/out.txt"; then
  ok "9srgz fold 2: a non-ASCII uncommitted path (docs/é.md, quoted by plain porcelain) holds an overlapping bead"
else no "9srgz fold 2 non-ASCII path" "$(grep -E 'pna|HELD' "$gdst/out.txt" | tail -3 | tr '\n' '|')"; fi
# 72l -- --review-only's queued touches file carries a non-ASCII path RAW (the Warden round two, finding 1).
nq_case() { # $1 name, $2 launcher -> sets nqst
  local r db
  r=$(mkfort "$1" ok); unpoison "$r"; mk_launcher "$2" "$work/$1-fleet.sh" "$r" || exit 3
  nqst="$work/$1-state"; mkdir -p "$nqst"; db="$work/$1.bd"
  git -C "$r" worktree add -q "$r-worktrees/wbn" -b bead/wbn >/dev/null 2>&1
  mkdir -p "$r-worktrees/wbn/docs"; echo n > "$r-worktrees/wbn/docs/é.md"
  git -C "$r-worktrees/wbn" add -A >/dev/null; git -C "$r-worktrees/wbn" commit -qm "E2E-wbn: non-ascii"
  printf 'E2E-wbn|in_progress|{{WORKBENCH_ID}}|workbench\n' > "$db"
  FLEET_STATE="$nqst" BD_STORE="$db" "$work/$1-fleet.sh" --review-only E2E-wbn > "$nqst/enq.txt" 2>&1
}
nq_case s72l "$launcher"
if grep -qx 'docs/é.md' "$nqst/workers/wbn/touches" 2>/dev/null; then ok "9srgz nit 1: --review-only writes a non-ASCII path RAW into the queued worker's touches file"
else no "9srgz nit 1" "touches=$(cat "$nqst/workers/wbn/touches" 2>/dev/null | tr '\n' '|')"; fi
noz9="$work/fleet-9srgz-noz.sh"
sed 's/ diff --name-only --no-renames -z "\$main_branch...bead\/\$sfx" 2>\/dev\/null | tr .\\0. .\\n. > "\$d\/touches"/ diff --name-only --no-renames "$main_branch...bead\/$sfx" > "$d\/touches" 2>\/dev\/null/' "$launcher" > "$noz9"
if ! cmp -s "$launcher" "$noz9"; then
  nq_case s72lr "$noz9"
  if ! grep -qx 'docs/é.md' "$nqst/workers/wbn/touches" 2>/dev/null && grep -q '^"docs/' "$nqst/workers/wbn/touches" 2>/dev/null; then
    ok "RED 9srgz nit 1: without -z the path is written QUOTED, so 72l discriminates"
  else no "RED 9srgz nit 1" "touches=$(cat "$nqst/workers/wbn/touches" 2>/dev/null | tr '\n' '|')"; fi
else no "RED 9srgz nit 1" "the variant could not be generated"; fi
# RED for 72k (the Warden round two, finding 3): the pre-fold read -- plain porcelain,
# newline-delimited -- quotes the non-ASCII path and the bead dispatches.
noz9k="$work/fleet-9srgz-nozk.sh"
python3 - "$launcher" "$noz9k" <<'PY'
import sys
t = open(sys.argv[1]).read()
a = 'status --porcelain -z --untracked-files=all'
b = "    while IFS= read -r -d '' rec; do"
ok = t.count(a) == 1 and t.count(b) == 1
if ok:
    t = t.replace(a, 'status --porcelain --untracked-files=all', 1).replace(b, "    while IFS= read -r rec; do", 1)
open(sys.argv[2], 'w').write(t if ok else open(sys.argv[1]).read())
PY
if ! cmp -s "$launcher" "$noz9k"; then
  gd_case s72kr "$noz9k" 'E2E-pna|open||fleet-safe||docs/\n' "" "docs/é.md"
  run_pass "$work/s72kr-fleet.sh" "$gdst" "$gddb" || true; gd_stop
  if grep -q '  dispatched E2E-pna' "$gdst/out.txt"; then ok "RED 9srgz fold 2: with the pre-fold newline porcelain read the non-ASCII path is quoted and the bead dispatches, so 72k discriminates"
  else no "RED 9srgz 72k" "$(grep -E 'pna|HELD' "$gdst/out.txt" | tail -3 | tr '\n' '|')"; fi
  wait_forge "$gdst" pna
else no "RED 9srgz 72k" "the variant could not be generated"; fi

echo "=========================================================================="
echo "SCENARIO 6niaz — FIX-FORWARD: ONE bounded lap on the same worktree, then the"
echo "                 re-check's verdict; a second FIX-FORWARD is APPROVE-WITH-FINDINGS"
echo "=========================================================================="
# Proofdelve ForgeOs-6niaz part B at run level. The stub Warden returns the tokens in
# order, one per review of the bead, with a tiered record carrying one [polish]
# item. Up to six passes; a pass that closes the bead ends the loop.
ff_run() { # $1 name, $2 sfx, $3 tokens, $4 launcher
  r=$(mkfort "$1" ok); mk_launcher "$4" "$work/$1-fleet.sh" "$r" || exit 3
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"; : > "$st/all.txt"
  printf 'E2E-%s|open||fleet-safe\n' "$2" > "$db"
  local i
  for i in 1 2 3 4 5 6; do
    E2E_FORGE_REUSE=1 E2E_WARDEN_TIERED=1 E2E_WARDEN_TOKENS="$3" run_pass "$work/$1-fleet.sh" "$st" "$db" || true
    cat "$st/out.txt" >> "$st/all.txt"
    grep -q "^E2E-$2|closed" "$db" && break
    wait_forge "$st" "$2"
  done
}
ff_run s6na ffa "FIX-FORWARD APPROVE" "$launcher"
fcalls="$(cat "$r/forge-calls" 2>/dev/null)"
if grep -q '^E2E-ffa|closed' "$db" && merged_in "$r" ffa && [ "$(grep -c '^E2E-ffa ' <<<"$fcalls")" -eq 2 ] \
   && [ "$(sed -n 1p <<<"$fcalls" | grep -c 'brief= ')" -eq 1 ] && sed -n 2p <<<"$fcalls" | grep -q 'brief=/.*fix-forward/ffa/brief ' \
   && [ "$(cut -d' ' -f3 <<<"$fcalls" | sort -u | wc -l)" -eq 1 ] \
   && grep -q 'fix-forward-used' "$db" && ! grep -q 'fleet-return' "$db" \
   && [ "$(grep -c '^E2E-ffa base= ' "$r/warden-ff-env")" -eq 1 ] && grep -q '^E2E-ffa base=[0-9a-f]\{40\} items=/' "$r/warden-ff-env" \
   && ! grep -q 'polish-batch' "$db.calls"; then
  ok "6niaz B: FIX-FORWARD sends the bead back for ONE lap in the SAME worktree, briefed with the items, spending no return; the re-check is briefed with the lap base; its APPROVE merges and closes"
else no "6niaz B: the lap" "db=$(cat "$db" | tr '\n' '|') forge=$(tr '\n' '|' <<<"$fcalls") warden=$(tr '\n' '|' < "$r/warden-ff-env" 2>/dev/null)
$(grep -E 'ffa|FIX' "$st/all.txt" | tail -8)"; fi
ff_run s6nb ffb "FIX-FORWARD FIX-FORWARD FIX-FORWARD" "$launcher"
fcalls="$(cat "$r/forge-calls" 2>/dev/null)"
if grep -q '^E2E-ffb|closed' "$db" && merged_in "$r" ffb && [ "$(grep -c '^E2E-ffb ' <<<"$fcalls")" -eq 2 ] \
   && grep -q 'FIX-FORWARD read as APPROVE-WITH-FINDINGS: this bead has already had its one FIX-FORWARD lap' "$st/all.txt" \
   && grep -q -- '--labels polish-batch' "$db.calls"; then   # the stub logs a multi-line description across lines, so anchor on the flag itself
  ok "6niaz B: AT MOST ONE LAP -- the second FIX-FORWARD is read as APPROVE-WITH-FINDINGS: merged, closed, its [polish] item filed as a polish-batch bead, no third Forge"
else no "6niaz B: the bound" "db=$(cat "$db" | tr '\n' '|') forge=$(tr '\n' '|' <<<"$fcalls")
$(grep -E 'ffb|FIX' "$st/all.txt" | tail -8)"; fi
# BELT 1 (the Overseer's ruling on the Warden's finding 2): a Workbench range that
# touches a gated path waits for his signature even on an APPROVE.
IFS='|' read -r r st db <<< "$(wb_fixture s6ng wg1 "$launcher" workbench,lands-on-review)"
mkdir -p "$r-worktrees/wg1/gate-1-surface"; printf 'factory change\n' > "$r-worktrees/wg1/gate-1-surface/tool.sh"
git -C "$r-worktrees/wg1" add -A >/dev/null; git -C "$r-worktrees/wg1" commit -qm "E2E-wg1: a gate-1 file"
enqueue "$work/s6ng-fleet.sh" "$st" "$db" E2E-wg1 >/dev/null
E2E_BD_CLASSIFY=off E2E_WARDEN_TOKEN=APPROVE run_pass "$work/s6ng-fleet.sh" "$st" "$db" || true
if ! merged_in "$r" wg1 && grep -q '^E2E-wg1|open|justin|.*sign-to-land' "$db" && grep -q 'touches a gated path (gate-1-surface/tool.sh is gate-1 surface' "$st/out.txt"; then
  ok "6niaz belt 1: a Workbench range touching a gate-1 file is HELD for the Overseer on an APPROVE (not merged, sign-to-land added, assigned justin)"
else no "6niaz belt 1" "merged=$(merged_in "$r" wg1 && echo yes || echo no) rec=$(grep '^E2E-wg1|' "$db") $(grep -E 'wg1' "$st/out.txt" | tail -4 | tr '\n' '|')"; fi
# and its vacuity control: the same fixture without the gated file lands.
IFS='|' read -r r st db <<< "$(wb_fixture s6ni wi1 "$launcher" workbench,lands-on-review)"
enqueue "$work/s6ni-fleet.sh" "$st" "$db" E2E-wi1 >/dev/null
E2E_BD_CLASSIFY=off E2E_WARDEN_TOKEN=APPROVE run_pass "$work/s6ni-fleet.sh" "$st" "$db" || true
if merged_in "$r" wi1 && grep -q '^E2E-wi1|closed' "$db"; then
  ok "6niaz belt 1 VACUITY: the same Workbench range without a gated file lands on APPROVE"
else no "6niaz belt 1 vacuity" "merged=$(merged_in "$r" wi1 && echo yes || echo no) rec=$(grep '^E2E-wi1|' "$db") $(grep -E 'wi1' "$st/out.txt" | tail -4 | tr '\n' '|')"; fi
# BELT 2: a range stacked on a sitting held for his signature does not land.
r=$(mkfort s6nh ok); unpoison "$r"; mk_launcher "$launcher" "$work/s6nh-fleet.sh" "$r" || exit 3
st="$work/s6nh-state"; mkdir -p "$st"; db="$work/s6nh.bd"
# THE HELD SITTING IS HELD BY THE REAL ESCALATE ROUTE (the Warden, round two, finding
# 1): the first draft hand-wrote workbench,sign-to-land,human, a label set the
# fleet never produces for a session bead, and so hid that belt 2 could not see
# the ordinary held sitting.
git -C "$r" worktree add -q "$r-worktrees/wh1" -b bead/wh1 >/dev/null 2>&1
printf 'held sitting\n' > "$r-worktrees/wh1/wh.txt"; git -C "$r-worktrees/wh1" add -A >/dev/null; git -C "$r-worktrees/wh1" commit -qm "E2E-wh1: held work"
printf 'E2E-wh1|in_progress|{{WORKBENCH_ID}}|workbench,lands-on-review\n' > "$db"
enqueue "$work/s6nh-fleet.sh" "$st" "$db" E2E-wh1 >/dev/null
E2E_BD_CLASSIFY=off E2E_WARDEN_TOKEN=ESCALATE run_pass "$work/s6nh-fleet.sh" "$st" "$db" || true
held_rec="$(grep '^E2E-wh1|' "$db")"
git -C "$r" worktree add -q "$r-worktrees/ws1" -b bead/ws1 bead/wh1 >/dev/null 2>&1
printf 'stacked sitting\n' > "$r-worktrees/ws1/ws.txt"; git -C "$r-worktrees/ws1" add -A >/dev/null; git -C "$r-worktrees/ws1" commit -qm "E2E-ws1: stacked work"
printf 'E2E-ws1|in_progress|{{WORKBENCH_ID}}|workbench,lands-on-review\n' >> "$db"
enqueue "$work/s6nh-fleet.sh" "$st" "$db" E2E-ws1 >/dev/null
E2E_BD_CLASSIFY=off E2E_WARDEN_TOKEN=APPROVE run_pass "$work/s6nh-fleet.sh" "$st" "$db" || true
if [ "${held_rec#*|*|}" != "${held_rec}" ] && grep -q '^E2E-wh1|open|justin|.*human' <<<"$held_rec" && ! grep -q 'sign-to-land' <<<"$held_rec" \
   && ! merged_in "$r" ws1 && ! merged_in "$r" wh1 && grep -q 'shares unlanded commits with E2E-wh1 (bead/wh1)' "$st/out.txt" "$r/emitted" "$db.comments" 2>/dev/null \
   && ! grep -q '^E2E-ws1|closed' "$db"; then
  ok "6niaz belt 2: a sitting HELD by the real ESCALATE route (human, no sign-to-land), and a range stacked on it is not merged on its APPROVE; the Overseer is paged naming the held sitting"
else no "6niaz belt 2" "merged=$(merged_in "$r" ws1 && echo yes || echo no) rec=$(grep -E '^E2E-w[hs]1|' "$db" | tr '\n' '|') $(grep -E 'ws1|wh1' "$st/out.txt" | tail -4 | tr '\n' '|')"; fi
if [ -n "${FLEET_SH_PRE_6NIAZ:-}" ]; then
  ff_run s6nc ffc "FIX-FORWARD APPROVE" "$FLEET_SH_PRE_6NIAZ"
  if ! grep -q '^E2E-ffc|closed' "$db" && ! merged_in "$r" ffc && [ "$(grep -c '^E2E-ffc ' "$r/forge-calls" 2>/dev/null)" -eq 1 ]; then
    ok "RED 6niaz: the pre-edict launcher cannot act on FIX-FORWARD (no lap, nothing merged), so the two cases above discriminate"
  else no "RED 6niaz" "db=$(cat "$db" | tr '\n' '|') forge=$(tr '\n' '|' < "$r/forge-calls" 2>/dev/null)"; fi
else
  skip "RED 6niaz" "FLEET_SH_PRE_6NIAZ not set (git show fa19302f8:fort/scripts/fleet.sh)"
fi

echo "=========================================================================="
echo "SCENARIO FS -- FORGE MODEL ROUTING (docket 2026-11-13 item B). A bead labelled"
echo "forge-strong is dispatched on FLEET_FORGE_MODEL_STRONG; an unlabelled one on"
echo "FLEET_FORGE_MODEL; bead.claimed records the model and the route."
fs_run() { # $1 name, $2 launcher
  r=$(mkfort "$1" ok); mk_launcher "$2" "$work/$1-fleet.sh" "$r" || exit 3
  printf 'FLEET_FORGE_MODEL_STRONG=strongm\n' >> "$r/fort/scripts/fleet.conf"
  git -C "$r" commit -qam "conf: strong model" >/dev/null
  st="$work/$1-state"; mkdir -p "$st"; db="$work/$1.bd"
  printf 'E2E-fsa|open||fleet-safe,forge-strong\nE2E-fsb|open||fleet-safe\n' > "$db"
  local i
  for i in 1 2 3 4 5 6 7 8; do
    run_pass "$work/$1-fleet.sh" "$st" "$db" || true
    wait_forge "$st" fsa; wait_forge "$st" fsb
    [ "$(grep -c '^E2E-fs[ab] ' "$r/forge-calls" 2>/dev/null)" -ge 2 ] && break
  done
}
fs_run sfs "$launcher"
if grep -q '^E2E-fsa .* model=strongm$' "$r/forge-calls" 2>/dev/null && grep -q '^E2E-fsb .* model=stub$' "$r/forge-calls" 2>/dev/null \
   && grep -q '^bead.claimed .*"model":"strongm","modelRoute":"strong"' "$r/emitted" && grep -q '^bead.claimed .*"model":"stub","modelRoute":"default"' "$r/emitted"; then
  ok "forge-strong: the labelled bead's Forge is launched with the strong model, the unlabelled one with the default, and bead.claimed says which and why"
else no "forge-strong routing" "forge=$(tr '\n' '|' < "$r/forge-calls" 2>/dev/null) claimed=$(grep '^bead.claimed' "$r/emitted" | tr '\n' '|')"; fi
if [ -n "${FLEET_SH_PRE_FORGE_STRONG:-}" ]; then
  fs_run sfsr "$FLEET_SH_PRE_FORGE_STRONG"
  if grep -q '^E2E-fsa .* model=stub$' "$r/forge-calls" 2>/dev/null; then
    ok "RED forge-strong: the pre-sitting launcher dispatches the labelled bead on the default model, so the case above discriminates"
  else no "RED forge-strong" "forge=$(tr '\n' '|' < "$r/forge-calls" 2>/dev/null)"; fi
else
  skip "RED forge-strong" "FLEET_SH_PRE_FORGE_STRONG not set (git show 7e40aeb5d:fort/scripts/fleet.sh)"
fi

echo; echo "RESULT $pass pass / $fail fail / $notrun not run"
[ $fail -eq 0 ]

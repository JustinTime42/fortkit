---
name: unattended-fleet-run
description: Run the Manyhalls fleet unattended as the Mayor. Use when the Overseer says "run the fleet overnight", "keep the fleet moving while I'm out", "unattended fleet", or "start the nightly run". Covers the grants to collect before he leaves, the loop to arm, the per-cycle checklist, the never-fleet-safe list, the helper scripts, and the failure catalogue from the first run (2026-09-15, 51 merges in 8.5 hours, HALT never fired).
---

# Unattended fleet management

> **Carried from Proofdelve at Manyhalls's re-founding, 2026-11-18 (`fortkit-ttpk`).**
> The procedure is the machinery's and holds here. The incidents, bead ids, paths and
> numbers in the examples are that fort's: read them as the reasons for each rule, and
> re-measure anything you would rely on (`fort/scripts/fleet.conf` ships conservative
> values and `FLEET_ENABLED=0`; no Manyhalls timer is installed).

Written by the Mayor after the first run, 2026-09-15 14:24 to 23:20.
Everything here was measured, not imagined. Where a rule exists because of a
specific failure, the failure is named, because a rule without its incident
gets argued away.

> **Posture note, 2026-10-26, permanent by the Overseer's ruling of 2026-11-14 (`Proofdelve ForgeOs-yhn44`; the posture is the one word in `fort/scripts/sandbox-posture`; docket `fort/annals/regent-docket-2026-10-26-secrets-only.txt`).** While the posture is `secrets-only`, every seat has Docker, a headless browser and the network. Suspended below: (a) red-main halt, "The Mayor seat runs it with docker:false": run it with `VERIFY_REQUIRE_DOCKER=1`; (b) gate 2, "The only gate that discriminates is his host Docker run": any seat runs the MigrationTests, and a Docker-backed run in the bead's own worktree, pasted on the bead, is fleet evidence (the Overseer's decision 5), while every migration still needs his signature; (c) "Name the full suite in the criteria": name the full suite without the MigrationTests filter, with `VERIFY_REQUIRE_DOCKER=1`; (d) "Host tests and red arms go through the airlock": a seat runs a Docker-backed test or red arm directly in a worktree, and `host-test` stays for host-only use; seats run `scripts/preview.sh` directly, and the airlock `preview` operation keeps its Keep approval for host use. Unchanged: the never-fleet-safe list, gates 1 to 6, push only through push-ready, signatures only by his hand. Back in `full`, the text as written holds again.

## The one structural fact that decides the whole approach

**The fleet does not need the Mayor awake. It needs the queue full.**

`fort/scripts/fleet-supervisor.sh` fires from a systemd user timer every two
minutes (`OnCalendar=*-*-* *:00/2:00`) and starts a run whenever a fleet-safe
bead is ready or a worker is reapable. A run that hits its hard stop
(`FLEET_HARD_STOP=36` launches) ends cleanly and the supervisor restarts it
within a minute. Measured twice on 09-15: 39 s and 95 s gaps. Nothing needed.

Exactly two things stop it:
1. **An empty queue.** The supervisor idles silently.
2. **`~/.local/state/manyhalls-fleet/HALT`.** Every future run refuses until a
   person removes it, or the Mayor does under grant 2's conditions. Written on
   a red main (post-merge or nightly) or a stall.

One more thing SLOWS it and does not stop it: **the supervisor's back-off**
(`Proofdelve ForgeOs-s49w`). After a run it started drains having done nothing, it waits
4, 8, 16, 32, then 60 minutes. Since `Proofdelve ForgeOs-enred` (2026-10-19) each window
ends in ONE probe run, and the next firing judges that probe: nothing again
backs off one step further, work done clears it. Before enred the supervisor
re-judged the same stale run record after every window and never started a run
(measured 2026-10-19 08:04-08:34), so this sentence was false until then. You
do not need to delete `supervisor.backoff` to resume; at worst you wait one
window.

Therefore: **front-load depth first, loop second.** A deep queue survives the
Mayor's death (the cron loop is session-only and dies with the session; the
supervisor does not). Then loop to top it up.

The honest throughput ceiling is `FLEET_WARDEN_CONC=1`: roughly 8 beads/hour
whatever the Forge concurrency says. Touch-set diversity matters less than
depth. On 09-15 careful triage produced beads at about the rate the fleet
consumed them, so the queue ran at whatever depth the last half hour produced.
Plan for that, not for a buffer.

## Before he leaves: collect three grants, on a bead, in his words

File a run-log bead first (`bd create`, P1, type task, title
`Unattended run <date>: ...`). Record the grants ON that bead before acting on
any of them. Use `AskUserQuestion`; these are genuinely his and the answers
change what you do:

1. **Push.** Standing, bounded: `git push origin main` after a fleet merge
   lands AND its post-merge verify is green. Code only, no force, no branches,
   no tags, no Dolt. **Expires when he returns.** Report every push in the log.
2. **HALT recovery.** Clear a STALL-halt after diagnosing and fixing the cause,
   recording both. **A red-main halt may be cleared ONLY when ALL of these hold**
   (Overseer's standing default from 2026-10-16, his words: "ok yes I like that
   better. ensure that shows up in the default grants moving forward"; the
   incident: 2026-10-16 00:42, ~9 h idle fleet for a stray root evidence file
   diagnosed and fixed in 15 min):
   - **Diagnosis first, on the run bead:** the failing step by name, its output,
     and why the fix addresses exactly that.
   - **The fix is narrow:** moving or deleting a non-code file, a docs/records
     change, or `git revert` of the offending fleet merge. Never product code.
   - **Green at the exact HEAD:** `fort/scripts/verify.sh` passes at the new main
     HEAD (a fresh detached worktree is fine). The Mayor seat runs it with
     docker:false; the restarted fleet's first post-merge verify has Docker and
     re-halts if main is still red, so the exposure is one merge.
   - **Never for a red you cannot explain:** a verifier-environment failure
     (Proofdelve ForgeOs-u65j.4), or a dotnet-test or MigrationTests failure you cannot
     reproduce, stays halted for him.
   - **Once per night:** a second red-main halt in the same run stays halted.
   Otherwise: stop dispatching, label `human`, leave it. The mechanical version
   (the supervisor lifts a red-main halt itself on a docker:true verify.pass at
   main HEAD) belongs on a Regent docket.
3. **What to stock.** Product backlog first (he chose this on 09-15), then the
   findings treadmill. Get it in his words; do not assume it carries over.

Also collect `ssh-add -l` showing an identity, or every push fails with
`Permission denied (publickey)` (Proofdelve ForgeOs-47mq, three times). He runs `ssh-add`
outside the mask; the agent socket is shared.

**Ask him to close Firefox (and Steam) before he leaves.** His words, 2026-10-14:
"In future I'll just make sure to close firefox during an unattended run like
this (no reason to have it open when I'm not even there)." Measured on the night
of 2026-10-13/14 (Proofdelve ForgeOs-603jn): with zero Forges the host sat at 22-23G of 31G,
Firefox content processes holding ~14G, and systemd-oomd killed the WHOLE fleet
run unit four times (20:44, 20:53, 21:00, 04:56) once six Forges' builds
overlapped. Every kill orphans every live bead ("NEEDS A PERSON"). If it is
open anyway, meter concurrency: swap `fleet-safe` to `held-oom` on everything not
in flight and release a few at a time (`FLEET_FORGE_MAX` is in kernel-locked
fleet.conf). Check kills with ABSOLUTE timestamps,
`journalctl --since "YYYY-MM-DD HH:MM" | grep "oomd.*Killed /"`: after midnight,
`--since "21:01"` means 21:01 today and searches an empty window.

## Arm the loop

`/loop 20m <prompt>` via CronCreate, offset off the :00/:20/:40 marks
(`7,27,47 * * * *`). The prompt must be SELF-CONTAINED so it survives a
compaction: name the run-log bead, the checklist, the never-fleet-safe list,
and the push clause. The template that worked is in "Loop prompt" below.

**It fires only while the REPL is idle**, so it never interrupts work.
**It is session-only.** If the session dies, only the supervisor keeps the
fleet alive, on whatever depth exists. That is why depth comes first.

**When he returns, kill it (`CronDelete`).** Its prompt says "the Overseer is
away" and instructs a push under an expired grant. On 09-15 it fired twice
after his return before I stopped it. A stale automated prompt instructing an
unauthorized action is a hazard the Mayor created and must remove without
waiting to be told.

## The cycle, every 20 minutes

Monthly: if `scripts/queue-lint.sh` shows `EXPORT SIZE`, run `scripts/bead-archive.sh --dry-run` and report to the Overseer before pruning.

```bash
# 1. HEALTH
ls ~/.local/state/manyhalls-fleet/HALT              # absent is good
cat ~/.local/state/manyhalls-fleet/supervisor.streak
pgrep -f fort/scripts/fleet.sh
# significant events since last cycle: review.verdict, fleet.returned, merge,
# incident, fleet.capped, verify.fail, fleet.ended, fleet.begun, gate.approved

# 2. INBOX -- the queues bd ready never shows
bd list --label-any fleet-escalated,fleet-return-1,fleet-return-2,mayor-review --limit 0

# 2b. HIS NOTES -- when the Overseer routes a bead to you from the dashboard
# ("Approve -> Mayor"), the Keep labels it mayor-review AND writes his note as
# a gate.* event (actor justin) and a bead comment. The inbox line above shows
# the TITLE only; three notes asking the Mayor a question sat unread for a
# cycle on 2026-09-16 (6qn1, 51x1, x2lv). Read the notes, answer the ones that
# ask, in chat and on the bead. Arm a Monitor on the stream for the in-between.
python3 - <<'PY'
import json, glob
for f in sorted(glob.glob('fort/events/events-*.jsonl'))[-2:]:
    for l in open(f):
        try: e = json.loads(l)
        except Exception: continue
        if e.get('actor') == 'justin' and str(e.get('category','')).startswith('gate.'):
            print(e['ts'][:16], e.get('target'), '|', e['detail'][:200])
PY

# 2c. A NOTE THAT ASKS FOR MORE WORK IS NOT A LANDING (Proofdelve ForgeOs-kj9c7, 2026-10-14).
# An Approve whose note says "go on lap N" (or any "fix X first") still records
# gate.approved with an approvedSha of the CURRENT tip. Restoring fleet-safe on
# that bead makes fleet.sh's signed-landing path LAND that tip. Measured on
# 2md9d.1.12 at 16:10: it tried to land a round with a reproduced regression and
# only a merge conflict stopped it. File a child LAP bead (cut from main,
# `git merge bead/<parent>`, the new criterion, sign-to-land) and park the
# parent in mayor-lane. NO `bd dep add <parent> <lap>`: on a CHILD that edge
# deadlocks the lap out of `bd ready` (see "Never add a blocks edge between a
# parent and its own child" below; re-measured 2026-10-21, five laps stuck).
# Never fleet-safe the parent.

# 3. DEPTH -- below 10, stock
bd ready --limit 0 --label fleet-safe --json | python3 -c 'import json,sys;d=json.load(sys.stdin);d=d.get("data",d) if isinstance(d,dict) else d;print(len(d))'

# 4. STOCK (see below), then ALWAYS:
scripts/queue-lint.sh                                 # exit 0 or fix it

# 5. PUSH -- only through the gate, never by eye
scripts/push-ready.sh && git push origin main         # exit 0 YES / 1 NO / 2 WAIT / 3 refuse
fort/scripts/emit.sh push "<range and why>" -a emrith -s mayor -t main

# 6. LOG -- append-only, safe quoting (see "Two shell traps")
bd comment fortkit-<runlog> "$(cat <<'EOF'
...
EOF
)"
```

`scripts/push-ready.sh` exists because on 09-15 I read `verify.run commit=X`,
matched the commit, and pushed while the verifier was still running. It
passed 76 s later. The process was still wrong. WAIT (2) and REFUSE (3) are
separate exits on purpose. **A green push-ready is not authorization**: it
checks the tree, not the grant.

## Triage the findings with a budget (Overseer 2026-11-11)

His words: "I feel like the Warden ends up with a LOT of findings, and some are trivial,
and many seem like they could easily be wrapped into a quick fix instead of round
after round of fleet work", then "let's work through implementing all of that".
Measured on 11-10/11: about a third of findings were record-only, about half became a
P3/P4 bead of one to three lines, and each such bead cost a full Forge -> verify ->
review -> merge lap on the one Warden slot. Twice a follow-up's own review filed a
follow-up on the same test lines (E12b -> rtvkz -> 87gj4 -> 87gj4.1).

Every "Triage the findings" bead, in this order:

1. **Record-only stays in the review.** Observations, limits of the review, honest-but-
   incomplete Forge comments, "accepted" notes: close the triage bead with one line
   naming them. No bead.
2. **One bead per review at most.** Fold every actionable finding of one review into a
   single bead. If an open bead already touches the same file, fold the finding into it
   by comment instead (wup3u's line went into 7mfp0, 11-11).
3. **Route by size.**
   - Tests-only, CSS-only, comment or harness tidy, no behaviour change, a few lines:
     label `polish-batch`, NOT `fleet-safe`. The next Workbench sitting clears the batch
     (`bd list --label polish-batch`), one review for all of them.
   - Behaviour change, a real defect, money, visibility, auth, migration, or anything a
     person would notice: `fleet-safe` as before, P2 or higher if it is a defect.
   - **Idle fleet beats a full batch.** When fleet-safe depth is 0 and no Workbench sitting
     is under way, move `polish-batch` beads back to `fleet-safe`, except ones that touch a
     branch held for the Overseer's signature (they would conflict with it). The budget
     exists to keep the one Warden slot for substantive work; an idle slot is not that
     (11-11 21:43, run ended drained with eleven polish beads waiting).
4. **Write the criterion against main before filing** (memory
   `run-the-instrument-before-filing`): copy the literal values from the tree or from
   `git show <sha>:<path>`, never from memory; execute every red arm you prescribe, or
   say why it must fail on main. On 11-10/11 three extra rounds came from Mayor criteria
   (`canInvite === true` broke fixtures, "201" for a 202 endpoint, an incomplete literal
   list, a red arm that could not fail).

## Stocking: where fleet-safe beads come from

Ranked by yield on 09-15:

1. **Findings-triage beads** (`Triage the findings from the fleet-merged review
   of X`). The fleet files one per APPROVE-WITH-FINDINGS or MERGE-PARENT-OPEN.
   Each carries the Warden's verbatim review; each yielded 0-2 beads. This is the
   treadmill and by mid-run it is the ONLY source. Read with:
   `python3 scripts/unattended-fleet/findings.py 1200 fortkit-X fortkit-Y`
2. **Backlog beads with criteria but no `Touches:` line.** Find with
   `bd list --status open --limit 0 --json | python3 scripts/unattended-fleet/triage.py`
   then add the line with `add-touches.py` (it refuses to double-append and
   proves the write by read-back). By hour two of 09-15 this source was
   drained: what remains at P1/P2 is fort infrastructure the Forge cannot write.
3. **Already-merged parents.** `MERGE-PARENT-OPEN` leaves the parent open with
   its original criteria, indistinguishable from fresh work. Six were open at
   once on 09-15. Each is a Mayor judgement: close it if the remainder landed
   elsewhere (verify in the TREE, not the record), or carry the unmet criterion
   into a new bead and close the parent. `already-merged.py` lists them.

**Every bead:** real acceptance criteria naming the PROPERTY (never a grep
proxy), every code identifier in backticks so the citation check can see it
(fact `identifiers-in-criteria-go-in-backticks`), a `Touches:` line naming REAL paths (queue-lint refuses a path whose
directory does not exist), and `--add-label fleet-safe` only after
`queue-lint` is clean. **Never write a placeholder `Touches:`** (`none`,
`n/a`, `TBD`): a non-empty prefix that matches no real path means "touches
NOTHING" to `touch_set_of`, so the bead co-dispatches with every declared bead
and the guard protects nothing (Proofdelve ForgeOs-pay0, the Warden on b9mj). Only an ABSENT line
or one that normalises to empty (`*`, `/`, `.`) means everything, and everything
serializes the queue. Name the files, or omit the line and accept the serial.

**NEVER MARKDOWN-FORMAT THE `Touches:` LINE.** `fleet.sh touch_set_of` and
`queue-lint.sh` match a line that STARTS with `Touches:`. Writing
`**Touches: a, b**` for emphasis makes the line invisible, and an invisible
touch set is the WHOLE REPOSITORY. Measured on `Proofdelve ForgeOs-5gbf`, 2026-09-18: I
bolded it, labelled the bead, and queue-lint reported UNDECLARED within minutes.
Plain text, at the start of its own line, always. The same goes for a `Touches:`
inside a bullet, a blockquote or a fenced block.

**ENUMERATE A FALSIFYING CASE PER GUARD, NOT PER BEAD.** Three criteria misses
in one night, all the same shape: I asked for a property and did not ask for the
case that would falsify it.
- `Proofdelve ForgeOs-mi7`: asked for a Docker-backed test the Forge cannot run, so the
  suite would print green having executed nothing.
- `Proofdelve ForgeOs-njz`: asked for three code fixes and never named the spec, so the
  merge falsified its own spec while standing order 6 makes spec updates
  expected output.
- `Proofdelve ForgeOs-4q03`: criterion 1 asked for TWO guards (JSON parse, record-count
  floor); criterion 4 enumerated RED cases for the parser and for python failure
  and NONE for the floor. The Warden replaced the floor with `if False:` and the
  harness still passed 14/0.
So when a bead asks for N guards, its evidence criterion names N red cases. The
question to ask before labelling: **for each thing I just required, what result
would tell me it is absent?** If the answer is "the suite would look the same,"
the criterion is decoration (`Proofdelve ForgeOs-8zb7`).

**SAY WHERE THE INVERSION GOES WHEN THE CODE SITS BEHIND A SHORT-CIRCUIT.**
"It went red" is compatible with "it went red for the wrong reason." Measured on
`Proofdelve ForgeOs-2g97`, 2026-09-19: the function under test was the THIRD operand of a
`||` chain, after `Uri.TryCreate(..., UriKind.Relative)`. Had `TryCreate`
rejected the input, the step being pinned would never have been reached — and
the new test row would have been VACUOUS while still going red under a throw
placed anywhere earlier in the same function. The bead's red-before-green
criterion did not say where to put the throw, so the paste could not settle it,
and the Warden had to place her own inversion AT the call site to prove the row
discriminated. Write it as: "place the inversion at <the specific call>, not
earlier in the function," and ask for the other rows to stay green — that pair
is what distinguishes a real pin from a red anywhere upstream of it.

**A CRITERION THAT ASSERTS A FACT ABOUT THE DATA MUST BE MEASURED BEFORE IT IS
WRITTEN.** This is a different failure from the missing red case above, and it
cost more, because the Forge implements it faithfully. Measured on
`Proofdelve ForgeOs-pezy`, 2026-09-18: my criterion suggested the wording "(open,
in_progress and blocked)". **`blocked` is not a status bd stores at all** — bd
and the Keep derive it from edges — and **`deferred` is, twelve times.** So the
shipped allow-list `{open, in_progress, blocked}` silently drops every deferred
bead out of four checks, in a script whose own comment says latent problems on
not-yet-dispatchable beads are the point. One command would have caught it:

```bash
python3 -c "import json,collections;c=collections.Counter();\
[c.update([json.loads(l).get('status')]) for l in open('.beads/issues.jsonl')];print(dict(c))"
```

If a criterion names a status, a field, a limit or a count, run the query first
and paste the number into the bead. Do not write "something like" and let the
Forge guess which part was load-bearing.

**ASK FOR THE RED RUN AS A FILE IN THE WORKTREE, NOT AS A PASTE.** Measured
across the 2026-09-18/19 run: the Forge pasted GREEN only on `njz`, on `ld77`,
and on `u89s` **twice in a row**, while every one of my criteria said "paste RED
and GREEN". The Warden reproduced the reds herself each time, which is the only
reason the evidence exists.

The cause is probably not discipline. The Forge runs RED first, then fixes, then
runs GREEN — and by handoff time the RED output has left its window (the same
30-second-command and output-truncation problem as `Proofdelve ForgeOs-y4rg`). It pastes
what it still has.

So stop asking it to HOLD the output: **"redirect the RED run to
`<bead>-red.txt` in the worktree and name the path in your handoff; then fix and
redirect the GREEN run to `<bead>-green.txt`."** A path survives a truncated
window, the reviewer can read both, and "the file is missing" is a checkable
failure where "it was not pasted" is ambiguous between forgot, truncated, and
never ran.

**PUT THOSE FILES UNDER `evidence/`, NOT THE REPO ROOT.** Measured 2026-10-15
(the Warden on `2md9d.2.36`): fifteen `*-red.txt`/`*-green.txt` files had been committed
at the repository root because this paragraph said "in the worktree" and named no
directory. Write **`evidence/<bead>-red.txt`** and **`evidence/<bead>-green.txt`**.
The fifteen were moved there in one records commit the same night.
Since `Proofdelve ForgeOs-hmdo8` (2026-10-15) `verify-impl.sh` refuses root-level ones.

**AND IN THE `Touches:` LINE NAME THE FILE, NEVER BARE `evidence/`.** The fleet's
touch guard matches by prefix (`fleet.sh` `touch_sets_intersect`), so two beads
that each declare `evidence/` cannot run at once. Measured 2026-10-16 00:03:
`2md9d.3.27.1` (P1) held behind `2md9d.3.29` on `evidence/ ~ evidence/`, both
written that way by me. Write `evidence/<bead>-red.txt`.

**IF YOU NAME THE FIXTURE, TRACE WHICH CODE PATH IT REACHES.** The most
repeated mistake of the 2026-09-18/19 run, three times in one night, and every
time the criterion was *met as written* while the evidence proved nothing:
- `Proofdelve ForgeOs-8rx8m`: I suggested "point the harness at a nonexistent `flock`" to
  prove a bounded wait terminates. That hits the `command -v` preflight and
  **exits before the loop** — 0.05 s, and the bound itself was never exercised.
- `Proofdelve ForgeOs-0nhz4`: my criterion described a manufactured absence (WAIT, **exit
  2**), and the case `rm -f`'d both day files, so the old script returned **exit
  3** — red, on the wrong axis. The Warden called it "the wrong colour of red."
- `Proofdelve ForgeOs-f4s0`: I asked for "an existing case that depends on normal `awk`
  behaviour" as a leak control. No such case could exist; `ld77` had made the
  runbook POSIX-only.

**WHEN A CRITERION SPANS FILES, NAME THE FILE PER CRITERION. "ONE PASS" READS
AS "ONE PLACE."** Measured on `Proofdelve ForgeOs-b8s2h`, 2026-09-19: criterion 3 said
"fold this into the same amendment as criterion 1 — one comment pass, not two."
I meant one commit. The Forge read it as *put everything into
`push-ready.sh:42`*, did so, and never touched
`scripts/push-ready-harness.sh` — where the sentence the criterion was actually
about lives. The Warden's words: it "read 'one comment pass, not two' as 'put
everything into push-ready.sh:42'", and that home was reasonable; what could not
be satisfied there was "stop attributing X", because only the attributing
sentence can satisfy it. So: say **"one commit, two files: <file A> for
criterion 1, <file B> for criterion 3."** Never "one pass."

**A "CHECK WHETHER THIS APPEARS ELSEWHERE" INSTRUCTION MUST SAY: FIND THE
CLAIM, NOT THE PHRASE — AND GIVE THE PATTERN.** Measured on `Proofdelve ForgeOs-2byaz`,
2026-09-19: my criterion said "check whether the same claim appears anywhere
else — `scripts/push-ready.sh` itself, or a handoff." It named the right file.
The Forge ran an exact-phrase grep for the wording it had just fixed, and the
claim survived one file over **as a paraphrase**: "bounded at the fleet's 14-day
horizon." A phrase search cannot find a restatement, so the instruction was
unsatisfiable by the method it invited. The Warden's sweep found it with
`14[- ]day|fleet's.*horizon|same.*(window|horizon)` over four trees. So supply a
REGEX ALTERNATION over the concepts, name the trees, and ask for the sweep's
output to be pasted — a recorded sweep is checkable; "I looked" is not.

So: either describe the fixture by the PATH it must exercise ("`flock` present,
holder starts, readiness file never written, so the loop runs and then
terminates"), or state the property and let the Forge choose the fixture. **A
suggested fixture reads as help and lands as a requirement**, and a bad one
produces a green the reviewer has to redo by hand. And when you do name one, say
what must NOT happen: do not trade one axis for the other, keep the case that
covered the old path.

**WHEN A CRITERION PRESCRIBES A COMMAND, STATE THE PROPERTY IT MUST PRESERVE.**
A command's default output ORDER can be load-bearing, and naming the command
hides that. Measured on `Proofdelve ForgeOs-u89s`, 2026-09-19: my criterion said "replace
the oldest-first scan with a single `git rev-list --first-parent --ancestry-path
"$tip..$main_ref"`". **`git rev-list` outputs newest-first by default**, so the
recipe implemented faithfully REVERSED the order — and oldest-first was the whole
mechanism for picking this branch's landing merge rather than a later unrelated
one, which the SAME bead's earlier criterion existed to prevent. My performance
fix undid my own correctness fix and the Forge could not have known, because I
gave a recipe instead of a criterion. Write "resolve the FIRST landing merge on
main's first-parent line, oldest-first, and prove a later unrelated merge is
never adopted" — a newest-first default cannot satisfy that sentence.

**The same root produces three shapes, and tonight produced all three.** (a) A
missing red case — `mi7`, `njz`, `4q03`, `drin`, `xdlu`. (b) A wrong fact about
the data — `pezy`, where I named a status bd does not store. (c) **A criterion
presuming a distinction a previous merge already removed** — `f4s0`, where I
asked for "an existing case that depends on normal `awk` behaviour" to keep
passing, and `ld77` had made the runbook POSIX-only, so no such case could
exist. Shape (c) is the one that looks most like diligence while being least
checkable: it reads as a positive control and is unsatisfiable. Before writing a
criterion that references EXISTING behaviour, read that behaviour at HEAD — not
at the commit the finding was written against.

**AN "EITHER DO IT OR SAY WHY" SENTENCE WITH NO CRITERION ATTACHED GETS
SILENTLY DROPPED.** Measured on `Proofdelve ForgeOs-xdlu`, 2026-09-18: I folded in an
optional idiom convergence worded as "if it is a small change while you are in
the file, do it and say so; if it is not, leave it and say that instead." The
Forge did **neither** — no change and no sentence — and the review had to notice
the absence. An option you actually want an ANSWER to is a criterion ("state on
the bead which you chose and why"), numbered like the rest. An option you do not
need an answer to should say "optional, no report needed" so nobody looks for one.

**"NOTHING UNDER `fort/`" IS A CRITERION NO FORGE CAN SATISFY.** A handoff under
`fort/handoffs/` is mandated seat output, so a literal reading refuses the
session its own required artifact. Write **"nothing under `fort/` except your
own handoff"**. (the Warden, finding 6 on `Proofdelve ForgeOs-pezy`. She read it as intended and
passed it; the next reviewer might not, and would be right.)

**A PER-SITE RED ARM AND "MAKE THE SITES ONE" CANNOT BOTH BE CRITERIA.** Measured on
`Proofdelve ForgeOs-2md9d.2.24.2`, 2026-10-15: I asked for "restore the bug at THAT site only and
show THAT path fail while the other stays green" and, in the same bead, for the two
duplicate sites to become one implementation. Once they are one, there is no "that
site" to restore; the Forge inverted the shared method (both paths red) and the Warden had
to build a private copy to prove per-path discrimination. When a bead dedupes, ask
for the inversion at each CALL SITE (point that caller at a copy with the bug), and
say so.

**IN A LANDING LAP, THE SOURCE BRANCH'S OWN RECORDS TRAVEL WITH THE MERGE.**
Measured on `Proofdelve ForgeOs-2md9d.2.24.1`, 2026-10-14: my criterion said "nothing under
`fort/` changed except your own handoff", and the Forge read it literally and left
the parent branch's two Forge handoffs (`fort/handoffs/forge-2026-10-14-2md9d.2.24*.md`)
out of the merge. Nothing was lost (they stay reachable through the second parent),
but they never reached main's `fort/handoffs/`, which the memory consolidator reads,
and the tree he signs differs from the one he signed. Write the lap criterion as:
**"the merge carries every file of `bead/<parent>`, its handoffs included; beyond
that, nothing under `fort/` except your own handoff."**

**A SERVER BEAD THAT CHANGES WHAT AN ENDPOINT ACCEPTS NAMES EVERY CONSUMER** (`Proofdelve ForgeOs-481se.3`; the rule and its incident are in `fort/seats/mayor.md`). Refuses a field, requires a field, or assigns fields from the request: grep the web's payload builders and the MCP tool classes `src/Product.Api/Mcp/*McpTools.cs` for the endpoint (`McpTools.cs` was deleted by `Proofdelve ForgeOs-413u8.41`), and write a round-trip criterion per consumer or a linked consumer bead with a `bd` edge. Prose "ships with X" is not an edge.

**AUDIT A READY BEAD AGAINST MAIN BEFORE IT DISPATCHES, AND SAY SO ON IT.** Beads are triaged days ahead and main moves under them (`3.16` and `3.24`, 2026-10-16). When a deploy-critical or large bead is about to become dispatchable, re-read its premises at HEAD (identifiers, files, what already exists), fix it with unlabel/fold/relabel, and add `Checked against main <sha>`. `Proofdelve ForgeOs-481se.1` makes queue-lint list the commits to a ready bead's touched paths since that marker; read the STALE CRITERIA section every cycle once it lands. And when an audit finds ONE bug, sweep its CLASS before reporting: on 2026-10-16 the Mayor found the deal-save refusal, then deal create, then the parcel-save erase, one ask at a time, each time sounding finished.

**Fold, don't pile.** When a new finding lands in a file that already has an
unclaimed fleet-safe bead, append a criterion to that bead (read old, append,
write, verify by read-back) rather than filing a second bead that will only
serialize behind it.

**AND UNLABEL BEFORE YOU FOLD, because a fold into a `fleet-safe` bead is a
RACE BY CONSTRUCTION.** The supervisor fires every two minutes, `forge.sh`
snapshots the bead text into the sandboxed prompt AT DISPATCH, and an unclaimed
fleet-safe bead can be claimed at any instant. So:

```bash
bd update <id> --remove-label fleet-safe     # closes the window
python3 scripts/unattended-fleet/append-block.py <id> <block-file>
bd update <id> --add-label fleet-safe        # and re-run queue-lint
```

The supervisor will not claim an unlabelled bead. Cost: a couple of minutes of
that bead's dispatchability, against a whole lap working from stale criteria.

Measured twice on 2026-09-18, and the second one is why this paragraph exists,
because the obvious rule does not cover it. `Proofdelve ForgeOs-mi7`: a correction landed
**81 s** after the claim, and the lesson looked like "stock a bead fully, THEN
label it." `Proofdelve ForgeOs-fruy`: the fold landed **77 s** after the claim — and fruy
WAS fully stocked when it was labelled. What arrived later was a finding from a
DIFFERENT bead's verdict (`njz` -> `gijh`) that belonged in fruy, which is
exactly what the paragraph above instructs. So "stock fully, then label" is
true and insufficient: new findings arrive after stocking as a matter of course,
and the fold instruction itself is what walks you into the race. Unlabel first.

## Two kinds of open bead that are not work: `record` and `standing`

**This is the one place these two labels are defined. If you find a second
definition anywhere, one of them is wrong and this one is the survivor
(`Proofdelve ForgeOs-76uob.4`, criterion 1 and criterion 6).**

Every backlog count in this fort divides by the number of open beads, and two
kinds of open bead are not asking anyone to build anything. Left unlabelled they
sit in the denominator permanently and read, to any router, as unstarted work.

| | `record` | `standing` |
|---|---|---|
| What it is | A log of a COMPLETED event | A rule the fort works under |
| Example | a night-run log; a fort-day ledger | `Proofdelve ForgeOs-eng3`, `Proofdelve ForgeOs-8zb7`, `Proofdelve ForgeOs-zwyp` |
| Can it close? | Yes, when nothing is left in it | No. Closing it would MISDESCRIBE it |
| An open one means | a triage question: is anything left? | nothing. It is correct and expected |
| Backlog count | excluded | excluded |
| Stale / stale-parent report | excluded | excluded |
| The misrouted report | NOT excluded | NOT excluded (see the red arm below) |

**THE TEST THAT SEPARATES THEM IS WHAT CLOSING WOULD MEAN.** Close a record and
you have said "that event is fully accounted for", which is a claim about the
record and may well be true. Close a standing discipline and you have said the
fort no longer works that way, which is false and which nobody decided. If you
cannot tell which you are holding, ask what a reader would conclude from seeing
it closed.

**NEITHER IS `deferred`.** A deferred bead is work, waiting for a date. These
are not work. `bd defer` on a standing discipline says it becomes relevant
later, which is the opposite of what it is.

**EXCLUSION IS PER-CHECK AND JUSTIFIED PER-CHECK, NEVER GLOBAL.** `Proofdelve ForgeOs-eng3`
carries `standing` and is correctly excluded from the stale-parent report, where
its nineteen closed children make it look abandoned. It must still appear in the
misrouted report, because it names `.claude/` and `fort/scripts/` and is
genuinely unroutable to the fleet: that finding is TRUE and suppressing it
everywhere would hide it. A label that silences a bead in every report is not a
classification, it is a mute button.

**STANDING ORDER 12 APPLIES IN FULL.** Labelling one of these deletes nothing,
closes nothing and defers nothing. It stops the bead pretending to be work.

## Never fleet-safe, unattended

Route these `--add-label human` with a comment saying why, at the moment you
notice, never at session close:

- **Gate 1**, judged by what a change DOES, not by filename: authentication,
  identity linking, which rows a caller may see. Includes "which callers may
  mutate" (b0vj.3.1) and consent steps (b0vj.12).
  **Amended 2026-09-15 22:40 after `orew`:** a gate-1 bead the OVERSEER ASKED
  FOR may be dispatched. The fleet cannot merge it: the Warden's ESCALATE
  removes `fleet-safe`, labels `human`, and the merge waits for his signature
  and a Mayor's hand (`orew` went Forge -> verify -> ESCALATE -> signed ->
  re-check -> hand merge `1d0305a`). Write "GATE 1" in the bead's own text so
  the Warden sees it. What stays never-fleet-safe is gate-1 work he has NOT asked
  for, and any gate-1 bead whose text does not say so.
- **Gate 2**: any migration, including column ADDS. The only gate that
  discriminates is his host Docker run; every agent-visible gate is green
  either way (`migrationtest-historical-schema-trap`).
- **Gate 3, 5, 6**: deploy/Azure, the approvals module, the fort constitution
  (`fort/scripts/`, `fort/profiles/`, `fort/charter.md`, `fort/seats/`,
  `.claude/`, `scripts/verify-impl.sh`).
- **Anything whose deliverable is an ANSWER rather than a diff.** The fleet
  returns it as "no product change: handoff only", re-dispatches it, and
  returns it again (Proofdelve ForgeOs-nz3u; pkl9 and nf17 on 09-15, four launches).
  This includes any bead whose premise may turn out false.
- **Product direction.** If the bead has to argue for its own direction, that
  argument IS the doubt (Proofdelve ForgeOs-cf5s). But "he asked for it" is already
  approved: read the DESCRIPTION, not the title. I sent him b0vj.65 for a
  second signature when its first line read "OVERSEER DECISION 2026-09-12".
- **The verifier itself.** `scripts/verify-impl.sh` is Mayor-writable and the
  highest-blast-radius file this seat can edit. I declined it unattended twice
  (6qn1, odew) with beads in flight. Reporting tools like `queue-lint.sh` I
  will change unattended, with a harness. The gate waits for him or an idle
  fleet.

## The failure catalogue (each cost something on 09-15)

**A parent's residual list has usually been carried already, and an old bead's
premise has usually moved.** Two errors on 2026-09-16, same class, two
launches and two reviews each. (1) I carried `kbt4.13`'s round-two findings
into `kbt4.13.1/.2` from the parent's own comment; the fleet had filed a
triage bead for that verdict (`hy13`) and the previous session had already
landed `hy13.1/.2` from it. Before carrying a MERGE-PARENT-OPEN parent's
residuals: `bd list --status closed --limit 0 | grep 'review of <parent>'`,
open that bead, read its children. (2) I dispatched `eng3.7` (filed 08-30)
whose "dead guard" was the live quiet exit `eng3.3.1` had installed on
08-29; the Forge deleted a reviewed behaviour and the Warden caught it. Before
dispatching any bead older than a few days: `git log --since=<filed date> --
<its files>` and read what landed there. If a finding names a line, look at
that line on main first.

**`bd list` without `--status` hides closed beads.** I asked
`bd list | grep -c 'b0vj.65\.'`, got 0, and decomposed a parent into three
duplicates of CLOSED work. One would have reversed an approved gate-2
migration. The Forge refused it twice; that refusal, not any check of mine,
is why nothing was damaged. Worse: I had caught this exact flaw an hour
earlier on a different query and never re-ran the earlier check. **Finding
that a tool lies is half the work; going back through what you concluded
with it is the other half.** Before decomposing:
`for s in open in_progress closed; do bd list --status=$s --limit 0 | grep 'fortkit-<parent>\.'; done`

**bd copies parent labels onto children at create.** Decomposing an escalated
bead gave the new child `fleet-escalated` (permanently undispatchable) plus
`fleet-return-1/2` (a false record of failures that never happened). Check
the child's labels immediately after every `--parent` create (Proofdelve ForgeOs-bbdr).

**Backticks in a double-quoted bash string execute.** My cycle-3 log
contained `` `bd list` `` unescaped; the shell ran it and injected its output
into an append-only record. Always `"$(cat <<'EOF' ... EOF)"` with the
delimiter QUOTED. Command-substitution output is not re-scanned.

**The fleet reopens a bead you closed if its worker is still settling.** The
return-and-escalate path writes labels without checking status
(Proofdelve ForgeOs-x2lv). Strip `fleet-safe` FIRST, then close, then verify the status
by reading it back. Check every close you made when you find one reopened.

**A grep can match the wrong thing and you file a bug.** `grep -c '9t5v'`
matched the TITLE of another bead. I nearly filed a direction-blindness bug in
the dependency guard that does not exist. Prove a negative with `--json` and
an exact-id comparison.

**Prose blockers do not gate dispatch.** vlyo.1 said "blocked on vlyo" in its
description; the fleet dispatched it anyway. `bd dep add <bead> <blocker>`.
`prose-blockers.py` finds the gap; it was proven in four outcomes and two
failed first time (a full stop swallowed into an id; a satisfied gate read as
missing). Never trust a checker that has not been shown to fire.

**A sweep criterion does not work on this fort's spec documents.** Three
consecutive sweeps of the parity inventory each fixed the last miss and
introduced a new one, two under criteria written to prevent it. Stale figures
live in METHODOLOGY PROSE, not tables. Ask for a mechanical enumeration
(Proofdelve ForgeOs-scmm), never a fourth sweep.

**Warden review is a snapshot; the tree moves.** Three findings I nearly
filed were already fixed by a later round or a sibling. One grep each.

**The Warden cannot execute any inversion.** node, `npm --prefix tools/keep`,
python3, sed, `bash <harness>`, and any source mutation are all denied
(Proofdelve ForgeOs-mskx, Proofdelve ForgeOs-51x1). Every "prove it goes RED" criterion is
Forge-pasted evidence she corroborates by reading. Write the criterion so the
Forge pastes the run; do not demand `--reporter=verbose` (a form), demand
that the tests executed (a property).

**Verifier output outruns the Forge's 30-second command window.** Seven
handoffs on 09-15 said "not verified" while the launcher stamp on the same
file said verified. The Forge is blameless in all seven: it refused to claim a
gate it had not seen. Read stamps, not bodies (Proofdelve ForgeOs-y4rg).

## Two things that stall the fleet from the Mayor's own chair

**An uncommitted tracked edit in the main checkout blocks EVERY fleet merge.**
The landability check (`landable_why`) refuses main while it carries
uncommitted tracked SOURCE changes, and the fleet defers each merge with
"NOT MERGED this pass". On 2026-09-16 I edited a ledger fact at 04:20, meant
to commit it "with the checkpoint", and held up two merged verdicts (`eng3.6`,
`qiyc`) for 33 minutes before the fleet log told me. Commit or stash a
source edit the moment it is lint-clean; never park one. (`fort/events/*.jsonl`
is exempt: the check names SOURCE.)

**A directory prefix in a gate-1 bead's `Touches:` is held all night.** An
escalated gate-1 worker keeps its touch set until the branch lands, which is
the morning signature. `9ysx` declared `src/Product.Api/` and
`tests/Product.Tests/` and starved every .NET bead from 01:34 until I found it
at 03:00 and narrowed the settled worker's `touches` file to the branch's
actual files (declared set kept beside it). Declare gate-1 beads by FILE, and
when one escalates, check what its worker holds:
`cat ~/.local/state/manyhalls-fleet/workers/<sfx>/touches`.

**Backticks in a `bd create --title` inside double quotes execute** (`reason`
-> "command not found", title shipped with a hole). Single-quote titles or
keep backticks out of them; the heredoc rule below covers descriptions only.

## Two shell traps

1. `bd update --description/--acceptance/--notes` REPLACE. Only `bd comment`
   appends. `add-touches.py` shows the safe pattern: read old, append, write,
   read back, assert the original is still present.
2. Never `ls`, `cat`, `stat` or `test` anything matching `.env*`. Gate 4. The
   policy layer denied it once on 09-15 mid-command; do not retry in another
   spelling (Proofdelve ForgeOs-21f.8 measured obfuscated spellings defeating globs 6/6).

## Loop prompt (the one that ran 18 cycles)

Replace `<runlog>` and the date. Keep it self-contained.

```
UNATTENDED FLEET RUN, <date>. You are the Mayor, Mayor of Manyhalls.
The Overseer is away and asked the fort to keep the fleet fuelled without him.
Do NOT go quiet, and do NOT wait for him to answer anything.

FIRST read fort/checklists/unattended-fleet-run.md, then the run log and its
authorizations: `bd show fortkit-<runlog> --json`. If your context was
compacted, those two plus fort/seats/mayor.md are your whole brief.

THEN run the cycle in fort/checklists/unattended-fleet-run.md in order: health, inbox, depth, stock,
queue-lint, push ONLY through scripts/push-ready.sh AND only while the grant on
the run log is unexpired, commit records right AFTER a push, log by bd comment
with a quoted heredoc. A red-main HALT may be cleared only under grant 2's
conditions in the checklist (diagnosis recorded, narrow fix, verify.sh green at
the exact HEAD, explainable, once per night). NEVER request an airlock deploy
unattended.

Keep working through beads for as long as you can. If everything is healthy
and the queue is deep, go further down the backlog rather than reporting that
there is nothing to do. If the Overseer speaks in this session, ask before
deleting this cron.
```

## Six more from the second run (night of 2026-09-16/17, 42 fleet merges, 24 pushes)

**Push the SHA push-ready verified, never the ref.** `scripts/push-ready.sh`
checked `10fb530`; in the four seconds before `git push origin main` the fleet
merged `47r`, and the push shipped `01c01177` 78 s before its post-merge
verify (01:54). The ref is whatever main is at that instant. Form:
`SHA=$(scripts/push-ready.sh | grep -oE 'HEAD [0-9a-f]+' | awk '{print $2}')
&& git push origin "$SHA:main"`, and the emit names the same SHA.

**A hand reopen keeps the assignee, and the fleet's claim refuses it every
pass.** `bd update zx04.1 --status open` (04:17) left `assignee=kethra`; three
passes of "claim refused" wrote a STALL halt (04:29). Reopen with
`--status open --assignee ""` in one command. The
fleet-claim-refused-means-assignee-set memory already said so; a rule you
have read is not a rule you have applied.

**Never write "run from a worktree" into a Forge criterion.** The mask refuses
`git worktree add` (`.git/worktrees` is read-only there), and an honest Forge
stops rather than substitute: `46xh` lap 1 and `31s6.1` lap 1 each did the
work, left it uncommitted, and handed off. Say "copy the harness and its
target into a temp directory with the same relative layout".

**Name the full suite in the criteria, or the Forge runs its own class.**
`yigf.1` shipped an intended behaviour change that broke two tests in files
outside its touch set; the host verifier failed twice on the same two names,
the fleet's return evidence listed them, and lap 2 committed only a handoff.
Criteria say: build first, then `dotnet test ... --filter
'FullyQualifiedName!~MigrationTests'`, in the background redirected to a
file if the window cuts it, and the paste shows the runner summary. And put
every file a behaviour change can reach into the touch set, not only the
files being edited.

**A Forge that closes its own bead is an incident, not a tidy finish.**
`zx04.1` was closed "gates green" at 03:59:53, six minutes before
REQUEST-CHANGES; the fleet's return pass correctly wrote nothing to a closed
bead and the work would have been lost without a person. Emit `incident`,
reopen (assignee cleared), note it on `dx34.19`.

**Window the event query from the previous cycle's START.** Windowing from
its end missed a merge that landed while that cycle was running (`91p2.20.1`,
cycle 6). Also: a bead's "in flight" state is invisible if you filter
`"actor":"kethra"` out; the claim events are the fleet's, the progress events
are hers.

## Five more from the day run (2026-09-17, 45 fleet merges by 12:33) and the fort day

**Hold a cleanup that touches a hot shared file until the P1 chain on that file
has landed.** Measured 2026-10-15 14:48-14:5x: the moment the parcel-economics
migration landed and its P1 server chain unblocked, the fleet dispatched my P2
cleanup `2md9d.3.26` (Entities.cs, MigrationTests.cs) first, and 21 candidates
sat behind it with 4 slots free. A live Forge cannot be preempted. File such a
cleanup with a `held-for-<chain>` label instead of `fleet-safe`, and release it
when the chain lands.

**After a Regent sitting, read the docket bead's comments before filing a
covenant review.** On 2026-10-15 the Regent had the Warden review the 9dqa6 sitting
inside the sitting (verdicts on the docket, plus a fold commit), and the Mayor
filed and launched a duplicate (`Proofdelve ForgeOs-t8cve`) that also nearly missed that the
push must include the fold. Push only a ref that contains every fold the
verdicts name (`git merge-base --is-ancestor <fold> <sha>`).

**No Mayor commit to main between a fleet host verify and its merge**
(`Proofdelve ForgeOs-s1reg`, in force from 2026-10-19). The fleet skips the post-merge
verify only when the merged tree IS the tree its host verifier passed; a commit
of yours in that window moves main, the trees differ, and the ~10-minute
post-merge run happens after all. Records and doc commits batch at push time.

**Commit records right AFTER a push, never between a merge and its post-merge
verify.** A Mayor records commit on top of a fleet merge puts HEAD past the
verified tip, and push-ready answers WAIT until the NEXT merge (`Proofdelve ForgeOs-qhr2s`).
On the 2026-10-14/15 night this cost a push window at least five times. Order:
wait for the post-merge, push the YES SHA, then commit the export and events.

**A SHA comes only from a `push-ready: YES` line.** The WAIT message contains
"HEAD <sha>" too, so `grep -oE 'HEAD [0-9a-f]+'` over the whole output scrapes
a SHA off a refusal; `c66c7506` was pushed on a WAIT that way (12:0x). Form:
`SHA=$(scripts/push-ready.sh | grep '^push-ready: YES' | grep -oE 'HEAD [0-9a-f]+'
| awk '{print $2}')`, and `[ -n "$SHA" ]` before the push.

**`Touches:` goes in the DESCRIPTION, never the acceptance field.**
`fleet.sh touch_set_of` and `queue-lint.sh` read `description` only; a
`Touches:` line under `--acceptance` is invisible and the bead claims the whole
repository. Seven beads stocked that way on the fort day all came back
UNDECLARED from queue-lint, which is the check doing its job. Description
updates REPLACE, so fetch the old text and append.

**A starved P1 behind lower-priority beads that share its files: narrow, then
hold.** The touch-set guard is correct and blind to priority: `aqc6.2.3.1`
(signed) waited 2h07m while `b0vj.28.3/.4`, `seqx.1`, `nf17`, `d5yi.1` were
claimed into the files it overlapped. Fix in two moves: narrow the P1's touch
set to the branch's REAL files (`git diff --name-only main...bead/x`), and swap
`fleet-safe` for a hold label (`held-for-<id>`) on every overlapping bead until
the P1 is claimed, then swap back.

**A signed branch whose refresh conflicts (exit 76) needs a landing-lap
child, and the child merges the PARENT'S branch into ITS OWN.** The Forge owns
only its own worktree (`--rw-tree $wt`); a description that says "work in the
parent's worktree and merge main" produces a handoff-only return (`o6ct.1` lap
one, 04:10 on 09-18). Write it as: in `fortkit-worktrees/<child>` on
`bead/<child>` (cut from main), `git merge bead/<parent>`, resolve, verify; the
child branch is main plus the parent's work, and the Warden re-escalates on it. The Forge merges main into the branch in-session, resolves, commits;
the Warden re-escalates on the resolved diff; one more signature. `aqc6.2.3.1`,
`2ibw.9.1`, `seqx.1.1` are the pattern; the child's touch set is the branch's
files, nothing wider.

**A plain Approve on a Mayor-lane bead re-queues it to the fleet.** The desk
restores `fleet-safe` on a bare Approve; a bead whose file the Forge cannot
write (verify-impl.sh, seat files) then dies at the last step. When a bead
needs a decision written in, his input, or a patch for his hand, ask him for
the NOTE button, not Approve, and say so in the ask.

**Codex outage looks like fleet returns.** Every Forge exits 1 at launch within
seconds; the return counters climb on beads that were never worked. Read one
forge.log, HALT, strip the false `fleet-return-N` labels, and wait for him to
reset usage or the vendor to recover.

**Never add a blocks edge between a parent and its own child.** `bd dep add
<parent> <child>` on top of the parent-child edge made bd report BOTH beads
blocked (04:00 on 09-18: `o6ct.1` never reached `bd ready` and the run drained
around it). A landing-lap child needs no edge: the parent is already out of the
fleet (fleet-safe removed) and MERGE-PARENT-OPEN keeps parents open without one.
And check the child's labels the moment it is filed: the fleet's page on the
parent can land seconds before the create and ride onto the child.

**Stock the bead that exists.** At 23:14 on 09-17 six product test beads were
stocked as NEW children beside their originals (oogf.4 beside oogf.1, and so
on), leaving six duplicates open until a Warden's measurement exposed one. A
new id is for a changed scope or a fold; adding criteria and a `Touches:` line
to the original is `bd update --acceptance`/`--description` (REPLACE: fetch the
old text and append).

**A new verifier step ships warn-only and earns its red on a soak.** The
bead-citation-check step went from written to hard gate in one commit at
23:2x on 09-17 and halted the fleet on its first post-merge run at 23:44, on a
green product: it compared citations against a tracked export that always lags
the beads filed that day. Any step whose input is a snapshot (an export, a
cache, a fixture regenerated by hand) must run as a warning through at least
one night of landings before it may fail the gate, and the Mayor never wires a
hard step while the fleet is mid-run and she cannot watch the first post-merge.
The fix was one env var; the cost was a red-main halt the Overseer had said
never to clear, cleared on a reasoned exception recorded on the run log.

**Uncommitted tracked edits in the root defer every merge**, source or docs
alike (`fleet.deferred ... not landable: uncommitted tracked SOURCE changes:
docs/patch-notes/...`, 12:28 on 09-17). Record files (`fort/events/*.jsonl`,
`.beads/interactions.jsonl`) are exempt; anything else, including a patch-notes
draft, parks the landing until it is committed.

**A `Touches:` line that names a DIRECTORY serialises the bead behind every
other bead touching anything inside it.** Measured 2026-09-19 10:42: four beads
filed in one sitting all declared `tests/Product.Tests`, and the co-dispatch
guard held four candidates behind one live Forge on
`tests/Product.Tests/ExternalSubjectCollisionTests.cs ~ tests/Product.Tests`. The
set is a PREFIX set, so the directory form overlaps every test file in the
repository. Name the FILE, including the file the new tests will be written in,
which means deciding that name at filing time and saying so in the bead. The
touch set is advisory (the fleet never enforces it against the diff), so a
narrower set risks nothing and a wider one costs throughput directly.
`scripts/unattended-fleet/retouch.py` replaces the line and proves it.

**A verifier you just wrote gets one adversarial read before you trust its
failure.** retouch.py's first version asserted `old not in new_description` to
prove the old touch set was gone. That is trivially false whenever the new value
CONTAINS the old as a prefix substring, which is precisely the
`tests/Product.Tests` -> `tests/Product.Tests/FooTests.cs` case it existed for,
so it reported FAIL on four correct writes. A check that cries wolf on its own
intended input is worse than no check, because the next hand learns to re-run it
with the assertion commented out. Ask what input makes this check wrong, not only
what input makes the subject wrong.

**An assertion over a command's WHOLE output can pass on incidental content.**
Measured 2026-09-19 on `locked-dir-clean-harness.sh`: the property under test was
that the failure message names WHICH kernel-locked directory grew a file, and the
assertion asked whether the output contained the directory name anywhere. It always
does, because `git ls-files --others -- fort/scripts` prints
`fort/scripts/stray.bak`, so the name arrives through the FILE LISTING whether or
not the header names it. A mutation that stripped the directory from the header
scored 8 pass / 0 fail. Anchor the assertion to the line or structure that carries
the property (here, a `grep -qE "kernel-locked directory <d>( |:|$)"` over the
header), and then re-run the mutation to confirm it goes red. The general form: ask
which OTHER part of the output could satisfy this assertion, not only whether the
right part does.

**`verify.sh` exit 0 does not prove a new step RAN.** `run_step` does not echo the
step name (`scripts/verify-impl.sh:263`); a step is visible only through its own
output. So after wiring a step, confirm it by a signature only that step emits (its
subject line, its `RESULT n pass / n fail`, a case name unique to it) and quote the
line number. On 2026-09-19 a full pass returned exit 0 with only three occurrences
of the word "harness" in 6,647 lines, which looks exactly like the steps not
running; they had run, and the grep was wrong. Either way, the exit code was not the
evidence.

## Host tests and red arms go through the airlock (Proofdelve ForgeOs-emshb, 2026-10-23)

Since the Regent sitting of 2026-10-23 (docket `fort/annals/regent-docket-2026-10-22-airlock-fleet.txt`, item A), a Docker-backed test the masked seats cannot run is REQUESTED, not handed to the Overseer:

```bash
fort/scripts/airlock.sh request host-test --reason "<bead>: <why>" \
  --param target=<main|bead id> --param filter='<dotnet test filter>' \
  [--param mutate=fort/airlock/requests/<name>.patch]   # a red arm: the patch lives where git ignores it, inside the bead's worktree
fort/scripts/airlock.sh show <id>        # the result; the log is fort/airlock/results/<id>.log
```

- `host-test` is `auto_run` with no approval line: the host runner executes it. `preview` still needs his Approve on the Civ Keep (that click is the "keep button"); `preview-stop` does not.
- Params are matched whole against the table in `fort/airlock/operations.json` and passed as arguments; anything else is refused with exit 64 before a script runs. A `mutate` patch must not dirty the worktree (`host-test.sh` refuses a dirty tree).
- **A red arm (`mutate`) needs a CLEAN bead worktree, never `target=main`:** `host-test.sh --mutate` refuses any `git status --porcelain` output, and the main checkout always carries untracked files, so it refuses every time. Measured 2026-10-23 on Proofdelve ForgeOs-7d540: the patch went in the bead's own worktree (`fortkit-worktrees/7d540/fort/airlock/requests/`, git-ignored) with `target=7d540`; red 23503 FK violation 1/0, green control 1/0. Always run the unpatched green control with the same filter.
- **The Mayor is the requester today.** A Forge cannot file one: `airlock.sh` resolves its root from its own location, so a worktree's copy writes into the worktree's `requests/`, which the runner never reads.
- This replaces `flag-human.sh <id> "..." run host test` for tests and red arms. It does NOT replace the gate 2 run: a migration bead still waits for his own host MigrationTests run and signature until he says otherwise.

## Whose move (Proofdelve ForgeOs-29j3g)

Since 2026-10-19 the Overseer's board is **the open beads assigned to `justin`**,
in the Civ Keep and this fort's Keep alike. To put something on it, use
`scripts/flag-human.sh <id> "<one line>" [sign|grant|decide|run host test|answer]`:
it posts the `ASK:` line and assigns him in one update. Never park a bead with
`human` and no assignee; that is nobody's board. `fleet-escalated` beads are
assigned to `emrith` and read with `bd list --assignee emrith`. His answers
move the bead on by themselves (a bare Approve back to the fleet, anything else
to the Mayor), so "what is waiting on him" is one query:
`bd list --assignee justin --status open`, and `scripts/queue-lint.sh` names any
bead on it without an `ASK:` line.

## Verify once (Proofdelve ForgeOs-s1reg)

Since 2026-10-19 a bead is verified ONCE on its way to main:

- **The host verify is tiered from the bead's diff**, by `fleet.sh`
  (`verify_tier_of`), never by a seat: `docs` (docs/, fort/handoffs/), `web`,
  `server`, `harness` (scripts/, tools/keep/), else `full`. Migrations, the
  auth/visibility surface, fort/ other than handoffs, `verify-impl.sh` itself,
  and any unknown path force `full`. The run's log names the tier, skipped
  steps print `SKIP`, and `verify.pass` carries `tier` and `skippedSteps`.
- **The post-merge verify is REUSED** (no second run, a `verify.pass` with
  `reused:true`, `verifiedTree`, `verifiedCommit`) only when the merge commit's
  tree equals the tree the host verify passed AND that run was `full` with
  Docker up. Otherwise it runs as before, and the run log says why
  (`post-merge verify RUNS: ...`). `push-ready.sh` accepts a reused pass only on
  that tree equality, checked itself.
- **The backstop is the nightly full verify** of main at 03:30
  (`manyhalls-nightly-verify.timer`, `fort/scripts/nightly-verify.sh`): every
  step, Docker required, in a fresh worktree. A RED writes the halt file, keeps
  the worktree, and emits an incident, exactly like a post-merge RED.
- **Kill switches are the Overseer's, in `fleet.conf`:** `FLEET_VERIFY_TIERS=off`
  (every host verify full) and `FLEET_VERIFY_REUSE=off` (every landing runs the
  post-merge verify). If the nightly timer is ever off, turn both off.

## Close-out

Kill the cron. Ask about unpushed commits (the grant expired). Write
`fort/handoffs/mayor-<date>.md` per the seat schema. Commit path-scoped:
handoff, event stream, any ledger facts, this skill if changed. Do not push
without his word.

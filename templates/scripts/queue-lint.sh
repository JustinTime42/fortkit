#!/bin/bash
# queue-lint.sh -- what the Mayor checks before trusting the fleet queue.
#
# SIX FAILURES THIS CATCHES, every one measured on 2026-09-15, 2026-09-16, or
# 2026-09-17.
#
# 1. A fleet-safe bead with no `Touches:` line takes <everything> (fleet.sh:1429,
#    deliberately conservative) and therefore blocks every other candidate while
#    it runs. Ten such beads ran the fleet at concurrency 1 all afternoon with a
#    ceiling of 6 and eight candidates waiting (Proofdelve ForgeOs-vky8 measured the guard
#    itself as clean; the undeclared beads were the cause).
# 2. A fleet-safe bead whose touch set names a path the FORGE CANNOT WRITE. The
#    Forge dies on a read-only filesystem at whatever step needs it, having done
#    the rest, and nothing explains why. Proofdelve ForgeOs-odew was filed this way.
#
# 3. A fleet-safe bead WHOSE WORK IS ALREADY MERGED (Proofdelve ForgeOs-ursv, added
#    2026-09-15). A MERGE-PARENT-OPEN verdict merges the diff and deliberately
#    leaves the parent open, because the reviewer found the diff sound and at
#    least one acceptance criterion unmet. fleet.sh files a triage bead at the
#    same moment and that part works. What does not work is that the parent is
#    then INDISTINGUISHABLE FROM FRESH WORK: open, in `bd ready`, still carrying
#    its original acceptance criteria, with nothing on it saying the diff is
#    already on main. Measured the day this was written: the Mayor marked
#    Proofdelve ForgeOs-7hxc fleet-safe four hours after it merged at 624a4ca, and the fleet
#    spent two Forge launches and two returns reporting "no product change:
#    handoff only" before escalating. Five such parents were open at that moment.
#    The id is matched EXACTLY against the parsed commit subject rather than by a
#    regex per bead, because ids share prefixes -- b0vj.5 and b0vj.51 both exist,
#    and a loose match would report one bead on the other's merge commit.
#
# 4. A fleet-safe bead whose touch set names a path THAT DOES NOT EXIST
#    (Proofdelve ForgeOs-ij4q, Warden finding 3, added 2026-09-15). Proofdelve ForgeOs-5648 declared
#    web/src/test/format.test.ts; the real file is web/src/utils/format.test.ts
#    and web/src/test/ does not exist at all. The Forge edited the right file, so
#    this reads as a cosmetic slip -- and it is not. A touch set reserves the
#    paths it names, so a misspelt one RESERVES NOTHING, and fleet.sh's
#    co-dispatch guard silently stops protecting the file the bead actually
#    edits: another Forge can be dispatched onto it in the same pass. The
#    discriminator is the DIRECTORY, not the file, because a bead that creates a
#    new file names a nonexistent path legitimately.
#
# 5. A Mayor answer left in `mayor-review` with no worker and no `human` label
#    is invisible to the Overseer's needs-you queue. Both labels are likewise a
#    broken turn boundary: one bead cannot belong to both turns.
#
# 6. A fleet-safe bead declares a blocker in prose but has no corresponding bd
#    blocking edge. This is reported as a CANDIDATE, never acted upon: wording
#    alone cannot prove intent. The checker quotes its matched sentence.
#
# 7. A fleet-safe bead with MORE THAN ONE `Touches:` line, or `Touches:` in the
#    middle of a line (Proofdelve ForgeOs-29j3g item 8). fleet.sh's touch_set_of() reads
#    only the FIRST line that begins with it: ~12 beads filed on 2026-10-19 with
#    one line per file were guarded on one file each, and a mid-line spelling is
#    not read at all, so the bead silently takes <everything>.
#
# 8. A bead ON THE OVERSEER'S BOARD WITH NO ASK LINE (Proofdelve ForgeOs-29j3g). Since the
#    cut-over his board is exactly the open beads assigned to justin, and every
#    hand-off posts one comment line beginning "ASK:". A bead assigned to him
#    with none shows on his board with no reason.
#
# 9. A DECLINED BEAD RE-RELEASED WITHOUT A LAP (Proofdelve ForgeOs-n1wbd, the lint half of
#    Proofdelve ForgeOs-0x25g option a). The Overseer's newest decision on a fleet-safe bead
#    in the event stream is gate.declined and no open child (lap) exists. A
#    Decline means "not this tip": re-releasing the bead makes the fleet try to
#    land the declined work again (measured 2026-10-14 on 2md9d.1.12, and the
#    loop 0x25g describes). A lap is a CHILD bead, matched by id prefix or a
#    parent-child edge; laps carry no blocks edge (it deadlocks them, 10-21).
# 10. A Touches: TOKEN THAT IS NOT A PATH (Proofdelve ForgeOs-n1wbd ADD). fleet.sh splits the
#    line on spaces and commas, so "Foo.cs (new file)" reserves "(new" and
#    "file)", and every bead naming them collides: seven beads serialised on
#    2026-10-21. Any token with a character a repo path here never uses is
#    reported.
#
# Reports and never acts. Exit 0 clean, 1 findings, 3 could not ask.
# QUEUE_LINT_BD_TIMEOUT is a harness-only timeout (default 60); an invalid value
# exits 3. It is not an operator tuning knob.
set -uo pipefail
root="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)" || exit 3

# --backlog: THE MAYOR'S SITTING SLICE, and deliberately NOT part of the default
# run (Proofdelve ForgeOs-mfyq, 2026-09-21). Everything above this line answers "may the
# fleet dispatch right now?" and runs at session start and after every
# fleet-safe filing, so it has to stay fast. These two answer "what has rotted
# while we were not looking?", which is a question for a scheduled sitting and
# never a gate: both checks EXIT 0 whatever they find, and --backlog cannot turn
# a clean queue red.
#
# It takes its own fresh `bd export` rather than reading the tracked
# .beads/issues.jsonl. That file is a passive export refreshed by hand, and a
# board one bead out of date gives a confidently wrong answer: measured
# 2026-09-21, the committed export still showed Proofdelve ForgeOs-sk3c.2 open minutes
# after it was closed, so the stale-parent check reported a bead that had
# already been dealt with.
if [ "${1:-}" = "--backlog" ]; then
  cd "$root" || exit 3
  board="$(mktemp)" || exit 3
  trap 'rm -f "$board"' EXIT
  bd -C "$root" export -o "$board" >/dev/null 2>&1 || {
    echo "queue-lint: INFRASTRUCTURE REFUSAL: bd export refused; cannot read the board" >&2; exit 3; }
  as_list() { python3 -c '
import json,sys
print(json.dumps([json.loads(l) for l in open(sys.argv[1]) if l.strip()]))' "$board"; }
  echo "=== EXPIRED DEFERRALS -- a bead this one waited on has since closed"
  as_list | ROOT="$root" python3 "$root/scripts/unattended-fleet/prose-blockers.py" --expired || exit 3
  echo
  echo "=== STALE PARENTS -- every child closed; is anything of the parent's own left?"
  as_list | python3 "$root/scripts/unattended-fleet/stale-parents.py" || exit 3
  echo
  echo "=== MISROUTED GATE-6 WORK -- open unrouted beads the Forge cannot finish"
  as_list | ROOT="$root" python3 "$root/scripts/unattended-fleet/misrouted.py" || exit 3
  echo
  echo "=== UNSHAPED WORK -- open, unrouted beads that name no file"
  as_list | ROOT="$root" python3 "$root/scripts/unattended-fleet/unshaped.py" || exit 3
  exit 0
fi

# Kernel read-only to the Forge. Sources: fort/scripts/forge.sh mask list,
# fort/scripts/lib/seat-sandbox.sh, charter "Prose gates" cycle 7.
FORGE_RO=(
  "scripts/verify-impl.sh"
  "fort/scripts/"
  "fort/profiles/"
  "fort/charter.md"
  "fort/seats/"
  ".claude/"
)

# EVERY fleet-safe bead, including historical parents needed for inheritance.
# bd list with --status all is the complete labelled board; the filter below
# keeps closed work out of the audit while allowing closed parent status to be
# resolved from this same documented payload. bd ready --label
# fleet-safe returned 6 while 14 carried the label (measured 2026-09-15): the
# rest were in_progress or blocked, and a bad touch set on those is latent rather
# than absent -- it bites when the bead becomes dispatchable. The first version of
# this script asked `ready` and missed Proofdelve ForgeOs-cy60, a seat-file bead the Forge
# cannot write, in the very next case after it was written.
json="$(bd -C "$root" list --status all --label-any fleet-safe --limit 0 --json 2>/dev/null)" || exit 3
[ -n "$json" ] || exit 3
board_json="$(bd -C "$root" list --status all --limit 0 --json 2>/dev/null)" || exit 3
[ -n "$board_json" ] || exit 3
# shellcheck disable=SC2016 # The embedded Python is intentionally a literal.
printf '%s\0%s' "$json" "$board_json" | FORGE_RO="${FORGE_RO[*]}" ROOT="$root" FLEET_STATE="${FLEET_STATE:-$HOME/.local/state/{{FORT_SLUG}}-fleet}" python3 -c '
import json, math, os, re, subprocess, sys, tempfile
raw = sys.stdin.buffer.read().split(b"\0")
if len(raw) != 2 or not raw[0] or not raw[1] or raw[0] == b"null" or raw[1] == b"null":
    print("queue-lint: bd returned invalid queue data"); sys.exit(3)
fleet_raw, board_raw = (part.decode() for part in raw)
d = json.loads(fleet_raw)
if isinstance(d, dict): d = d.get("data", d)
no_fleet_safe = not d
fleet_by_id = {i.get("id"): i for i in d}
# Closed status is outside the audit. The two non-work labels are excluded only
# from workload denominators below; every per-bead safety check still sees them.
# fleet_by_id intentionally retains the complete --status all response above
# because a closed parent is evidence for LIKELY INHERITED rather than an audit
# row itself.
EXCLUDED_FROM_WORK_COUNTS = {"standing", "record"}
def counts_as_work(issue):
    return not EXCLUDED_FROM_WORK_COUNTS.intersection(issue.get("labels") or [])
d = [i for i in d if (i.get("status") or "open") != "closed"]
work_d = [i for i in d if counts_as_work(i)]
import datetime as _dt
board = json.loads(board_raw)
if isinstance(board, dict): board = board.get("data", board)
board_by_id = {i.get("id"): i for i in board}
open_beads = [i for i in board if (i.get("status") or "open") == "open"]
work_open_beads = [i for i in open_beads if counts_as_work(i)]
ro = os.environ["FORGE_RO"].split()
root = os.environ["ROOT"]
fleet_workers = os.path.join(os.environ["FLEET_STATE"], "workers")
raw_bd_timeout = os.environ.get("QUEUE_LINT_BD_TIMEOUT", "60")
try:
    bd_timeout = float(raw_bd_timeout)
    if not math.isfinite(bd_timeout) or bd_timeout <= 0:
        raise ValueError
except ValueError:
    print("queue-lint: invalid QUEUE_LINT_BD_TIMEOUT value: %s" % raw_bd_timeout)
    sys.exit(3)
# WHAT "LIVE" MEANS ON THE REAL BOARD (the Warden, eng3.15 round two; the fleet says so
# itself at fleet.sh:936-938). running / launching / orphaned are DERIVED from
# the filesystem and never stored: dispatch writes bead, started, run, touches
# and the child writes pid, with NO state file; the first stored token is
# in-hand, written by the reap pass AFTER the Forge has exited. So: a state
# file present means live only if its first field is in-hand; a state file
# ABSENT means the Forge is still in its session (or died without a record,
# which is also not a settled worker) unless an exit or done marker exists.
live_worker_states = {"in-hand"}

def has_live_worker(bead_id):
    """Match suffix-named fleet workers by their authoritative bead file."""
    try:
        workers = os.scandir(fleet_workers)
    except FileNotFoundError:
        return False
    except OSError as e:
        print("queue-lint: cannot read fleet workers: %s" % e); sys.exit(3)
    with workers:
        for worker in workers:
            if not worker.is_dir():
                continue
            try:
                with open(os.path.join(worker.path, "bead"), encoding="utf-8") as f:
                    worker_bead = f.readline().strip()
            except OSError:
                continue
            if worker_bead != bead_id:
                continue
            try:
                with open(os.path.join(worker.path, "state"), encoding="utf-8") as f:
                    worker_state = f.readline().split("|", 1)[0].strip()
            except FileNotFoundError:
                # No state file: the session is in flight unless it has ended.
                ended = any(os.path.exists(os.path.join(worker.path, m)) for m in ("exit", "done"))
                if not ended:
                    return True
                continue
            except OSError:
                continue
            if worker_state in live_worker_states:
                return True
    return False

def bd_query(args, context):
    """Ask bd once; an unavailable or slow bd is a refusal, never a finding."""
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=bd_timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        print("queue-lint: %s failed: %s" % (context, e)); sys.exit(3)
    if result.returncode != 0:
        print("queue-lint: %s failed: %s" % (context, result.stderr.strip()[:160]))
        sys.exit(3)
    return result.stdout

def touches_of(issue):
    """Normalise Touches to conflict prefixes: * ? and [ cut at their first occurrence."""
    desc = issue.get("description") or ""
    line = next((line.split("Touches:", 1)[1].strip() for line in desc.splitlines()
                 if line.strip().startswith("Touches:")), None)
    if line is None:
        return None
    prefixes = []
    for token in line.replace(",", " ").split():
        token = token.removeprefix("./")
        wildcard = min((index for index in (token.find("*"), token.find("?"), token.find("[")) if index >= 0), default=len(token))
        prefixes.append(token[:wildcard])
    return prefixes

# The citation checker owns identifier resolution. Feed it only the active
# fleet-safe/gate-ready slice of the board already fetched above, then surface
# its warn-only findings here, where the Mayor reads them after each filing.
# This deliberately makes no bd call per bead (or at all): queue-lint already
# holds the complete board in memory.
def report_unresolved_identifiers(issues):
    if os.environ.get("QUEUE_LINT_SKIP_IDENTIFIER_SURFACE") == "1":
        return
    selected = [issue for issue in issues
                if (issue.get("status") or "open") == "open"
                and {"fleet-safe", "gate-ready"}.intersection(issue.get("labels") or [])]
    if not selected:
        return
    checker_path = os.path.join(root, "scripts", "bead-citation-check.sh")
    # verify-impl deliberately runs its pinned harness against this queue-lint
    # source. Older pinned harnesses do not copy the checker into their
    # hermetic fixture, whereas production must always have it. Keep that
    # harness compatibility explicit without ever treating a missing production
    # checker as a clean result.
    if not os.path.isfile(checker_path):
        if os.environ.get("HARNESS_REAL_PYTHON3"):
            return
        print("queue-lint: identifier citation checker is missing: %s" % checker_path); sys.exit(3)
    fd, export_path = tempfile.mkstemp(prefix="queue-lint-citations-", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as export:
            for issue in selected:
                export.write(json.dumps(issue) + "\n")
        env = os.environ.copy()
        env["CITATION_EXPORT"] = export_path
        check = subprocess.run([checker_path, root],
                               capture_output=True, text=True, env=env)
    except OSError as e:
        print("queue-lint: identifier citation check failed: %s" % e); sys.exit(3)
    finally:
        try: os.unlink(export_path)
        except OSError: pass
    if check.returncode == 3:
        print("queue-lint: identifier citation check refused: %s" % check.stdout.strip()[:160]); sys.exit(3)
    if check.returncode not in (0, 1):
        print("queue-lint: identifier citation check failed with exit %d" % check.returncode); sys.exit(3)
    findings = [line for line in check.stdout.splitlines()
                if re.match(r"^  \S+  \S+  -- grep it before writing it$", line)]
    if findings:
        print("UNRESOLVED IDENTIFIERS -- open fleet-safe or gate-ready beads name code identifiers that do not resolve:")
        for finding in findings:
            print(finding)

# ONE git pass, then an EXACT id match. A regex per bead would have to defend
# against shared prefixes; parsing the subject and comparing strings cannot
# confuse b0vj.5 with b0vj.51 in the first place. A git that will not answer is
# a refusal (exit 3), never a clean sheet.
try:
    g = subprocess.run([
        "git", "-C", root, "log", "main", "--format=%h %s",
        "--grep", "merged by the fleet"],
        capture_output=True, text=True, timeout=60)
except Exception as e:
    print("queue-lint: git would not answer (%s)" % e); sys.exit(3)
if g.returncode != 0:
    print("queue-lint: git log failed: %s" % g.stderr.strip()[:160]); sys.exit(3)
merged_map = {}
for ln in g.stdout.splitlines():
    sha, _, subject = ln.partition(" ")
    m = re.match(r"([A-Za-z0-9][A-Za-z0-9._-]*): merged by the fleet", subject)
    if m:
        merged_map.setdefault(m.group(1), "%s %s" % (sha, subject))

undeclared, inherited, unwritable, already, misspelt, stalled, both_labels, fleet_human, fleet_escalated = [], [], [], [], [], [], [], [], []
touches_multi, touches_midline, ask_missing, touches_nonpath = [], [], [], []
for i in d:
    labels = set(i.get("labels") or [])
    # Proofdelve ForgeOs-29j3g item 8: only the FIRST line beginning "Touches:" is read.
    desc_lines = (i.get("description") or "").splitlines()
    if sum(1 for line in desc_lines if line.strip().startswith("Touches:")) > 1:
        touches_multi.append(i["id"])
    if any("Touches:" in line and not line.strip().startswith("Touches:") for line in desc_lines):
        touches_midline.append(i["id"])
    # fleet.sh:1264-1267 refuses these label collisions. Check both predicate
    # halves explicitly, independent of the label-filtering query above.
    if {"fleet-safe", "human"}.issubset(labels):
        fleet_human.append(i["id"])
    if {"fleet-safe", "fleet-escalated"}.issubset(labels):
        fleet_escalated.append(i["id"])
    # Only an OPEN bead can be dispatched, so only an open one can waste a
    # launch. A closed bead with a merge commit is the normal, finished case.
    if (i.get("status") or "") == "open" and i["id"] in merged_map:
        already.append((i["id"], merged_map[i["id"]]))
    touches = touches_of(i)
    if touches is None:
        parent = next((edge.get("depends_on_id") for edge in (i.get("dependencies") or [])
                       if edge.get("type") == "parent-child"), None)
        parent_status = (fleet_by_id.get(parent) or {}).get("status")
        if parent and parent_status == "closed":
            inherited.append((i["id"], parent)); continue
        undeclared.append(i["id"]); continue
    for tok in touches:
        if not re.fullmatch(r"[A-Za-z0-9._/*?\[\]-]+", tok):
            touches_nonpath.append((i["id"], tok))
        for r in ro:
            if tok.startswith(r) or r.startswith(tok):
                unwritable.append((i["id"], tok, r)); break
        # A MISSPELLED TOUCH PATH RESERVES NOTHING, so the co-dispatch guard
        # stops protecting the file the bead actually edits and another Forge
        # can be sent onto it. Silent, and it looks like tidiness.
        #
        # A path that does not exist is NOT enough on its own: a bead that
        # creates a new file names one legitimately. The discriminator is the
        # DIRECTORY. web/src/test/format.test.ts (Proofdelve ForgeOs-5648, measured
        # 2026-09-15) had no web/src/test/ at all -- the real file was
        # web/src/utils/format.test.ts. A new file inside an existing directory
        # is ordinary and is deliberately not reported.
        probe = tok.rstrip("/")
        if "*" in probe:
            probe = os.path.dirname(probe)
        if not probe:
            continue
        full = os.path.join(root, probe)
        if not os.path.exists(full):
            parent = os.path.dirname(full)
            if parent and not os.path.isdir(parent):
                misspelt.append((i["id"], tok, os.path.relpath(parent, root)))

# Proofdelve ForgeOs-29j3g: his board is the assignee; each bead on it needs an ASK line.
# Asked only of beads assigned to him, so a clean board costs no comment query.
for i in board:
    if (i.get("status") or "open") == "closed" or (i.get("assignee") or "") != "justin":
        continue
    comments = bd_query(["bd", "-C", root, "comments", i["id"], "--json"],
                        "comments query for %s" % i["id"])
    try:
        rows = json.loads(comments)
        if isinstance(rows, dict): rows = rows.get("data", rows)
    except json.JSONDecodeError:
        print("queue-lint: invalid comments for %s" % i["id"]); sys.exit(3)
    if not any(line.strip().startswith("ASK: ")
               for row in (rows or []) for line in str(row.get("text") or "").splitlines()):
        ask_missing.append(i["id"])

for i in open_beads:
    labels = set(i.get("labels") or [])
    if {"human", "mayor-review"}.issubset(labels):
        both_labels.append(i["id"])
        continue
    if "mayor-review" not in labels or "human" in labels:
        continue
    if has_live_worker(i["id"]):
        continue
    comments = bd_query(["bd", "-C", root, "comments", i["id"], "--json"],
                        "comments query for %s" % i["id"])
    try:
        rows = json.loads(comments)
        if isinstance(rows, dict): rows = rows.get("data", rows)
    except json.JSONDecodeError:
        print("queue-lint: invalid comments for %s" % i["id"]); sys.exit(3)
    if rows and (rows[-1].get("author") or "") == "{{MAYOR_ID}}":
        stalled.append(i["id"])
# Proofdelve ForgeOs-2ll5.1: a stale tracked export is indistinguishable from a fresh one
# at the point of reading. Compare its id set against the live open board; every
# open bead absent from it is a finding. A fort without a tracked export has
# nothing to compare (say so, no finding); an unreadable one is a refusal.
export_path = os.path.join(root, ".beads", "issues.jsonl")
export_missing = []
export_note = ""
if os.path.exists(export_path):
    try:
        exported = set()
        with open(export_path, encoding="utf-8") as ef:
            for line in ef:
                line = line.strip()
                if not line:
                    continue
                try:
                    exported.add(json.loads(line).get("id"))
                except ValueError:
                    continue      # a torn line is not an id
    except OSError as e:
        print("queue-lint: cannot read %s: %s" % (export_path, e)); sys.exit(3)
    export_missing = [i["id"] for i in open_beads if i["id"] not in exported]
else:
    export_note = "no tracked export at .beads/issues.jsonl; freshness not checked"
# Proofdelve ForgeOs-n1wbd: the newest Overseer gate decision per bead, from the event
# stream (actor justin, gate.approved / gate.declined; later lines win, files in
# date order). A fort with no event directory has nothing to compare: no finding.
declined_no_lap = []
events_dir = os.path.join(root, "fort", "events")
if os.path.isdir(events_dir):
    newest_decision = {}
    for name in sorted(n for n in os.listdir(events_dir) if re.fullmatch(r"events-\d{4}-\d{2}-\d{2}\.jsonl", n)):
        try:
            with open(os.path.join(events_dir, name), encoding="utf-8") as ef:
                for line in ef:
                    try:
                        e = json.loads(line)
                    except ValueError:
                        continue      # a torn line is not a decision
                    if e.get("actor") == "justin" and e.get("category") in ("gate.approved", "gate.declined"):
                        newest_decision[e.get("target")] = e.get("category")
        except OSError as err:
            print("queue-lint: cannot read %s: %s" % (name, err)); sys.exit(3)
    active = {"open", "in_progress"}
    for i in d:
        if newest_decision.get(i["id"]) != "gate.declined":
            continue
        has_lap = any((b.get("status") or "open") in active and (
                          (b.get("id") or "").startswith(i["id"] + ".")
                          or any(edge.get("type") == "parent-child" and edge.get("depends_on_id") == i["id"]
                                 for edge in (b.get("dependencies") or [])))
                      for b in board)
        if not has_lap:
            declined_no_lap.append(i["id"])
rc = 0
if declined_no_lap:
    rc = 1
    print("DECLINED ESCALATE RE-RELEASED WITHOUT A LAP -- his newest decision is a Decline and no open lap exists; the fleet would try to land the declined tip. File a child lap and remove fleet-safe here (Proofdelve ForgeOs-n1wbd):")
    for b in declined_no_lap: print("  %s" % b)
if touches_nonpath:
    rc = 1
    print("TOUCHES TOKEN IS NOT A PATH -- fleet.sh reserves it as one, so beads sharing it collide; move notes like (new file) to their own line (Proofdelve ForgeOs-n1wbd):")
    for b, tok in touches_nonpath: print("  %s declares %s" % (b, tok))
if export_missing:
    rc = 1
    print("EXPORT STALE -- %d open bead(s) absent from the tracked .beads/issues.jsonl (Proofdelve ForgeOs-2ll5.1). Refresh with scripts/bead-export.sh and commit it" % len(export_missing))
    for b in export_missing[:8]: print("  %s" % b)
    if len(export_missing) > 8: print("  ... and %d more" % (len(export_missing) - 8))
if touches_multi:
    rc = 1
    print("TOUCHES ON MORE THAN ONE LINE -- fleet.sh reads only the first, so the rest reserve nothing (Proofdelve ForgeOs-29j3g). Put every path on ONE Touches: line:")
    for b in touches_multi: print("  %s" % b)
if touches_midline:
    rc = 1
    print("TOUCHES MID-LINE -- fleet.sh reads only a line that BEGINS with Touches:, so this declares nothing (Proofdelve ForgeOs-29j3g):")
    for b in touches_midline: print("  %s" % b)
if ask_missing:
    rc = 1
    print("ON HIS BOARD WITH NO ASK LINE -- assigned to justin, no comment line beginning \"ASK:\", so the Keep shows no reason (Proofdelve ForgeOs-29j3g):")
    for b in ask_missing: print("  %s" % b)
if undeclared:
    rc = 1
    print("UNDECLARED -- these take <everything> and serialize the whole queue:")
    for b in undeclared: print("  %s" % b)
if inherited:
    rc = 1
    print("LIKELY INHERITED -- fleet-safe children with no Touches: whose closed parent likely passed on the label. Remove fleet-safe and review the create path:")
    for child, parent in inherited: print("  %s <- %s" % (child, parent))
if unwritable:
    rc = 1
    print("FORGE CANNOT WRITE -- fleet-safe but the lane cannot finish it:")
    for b, tok, r in unwritable: print("  %s declares %s (read-only: %s)" % (b, tok, r))
if misspelt:
    rc = 1
    print("TOUCH PATH DOES NOT EXIST -- and neither does its directory, so this")
    print("reserves nothing and the co-dispatch guard stops protecting the real file:")
    for b, tok, par in misspelt:
        print("  %s declares %s (no such directory: %s)" % (b, tok, par))
if already:
    rc = 1
    print("ALREADY MERGED -- fleet-safe, but the diff is on main; dispatching buys")
    print("a return of \"no product change: handoff only\". Triage it instead:")
    for b, line in already: print("  %s <- %s" % (b, line))
if both_labels:
    rc = 1
    print("BOTH TURN LABELS -- human and mayor-review cannot belong to one bead:")
    for b in both_labels: print("  %s carries human and mayor-review" % b)
if fleet_human:
    rc = 1
    print("FLEET/HUMAN CONTRADICTION -- fleet-safe and human cannot belong to one bead; resolve which label is premature or stale:")
    print("  fleet-safe is premature if the Overseer has not decided; human is stale if the Overseer has.")
    for b in fleet_human: print("  %s carries fleet-safe and human" % b)
if fleet_escalated:
    rc = 1
    print("FLEET/ESCALATED CONTRADICTION -- fleet-safe and fleet-escalated cannot belong to one bead; remove the inherited escalation label before dispatch:")
    for b in fleet_escalated: print("  %s carries fleet-safe and fleet-escalated" % b)
if stalled:
    rc = 1
    print("STALLED DIALOGUE -- the Mayor answered but did not hand the turn back:")
    for b in stalled: print("  %s has mayor-review, no human, no worker, and last comment by {{MAYOR_ID}}" % b)
# LANDING CLASS -- fleet.sh refuses a fleet-safe bead without either class,
# but that refusal is only a skip line in a fleet run. Keep the diagnosis here,
# on the queue surface the Mayor reads after marking a bead fleet-safe. The
# complete board is already in memory, so gate-ready work is visible before a
# Keep approval adds fleet-safe. Closed and deferred work cannot enter either
# transition; OPEN and IN_PROGRESS are the active states named by the policy.
active_landing_statuses = {"open", "in_progress"}
unclassified_fleet_safe = []
unclassified_gate_ready = []
both_landing_classes = []
for issue in board:
    if (issue.get("status") or "open") not in active_landing_statuses:
        continue
    labels = set(issue.get("labels") or [])
    has_sign_to_land = "sign-to-land" in labels
    has_lands_on_review = "lands-on-review" in labels
    if has_sign_to_land and has_lands_on_review:
        both_landing_classes.append(issue["id"])
    if not has_sign_to_land and not has_lands_on_review:
        if "fleet-safe" in labels:
            unclassified_fleet_safe.append(issue["id"])
        elif "gate-ready" in labels:
            unclassified_gate_ready.append(issue["id"])
if unclassified_fleet_safe:
    rc = 1
    print("UNCLASSIFIED FLEET-SAFE -- fleet-safe takes precedence over gate-ready because fleet dispatch requires a landing class: neither sign-to-land nor lands-on-review, so fleet.sh refuses dispatch")
    for b in unclassified_fleet_safe: print("  %s" % b)
if unclassified_gate_ready:
    rc = 1
    print("UNCLASSIFIED GATE-READY -- these active beads have neither sign-to-land nor lands-on-review:")
    for b in unclassified_gate_ready: print("  %s" % b)
if both_landing_classes:
    print("LANDING CLASS WARNING -- the fleet resolves both labels to sign-to-land:")
    for b in both_landing_classes: print("  %s carries sign-to-land and lands-on-review; fleet resolves it to sign-to-land" % b)

# STALE CRITERIA is a report-only surface. One export supplies every comment
# anchor in one call rather than one bd comments process per bead.
# The helper skips every first-parent commit whose subject starts with `<bead-id>:`.
stale_input = []
for issue in d:
    if (issue.get("status") or "open") != "open":
        continue
    touches = touches_of(issue)
    if not touches:
        continue
    if not issue.get("created_at"):
        # A malformed list record cannot be anchored to creation. Keep the
        # report-only check silent rather than turn queue-lint into a gate.
        continue
    stale_input.append({"id": issue["id"], "description": issue.get("description") or "",
                        "created_at": issue.get("created_at"), "touches": touches})
if stale_input:
    try:
        comments_export = None
        try:
            fd, comments_export = tempfile.mkstemp(prefix="queue-lint-comments-", text=True)
            os.close(fd)
            exported = subprocess.run(["bd", "-C", root, "export", "-o", comments_export],
                                      capture_output=True, text=True, timeout=bd_timeout)
            if exported.returncode:
                raise RuntimeError("cannot export comment anchors")
            comments_by_id = {}
            with open(comments_export, encoding="utf-8") as stream:
                for line in stream:
                    record = json.loads(line)
                    if record.get("_type") == "issue":
                        comments_by_id[record.get("id")] = [c.get("text") or "" for c in record.get("comments") or []]
            for item in stale_input:
                item["comments"] = comments_by_id.get(item["id"], [])
        finally:
            if comments_export:
                try: os.unlink(comments_export)
                except OSError: pass
        helper = os.path.join(root, "scripts", "unattended-fleet", "stale-criteria.py")
        criteria = subprocess.run(["python3", helper, root], input=json.dumps(stale_input),
                                  capture_output=True, text=True, timeout=60)
        if criteria.returncode:
            raise RuntimeError(criteria.stderr.strip()[:160] or "helper exited %d" % criteria.returncode)
        if criteria.stdout:
            print(criteria.stdout, end="")
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as e:
        print("STALE CRITERIA UNAVAILABLE -- %s" % e)
report_unresolved_identifiers(board)
# THE BACKLOG SITTING TRIGGER (Proofdelve ForgeOs-4dzt8, seat-file amendment approved
# 2026-09-21). An obligation with no trigger is a wish -- this seat file says so
# about the advisory channel, and ADV-0008 records the same failure at
# civilization level: the queue nobody reads is the failure mode. So the nudge
# goes on a surface the Mayor ALREADY reads every morning rather than on anyone
# memory.
#
# It is computed from the board ALREADY FETCHED above: zero extra bd calls, and
# no bd stale call in the hot path. It NEVER changes rc -- a backlog is not a
# queue defect and must never stop a dispatch or turn this check red.
stale30 = 0
_now = _dt.datetime.now(_dt.timezone.utc)
for i in work_open_beads:
    ts = (i.get("updated_at") or "").replace("Z", "+00:00")
    try:
        if (_now - _dt.datetime.fromisoformat(ts)).days > 30: stale30 += 1
    except Exception:
        pass
if stale30 > 40:
    print("BACKLOG SITTING DUE -- %d open beads untouched for 30+ days (threshold 40)." % stale30)
    print("  Run: scripts/queue-lint.sh --backlog     (reports only; it cannot turn this red)")

# DEPTH IS A REPORT, NOT A FINDING. It applies the fleet.sh dispatchable()
# rules to the workload slice using the two board slices already fetched above.
# standing and record are intentionally omitted here, so it can understate the
# dispatcher rather than claim those non-work classes are dispatchable. The
# list payload has bare edges, unlike the bd-show records used by fleet.sh, so each edge
# target is resolved from the complete second slice before its status or type is
# judged. Importing the fleet predicate is unavailable to this masked Forge
# (fleet.sh is kernel read-only), and another bd query would make DEPTH a stale
# second answer. bd show counts every dependency edge, whereas bd list and bd
# export count only blocks edges. Therefore a zero list/export count does not
# mean there are no edges to inspect. DEPTH must never overstate what the
# dispatcher could draw.
NONBLOCKING_DEPENDENCY_TYPES = {
    "tracks", "related", "parent-child", "discovered-from", "until",
    "caused-by", "validates", "relates-to", "supersedes",
}

def depth_dispatchable(issue):
    if (issue.get("status") or "open") != "open":
        return False
    if {"human", "fleet-escalated"} & set(issue.get("labels") or []):
        return False
    if "dependency_count" not in issue:
        return False
    dependencies = issue.get("dependencies")
    if dependencies is None:
        return not (issue.get("dependency_count") or 0)
    for dependency in dependencies:
        target = board_by_id.get(dependency.get("depends_on_id"))
        if target is None:
            return False
        status = (target.get("status") or "").lower()
        if status in {"closed", "done"}:
            continue
        if target.get("issue_type") == "gate":
            return False
        edge_type = (dependency.get("dependency_type") or dependency.get("type") or "").strip().lower()
        if edge_type not in NONBLOCKING_DEPENDENCY_TYPES:
            return False
    return True

dispatchable = [issue for issue in work_d if depth_dispatchable(issue)]
depth = len(dispatchable)
if depth == 0:
    print("DEPTH -- 0 fleet-safe, unblocked beads; queue is empty (0.0 hours at ~8 beads/hour).")
else:
    print("DEPTH -- %d fleet-safe, unblocked bead(s); %.1f hours at ~8 beads/hour." % (depth, depth / 8))

if no_fleet_safe:
    print("queue-lint: no fleet-safe beads")
if rc == 0:
    print("queue-lint: %d fleet-safe workload beads (everything except closed, standing, or record), %d open workload beads, all declared, all landing classes declared, all writable by the Forge, all real, none already merged, no stalled dialogue, export %s" % (len(work_d), len(work_open_beads), export_note or "fresh"))
sys.exit(rc)
'
core_rc=$?

# The prose checker receives the board already fetched above. A failed lookup is
# a refusal, never an apparently clean queue. Its findings are candidates only;
# queue-lint still returns 1 so the Mayor must inspect them before dispatch.
printf '%s' "$json" | ROOT="$root" python3 "$root/scripts/unattended-fleet/prose-blockers.py"
prose_rc=$?

# PROMPT SIZE (Proofdelve ForgeOs-2tz10, 2026-11-03). forge.sh hands the Forge `bd show <bead>`
# with every comment, and past 1,048,576 characters the session dies at turn/start
# (input_too_large) while the fleet records only "exit 1": Proofdelve ForgeOs-9gmk3's thread
# reached 1.8 MB from one pasted verify log. Flag any open fleet-safe bead whose
# text passes a third of the limit, so the Mayor supersedes it before dispatch.
# Raw text, because bd show's wrapping and indent render it about 1.5x larger
# (9gmk3: 1.2 MB of text became a 1.86 MB prompt). One bd export, not a bd show
# per bead: 26 shows took 85 s on 2026-11-03, the export 25 s.
prompt_limit="${QUEUE_LINT_PROMPT_LIMIT:-350000}"
# An export refusal skips this check with a warning, as the stale-criteria check
# does, rather than refusing the whole lint.
size_board="$(mktemp)" || exit 3
if ! bd -C "$root" export -o "$size_board" >/dev/null 2>&1; then
  echo "queue-lint: WARNING bd export refused; prompt sizes not checked this run" >&2
  : > "$size_board"
fi
oversized="$(printf '%s' "$json" | python3 -c '
import json,sys
board, limit = sys.argv[1], int(sys.argv[2])
wanted = {b["id"] for b in json.load(sys.stdin) if (b.get("status") or "open") != "closed"}
for line in open(board):
    if not line.strip(): continue
    b = json.loads(line)
    if b.get("id") not in wanted: continue
    n = len(b.get("description") or "") + sum(len(c.get("text") or "") for c in b.get("comments") or [])
    if n > limit: print("  %s -- %d characters of description and comments" % (b["id"], n))' "$size_board" "$prompt_limit")"
# EXPORT SIZE (2026-11-07). On 11-07 the full `bd export` reached 64.2 MB, past the
# Civ Keep's old 64 MiB read buffer, and the Overseer's board froze on an 07:16
# snapshot all day. fortkit's Keep now streams the export and keeps only a bounded
# view (closed beads older than 14 days become stubs), so it has no hard limit; it
# emits keep.stale when a refresh fails. This check stays as the tracker's own size
# guard (queue-lint, bead-export and every `bd export` caller pay for the size):
# warn at half the budget, fail at 85%. When it warns, run scripts/bead-archive.sh
# --dry-run (Proofdelve ForgeOs-a8yqk) and report to the Overseer.
export_rc=0
export_limit_mb="${QUEUE_LINT_EXPORT_LIMIT_MB:-256}"
export_bytes="$(wc -c < "$size_board" 2>/dev/null || echo 0)"
export_pct=$(( export_bytes * 100 / (export_limit_mb * 1048576) ))
if [ "$export_bytes" -gt 0 ] && [ "$export_pct" -ge 50 ]; then
  echo "EXPORT SIZE -- bd export is $(( export_bytes / 1048576 )) MiB, ${export_pct}% of the ${export_limit_mb} MiB tracker budget. Run scripts/bead-archive.sh --dry-run and report it to the Overseer before pruning."
  [ "$export_pct" -ge 85 ] && export_rc=1
fi
rm -f "$size_board"
size_rc=0
if [ -n "$oversized" ]; then
  echo "PROMPT SIZE -- open fleet-safe bead(s) past $prompt_limit characters of text; the Forge prompt (bd show, every comment) dies past 1048576. Supersede with a clean bead (Proofdelve ForgeOs-2tz10):"
  printf '%s\n' "$oversized"
  size_rc=1
fi
if [ "$core_rc" -eq 3 ] || { [ "$prose_rc" -ne 0 ] && [ "$prose_rc" -ne 1 ]; }; then
  if [ "$core_rc" -eq 3 ]; then
    echo "queue-lint: core queue checks refused with exit $core_rc" >&2
  else
    echo "queue-lint: prose-blockers failed with exit $prose_rc" >&2
  fi
  exit 3
fi
if [ "$core_rc" -ne 0 ] || [ "$prose_rc" -ne 0 ] || [ "$size_rc" -ne 0 ] || [ "$export_rc" -ne 0 ]; then
  exit 1
fi

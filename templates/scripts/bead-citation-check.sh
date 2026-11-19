#!/bin/bash
# bead-citation-check.sh -- every {{BEAD_PREFIX}}-<id> cited in shipped source resolves
# to a bead, none was created AFTER the commit that first cited it, and explicit
# identifier references in open bead work still name symbols in the tree.
#
# WHY (Proofdelve ForgeOs-x5u9). bd reissues ids it has no record of: Proofdelve ForgeOs-u65j.3.3.4
# was issued twice, and five source files cite the first meaning. A citation
# in a kernel-read-only launcher can therefore silently come to mean something
# else, and nothing goes red. Two signals, both cheap:
#   UNRESOLVED  the id is in no bead (typo, or a bead pruned; SO12 says never)
#   REISSUED    the bead exists but was created after the earliest commit that
#               cites it -- the citation predates the bead, so the id was
#               reused (or the cite was a guess).
#
# READS the tracked export .beads/issues.jsonl, never bd: the check must run
# inside the Warden's mask (no bd there, Proofdelve ForgeOs-278) and in the verifier at
# harness speed. A stale export is queue-lint's finding, not this one's; an
# absent export is a refusal (exit 3), never a clean sheet.
#
# Harness fixtures cite invented ids on purpose (dialogue, aaa and the like);
# paths matching *harness*, */test/*, *fixtures*, *.test.* are skipped, and the
# known findings are RECORDED in scripts/bead-citation-allow.txt with a reason
# each (a row there is a finding on file, not a pardon), so a new one goes red.
#
# Identifier references are deliberately narrow: only backticked PascalCase or
# dotted PascalCase tokens in open bead descriptions and acceptance criteria.
# They warn, never fail the existing citation gate: the purpose is to surface a
# stale or invented touch-set before a seat implements it, not to stop a build.
# A dotted C# reference resolves only when both its first (type) segment and
# terminal (member) segment occur in the tree. They need not be contiguous in
# a declaration (for example DealApplicationService.CreateUserAsync), but a
# plausible member on an invented type must not appear resolved by itself.
#
# Usage: bead-citation-check.sh [root]      exit 0 clean, 1 findings, 3 refusal
#   CITATION_EXPORT=<path>  override the export (the harness points it at a fixture)
#   CITATION_UNRESOLVED=warn   UNRESOLVED is reported but does not fail. THE
#     VERIFIER RUNS IN THIS MODE, measured 2026-09-17 23:44: the first
#     post-merge verify with this step as a hard gate went RED on
#     Proofdelve ForgeOs-ubgx.5, a bead filed that evening and cited in a README before
#     the tracked export was next refreshed, and HALTED the fleet on a green
#     product. The tracked export always lags beads filed today, so an
#     unresolved id in the gate is "not exported yet" far more often than
#     "does not exist"; REISSUED stays a failure everywhere, because it needs
#     the bead to be IN the export and is a real signal when it fires.
set -uo pipefail
root="${1:-$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel 2>/dev/null)}" || { echo "bead-citation-check: not a git tree"; exit 3; }
export_path="${CITATION_EXPORT:-$root/.beads/issues.jsonl}"
[ -r "$export_path" ] || { echo "bead-citation-check: cannot read $export_path -- refusing to guess"; exit 3; }
cd "$root" || exit 3
ROOT="$root" EXPORT_PATH="$export_path" python3 - <<'PY'
import json, os, re, subprocess, sys
root = os.environ["ROOT"]; export_path = os.environ["EXPORT_PATH"]
created = {}
open_beads = []
with open(export_path, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line: continue
        try: b = json.loads(line)
        except ValueError: continue
        if b.get("id"):
            created[b["id"]] = b.get("created_at") or ""
            if b.get("status") in ("open", "in_progress"):
                open_beads.append(b)
if not created:
    print("bead-citation-check: export holds no ids -- refusing to guess"); sys.exit(3)
allow = set()
allow_path = os.path.join(root, "scripts", "bead-citation-allow.txt")
if os.path.exists(allow_path):
    with open(allow_path, encoding="utf-8") as af:
        for line in af:
            line = line.strip()
            if line and not line.startswith("#"): allow.add(line.split()[0])
skip = re.compile(r"(harness|/test/|fixtures|\.test\.)")
scan = ["src", "test", "scripts", "fort/scripts", "bin", "civ/scripts", "docs"]
scan = [d for d in scan if os.path.isdir(os.path.join(root, d))]
g = subprocess.run(["grep", "-rnoE", r"{{BEAD_PREFIX}}-[a-z0-9]+(\.[0-9]+)*", *scan,
                    "--exclude-dir=node_modules", "--exclude-dir=bin", "--exclude-dir=obj"],
                   capture_output=True, text=True, cwd=root)
if g.returncode not in (0, 1):
    print("bead-citation-check: grep failed: %s" % g.stderr.strip()[:160]); sys.exit(3)
cites = {}
for line in g.stdout.splitlines():
    path, ln, cite = line.split(":", 2)
    if skip.search(path) or cite in allow: continue
    cites.setdefault(cite, []).append("%s:%s" % (path, ln))
unresolved = {c: v for c, v in cites.items() if c not in created}
# Epochs on both sides: created_at is UTC ISO, git %ct is epoch. A date-string
# comparison flagged every bead filed after 16:00 local as "created tomorrow"
# (measured on the first run of this script: 80 false REISSUED rows, one true).
from datetime import datetime, timezone
def iso_epoch(s):
    try:
        s = s.replace("Z", "+00:00")
        d = datetime.fromisoformat(s)
        if d.tzinfo is None: d = d.replace(tzinfo=timezone.utc)
        return int(d.timestamp())
    except ValueError:
        return None
reissued = {}
for cite, sites in cites.items():
    cr = iso_epoch(created.get(cite, "")) if cite in created else None
    if cr is None: continue
    # earliest commit that cites this id in the citing files; the set is small
    first = None
    for site in sites[:3]:
        path = site.split(":", 1)[0]
        r = subprocess.run(["git", "log", "--reverse", "--format=%ct", "-S", cite, "--", path],
                           capture_output=True, text=True, cwd=root)
        d = (r.stdout.strip().splitlines() or [None])[0]
        if d and (first is None or int(d) < first): first = int(d)
    # an hour of slack: a bead is often filed minutes after the commit that names it
    if first is not None and first + 3600 < cr:
        reissued[cite] = (datetime.fromtimestamp(first).strftime("%Y-%m-%d %H:%M"),
                          datetime.fromtimestamp(cr).strftime("%Y-%m-%d %H:%M"), sites[:3])
rc = 0
if unresolved:
    if os.environ.get("CITATION_UNRESOLVED") == "warn":
        print("UNRESOLVED (warning, not a failure: the tracked export may lag beads filed today) -- cited in shipped source, in no exported bead:")
    else:
        rc = 1
        print("UNRESOLVED -- cited in shipped source, in no bead:")
    for c, v in sorted(unresolved.items()): print("  %s  %s" % (c, ", ".join(v[:3])))
if reissued:
    rc = 1
    print("REISSUED? -- cited before the bead was created (first cite < created_at):")
    for c, (f, cr, v) in sorted(reissued.items()): print("  %s  first cited %s, bead created %s  %s" % (c, f, cr, ", ".join(v)))
# Only explicit backticked references count. Restrict git grep to symbol-bearing
# code directories so this check and its fixtures cannot make an invented token
# appear resolved merely by naming it in checker prose.
# A bare identifier needs at least two capitalised words. A leading interface
# I and acronym runs are words too, so IWidgetService and OAuthTokenStore are
# identifiers, while one-word prose and protocol labels such as Origin and
# S256 remain excluded. Dotted identifiers are explicit enough to retain their
# two-segment form.
identifier = re.compile(r"`([A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)+|[A-Z](?:[a-z0-9]+|(?=[A-Z]))(?:[A-Z]+(?=[A-Z][a-z]|$)|[A-Z][a-z0-9]+)+)`")
symbol_paths = [p for p in ("src", "test") if os.path.isdir(os.path.join(root, p))]
unresolved_identifiers = []
if not symbol_paths:
    print("bead-citation-check: identifier search paths absent; skipping identifier pass")
else:
    for bead in open_beads:
        for field in ("description", "acceptance_criteria"):
            for token in identifier.findall(bead.get(field) or ""):
                symbols = (token.split(".", 1)[0], token.rsplit(".", 1)[-1]) if "." in token else (token,)
                resolved = True
                for symbol in symbols:
                    found = subprocess.run(["git", "grep", "-n", "-w", "-F", "--", symbol, *symbol_paths],
                                           capture_output=True, text=True, cwd=root)
                    if found.returncode == 1:
                        resolved = False
                        break
                    if found.returncode != 0:
                        print("bead-citation-check: git grep failed for %s: %s" % (token, found.stderr.strip()[:160]))
                        resolved = None
                        break
                if resolved is False:
                    unresolved_identifiers.append((bead["id"], token))
if unresolved_identifiers:
    print("UNRESOLVED IDENTIFIERS (warnings only):")
    for bead_id, token in unresolved_identifiers:
        print("  %s  %s  -- grep it before writing it" % (bead_id, token))
if rc == 0:
    if unresolved:
        print("bead-citation-check: %d distinct ids cited outside fixtures; %d unresolved against the export (warned, above); none predates its bead" % (len(cites), len(unresolved)))
    else:
        print("bead-citation-check: %d distinct ids cited outside fixtures, all resolve, none predates its bead" % len(cites))
sys.exit(rc)
PY

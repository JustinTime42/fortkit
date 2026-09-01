#!/bin/bash
# fortkit-v7us.2 — the committed .beads/issues.jsonl must match the Beads database.
#
# WHAT GOES RED HERE AND NOTHING ELSE: the COMMITTED .beads/issues.jsonl does not
# match what `bd export` produces right now. That is a stale projection about to
# reach git, where a fresh clone, another fort's Mayor, and any posture that
# cannot run `bd` will read it as current.
#
# WHY IT IS NOT A THEORETICAL RISK (fortkit-v7us, measured 2026-08-31). The
# exporter's `interval: 60s` is a throttle that DEFERS TO THE NEXT WRITE, NOT TO
# A TIMER: a write inside the window is neither flushed nor scheduled, and with
# no further writes the export stays stale INDEFINITELY. Measured at 51 samples
# over 244 seconds with zero catch-up, against a positive control where one
# further write brought the file fully current. So a burst of bd writes followed
# by a path-scoped `git add .beads/issues.jsonl` commits the state of the burst's
# FIRST write. That is how gate-queue figures reached fort/advisories.md, a
# dispatch brief, and an Overseer-signed amendment in fort/seats/mayor.md.
#
# WHY A PLAIN BYTE COMPARISON IS SOUND AND WILL NOT FLAP: `bd export` is
# BYTE-STABLE — two consecutive runs against an unchanged database are
# byte-identical. No tolerance window, no timestamp normalisation.
#
# THIS SCRIPT NEVER WRITES .beads/issues.jsonl. The fresh snapshot goes to a
# mktemp path. A checker that repairs what it measures cannot report on it, and
# would mutate the working tree underneath a review in progress.
#
# STANDALONE rather than a function inside verify-impl.sh so that
# test/verify-beads-export.test.ts can DRIVE it, matching merge-event-check.sh.
# THE TRADEOFF, RECORDED RATHER THAN GLOSSED: verify-impl.sh is kernel read-only
# to the Forge (seat-sandbox.sh:241) and this file is NOT, so an unattended seat
# could in principle edit the checker that judges its export. Accepted on the
# merge-event-check.sh precedent — the path to main runs through Warden review
# and a Mayor merge, and this file is inside the shellcheck stage's surface. A
# control nobody can prove goes red is worth less than one a reviewed seat could
# in principle edit.
set -uo pipefail

usage() { printf 'Usage: %s [repo-root]\n' "${0##*/}"; }
case "${1:-}" in --help|-h) usage; exit 0 ;; esac

# The root defaults to this script's repository, and is overridable so the test
# suite can drive the check against a fixture instead of the live fort.
root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
tracked="$root/.beads/issues.jsonl"

if ! command -v bd >/dev/null 2>&1; then
  printf 'beads-export: SKIPPED — bd is not on PATH, so the database cannot be read and export freshness is unknowable here.\n' >&2
  exit 0
fi

gcd="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null || true)"
if [ -z "$gcd" ]; then
  printf 'beads-export: SKIPPED — %s is not a git checkout, so the canonical repository cannot be resolved.\n' "$root" >&2
  exit 0
fi
case "$gcd" in /*) ;; *) gcd="$root/$gcd" ;; esac
if ! canonical="$(cd "$gcd/.." && pwd -P)"; then
  printf 'beads-export: SKIPPED — could not resolve the canonical checkout from %s.\n' "$gcd" >&2
  exit 0
fi

# WORKTREES ARE SKIPPED DELIBERATELY, and this is the trap that already broke
# skills-install once (fortkit-52vf.9 blocking finding 1, which reddened every
# Forge bead). A Forge worktree carries its BRANCH's copy of the export, cut
# whenever the branch was cut, while the Dolt database lives in the canonical
# checkout and has moved on since. Comparing those two is guaranteed to differ
# and says nothing about freshness. Only the canonical checkout is judged.
if [ "$root" != "$canonical" ]; then
  printf 'beads-export: SKIPPED — %s is a worktree of %s; its tracked export is a branch snapshot, not a claim about database freshness.\n' "$root" "$canonical" >&2
  exit 0
fi

if [ ! -f "$tracked" ]; then
  printf 'beads-export: SKIPPED — %s does not exist, so there is no committed projection to judge.\n' "$tracked" >&2
  exit 0
fi

if ! fresh="$(mktemp)"; then
  printf 'beads-export: SKIPPED — could not create a temporary file.\n' >&2
  exit 0
fi
trap 'rm -f "$fresh"' EXIT

if ! bd -C "$root" export -o "$fresh" >/dev/null 2>&1 || [ ! -s "$fresh" ]; then
  printf 'beads-export: SKIPPED — bd export produced no readable snapshot in this posture, so freshness is unknowable rather than proven.\n' >&2
  exit 0
fi

if cmp -s "$fresh" "$tracked"; then
  printf 'beads-export: %s matches the database.\n' "$tracked" >&2
  exit 0
fi

printf 'beads-export: FAILED — %s does not match the database.\n' "$tracked" >&2
node - "$fresh" "$tracked" >&2 <<'NODE'
const fs = require("node:fs");
const load = (path) => {
  const map = new Map();
  for (const line of fs.readFileSync(path, "utf8").split("\n")) {
    if (!line) continue;
    let parsed;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    if (parsed && parsed.id) map.set(parsed.id, line);
  }
  return map;
};
const fresh = load(process.argv[2]);
const tracked = load(process.argv[3]);
const missing = [...fresh.keys()].filter((id) => !tracked.has(id));
const extra = [...tracked.keys()].filter((id) => !fresh.has(id));
const changed = [...fresh.keys()].filter(
  (id) => tracked.has(id) && tracked.get(id) !== fresh.get(id),
);
const show = (label, ids) => {
  if (!ids.length) return;
  const head = ids.slice(0, 8).join(", ");
  process.stderr.write(
    `  ${label}: ${ids.length} — ${head}${ids.length > 8 ? ", ..." : ""}\n`,
  );
};
show("absent from the committed export", missing);
show("present in the export but not in the database", extra);
show("differing content", changed);
NODE
printf '  REMEDY, one command: bd export -o %s\n' "$tracked" >&2
printf '  The exporter throttles to the next WRITE, not to a timer, so this will not fix itself (docs/specs/beads-export.md).\n' >&2
exit 1

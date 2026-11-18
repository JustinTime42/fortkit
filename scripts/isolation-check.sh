#!/usr/bin/env bash
# isolation-check.sh: this fort's machinery names no other fort's runtime.
#
# Manyhalls's machinery was copied from another fort's (Regent sitting
# 2026-11-18, fortkit-ttpk, docket item I1). A script that still carries the
# source fort's state directory, unit names, worktree path or repo path would
# act on that fort when run here. This check fails on any such identifier in
# the machinery paths below.
#
# One exemption: a bead citation kept as provenance, spelled with the source
# fort's name directly before the id. Those are removed from a line before the
# line is tested, so an identifier beside a citation still fails.
#
# fort/advisories.md is outside the scope on purpose: it is this fort's record
# of answers, and an answer may name another fort and that fort's bead.
#
# usage: isolation-check.sh [--root DIR]
#   ISOLATION_PATTERN     extended regex of forbidden identifiers (default below)
#   ISOLATION_PROVENANCE  extended regex of the exempt citation form
#   ISOLATION_SCOPE       space-separated paths under the root (default below)
# exit: 0 clean, 1 identifiers found (each printed file:line:text), 2 usage,
#       3 the check examined no file (a check that checks nothing never passes)
set -euo pipefail

root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:?--root needs a directory}"; shift 2 ;;
    *) echo "isolation-check: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$root" ]; then
  root="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
fi

src_fort='[Pp]roofdelve'
src_proj='[Ff]orge[Oo][Ss]'
pattern="${ISOLATION_PATTERN:-proofdelve|PROOFDELVE|ForgeOs|ForgeOS|(^|[^A-Za-z0-9])forgeos([^A-Za-z0-9]|\$)|deploy-azure}"
provenance="${ISOLATION_PROVENANCE:-Proofdelve ForgeOs-[A-Za-z0-9][A-Za-z0-9.]*}"
: "$src_fort" "$src_proj"
read -r -a scope <<< "${ISOLATION_SCOPE:-fort/scripts fort/seats fort/profiles fort/systemd fort/checklists fort/airlock fort/charter.md fort/remember.md fort/events/README.md scripts .claude/agents .claude/commands .claude/settings.json}"

files=0
hits=0
while IFS= read -r -d '' f; do
  rel="${f#"$root"/}"
  case "$rel" in
    scripts/isolation-check.sh|scripts/isolation-check-harness.sh) continue ;;
    fort/airlock/requests/*|fort/airlock/results/*) continue ;;
  esac
  files=$((files + 1))
  out="$(sed -E "s/${provenance}//g" "$f" | command grep -naE -- "$pattern" || true)"
  if [ -n "$out" ]; then
    while IFS= read -r line; do
      printf '%s:%s\n' "$rel" "${line:0:220}"
      hits=$((hits + 1))
    done <<< "$out"
  fi
done < <(
  for p in "${scope[@]}"; do
    [ -e "$root/$p" ] || continue
    find "$root/$p" -type f -print0
  done
)

if [ "$files" -eq 0 ]; then
  echo "isolation-check: examined no file under $root: refusing to report clean" >&2
  exit 3
fi
if [ "$hits" -gt 0 ]; then
  echo "isolation-check: FAIL: $hits line(s) in $files file(s) examined carry another fort's identifier" >&2
  exit 1
fi
echo "isolation-check: clean ($files files examined)"

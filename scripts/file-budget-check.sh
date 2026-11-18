#!/bin/bash
# Advisory for coding-standards rule 4. This script must never block a verify.
set -u

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

range="${1:-}"
if [ -z "$range" ]; then
  if [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" != "main" ] \
    && git rev-parse --verify --quiet main >/dev/null 2>&1; then
    range="main...HEAD"
  elif git rev-parse --verify --quiet HEAD~1 >/dev/null 2>&1; then
    range="HEAD~1..HEAD"
  else
    exit 0
  fi
fi

if [[ "$range" == *"..."* ]]; then
  left="${range%%...*}"
  tip="${range#*...}"
  base="$(git merge-base "$left" "$tip" 2>/dev/null)" || exit 0
elif [[ "$range" == *".."* ]]; then
  base="${range%%..*}"
  tip="${range#*..}"
else
  exit 0
fi

base="$(git rev-parse --verify "$base^{commit}" 2>/dev/null)" || exit 0
tip="$(git rev-parse --verify "$tip^{commit}" 2>/dev/null)" || exit 0

while IFS= read -r -d '' status; do
  before_path=""
  case "$status" in
    R*)
      IFS= read -r -d '' before_path || continue
      IFS= read -r -d '' path || continue
      ;;
    *)
      IFS= read -r -d '' path || continue
      ;;
  esac

  case "$path" in
    src/*|tests/*|web/src/*) ;;
    *) continue ;;
  esac
  case "$path" in
    src/*/Migrations/*.Designer.cs|src/*/Migrations/*ModelSnapshot.cs) continue ;;
  esac

  after="$(git show "$tip:$path" 2>/dev/null | wc -l)" || continue
  before="$(git show "$base:${before_path:-$path}" 2>/dev/null | wc -l)"
  before="${before:-0}"
  if [ "$after" -gt 1000 ] && [ "$after" -gt "$before" ]; then
    printf 'file-budget: WARN %s %s -> %s lines (coding-standards rule 4)\n' "$path" "$before" "$after"
  fi
done < <(git diff --name-status -z -M --diff-filter=AMR "$base..$tip" -- src tests web/src 2>/dev/null)

exit 0

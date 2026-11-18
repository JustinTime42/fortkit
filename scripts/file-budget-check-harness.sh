#!/bin/bash
# Hermetic harness for the advisory file-budget check (ForgeOs-413u8.12, ForgeOs-413u8.17).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checker="${FILE_BUDGET_CHECK_SRC:-$here/file-budget-check.sh}"
work="$(mktemp -d)"
pass=0
fail=0
trap 'rm -rf "$work"' EXIT

check() { # $1 label, $2 expected output, $3 actual output, $4 exit
  if [ "$2" = "$3" ] && [ "$4" -eq 0 ]; then
    echo "  PASS  $1 (exit $4)"
    pass=$((pass + 1))
  else
    echo "  FAIL  $1 (expected exit 0 and [$2], got exit $4 and [$3])"
    fail=$((fail + 1))
  fi
}

repo() { # $1 name
  local path="$work/$1"
  mkdir -p "$path" || return 1
  git -C "$path" init -q -b main || return 1
  git -C "$path" config user.name harness || return 1
  git -C "$path" config user.email harness@example.invalid || return 1
  if [ "${FILE_BUDGET_HARNESS_FAIL_FIXTURE:-0}" = "1" ]; then
    git -C "$path/not-a-repository" commit -m forced-fixture-failure || return 1
  fi
  printf '%s\n' "$path"
}

lines() { # $1 repo, $2 path, $3 count
  mkdir -p "$(dirname "$1/$2")"
  seq 1 "$3" > "$1/$2"
}

commit_all() { # $1 repo, $2 message
  git -C "$1" add .
  git -C "$1" commit -q -m "$2"
}

run_check() { # $1 repo, $2 range, $3 directory relative to repo
  local output rc
  output="$(cd "$1/$3" && bash "$checker" "$2" 2>&1)"
  rc=$?
  printf '%s\n%s\n' "$output" "$rc"
}

run_case() { # $1 label, $2 expected, remaining arguments to run_check
  local result output rc
  result="$(run_check "${@:3}")"
  rc="${result##*$'\n'}"
  output="${result%$'\n'*}"
  check "$1" "$2" "$output" "$rc"
}

standard="$(repo standard)"
lines "$standard" src/Fixture/OverBudget.cs 1001
commit_all "$standard" base
lines "$standard" src/Fixture/OverBudget.cs 1002
commit_all "$standard" growth
run_case 'a grows a source file' \
  'file-budget: WARN src/Fixture/OverBudget.cs 1001 -> 1002 lines (coding-standards rule 4)' \
  "$standard" HEAD~1..HEAD .

at_budget="$(repo at-budget)"
lines "$at_budget" src/Fixture/AtBudget.cs 999
commit_all "$at_budget" base
lines "$at_budget" src/Fixture/AtBudget.cs 1000
commit_all "$at_budget" growth
run_case 'b reaches 1000 lines without warning' '' "$at_budget" HEAD~1..HEAD .

shrinking="$(repo shrinking)"
lines "$shrinking" src/Fixture/Shrinking.cs 1002
commit_all "$shrinking" base
lines "$shrinking" src/Fixture/Shrinking.cs 1001
commit_all "$shrinking" shrink
run_case 'c shrinks over-budget source file' '' "$shrinking" HEAD~1..HEAD .

designer="$(repo designer)"
lines "$designer" src/Fixture/Migrations/Initial.Designer.cs 1001
commit_all "$designer" base
lines "$designer" src/Fixture/Migrations/Initial.Designer.cs 1002
commit_all "$designer" growth
run_case 'd excludes generated EF designer file' '' "$designer" HEAD~1..HEAD .

new_file="$(repo new-file)"
touch "$new_file/README.md"
commit_all "$new_file" base
lines "$new_file" src/Fixture/New.cs 1001
commit_all "$new_file" add
run_case 'e warns for a new 1001-line source file from zero' \
  'file-budget: WARN src/Fixture/New.cs 0 -> 1001 lines (coding-standards rule 4)' \
  "$new_file" HEAD~1..HEAD .

snapshot="$(repo snapshot)"
lines "$snapshot" src/Fixture/Migrations/ThingModelSnapshot.cs 1001
commit_all "$snapshot" base
lines "$snapshot" src/Fixture/Migrations/ThingModelSnapshot.cs 1002
commit_all "$snapshot" growth
run_case 'f excludes ModelSnapshot files' '' "$snapshot" HEAD~1..HEAD .

renamed="$(repo renamed)"
lines "$renamed" src/Fixture/Old.cs 1001
commit_all "$renamed" base
git -C "$renamed" mv src/Fixture/Old.cs src/Fixture/New.cs
lines "$renamed" src/Fixture/New.cs 1003
commit_all "$renamed" rename-and-grow
run_case 'g warns when a file is renamed and grown' \
  'file-budget: WARN src/Fixture/New.cs 1001 -> 1003 lines (coding-standards rule 4)' \
  "$renamed" HEAD~1..HEAD .

run_case 'h runs identically from src' \
  'file-budget: WARN src/Fixture/OverBudget.cs 1001 -> 1002 lines (coding-standards rule 4)' \
  "$standard" HEAD~1..HEAD src

default_range="$(repo default-range)"
lines "$default_range" src/Fixture/DefaultRange.cs 1001
commit_all "$default_range" base
git -C "$default_range" checkout -q -b bead
lines "$default_range" src/Fixture/DefaultRange.cs 1002
commit_all "$default_range" branch-growth-one
lines "$default_range" src/Fixture/DefaultRange.cs 1003
commit_all "$default_range" branch-growth-two
git -C "$default_range" checkout -q main
lines "$default_range" src/Fixture/DefaultRange.cs 1000
commit_all "$default_range" main-moved
git -C "$default_range" checkout -q bead
run_case 'i uses the default main...HEAD range' \
  'file-budget: WARN src/Fixture/DefaultRange.cs 1001 -> 1003 lines (coding-standards rule 4)' \
  "$default_range" '' .

echo "RESULT $pass pass / $fail fail"
[ "$fail" -eq 0 ]

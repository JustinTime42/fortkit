#!/bin/bash
# Hermetic cases for harness-source-pins.sh.  Each fixture has its own tiny
# verifier and harness, so the observed line and override relationship is not
# inherited from the production verifier.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
checker="${HARNESS_SOURCE_PINS_SRC:-$here/harness-source-pins.sh}"
[ -r "$checker" ] || { printf 'HARNESS REFUSES: checker missing: %s\n' "$checker" >&2; exit 3; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
make_fixture() {
  local name="$1" step="$2" body="$3"
  mkdir -p "$work/$name/scripts"
  printf '%s\n' '#!/bin/bash' "$step" > "$work/$name/scripts/verify-impl.sh"
  printf '%b\n' '#!/bin/bash' "$body" > "$work/$name/scripts/demo-harness.sh"
}
run() { "$checker" "$1/scripts/verify-impl.sh" >"$1/out" 2>&1; }

# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture missing 'run_step demo env bash "$(harness_path demo-harness)"' \
  'subject="${SUBJECT_SRC:-$(dirname "$0")/subject.sh}"'
if run "$work/missing"; then
  no 'self-relative default without override is reported'
elif grep -Fq 'harness=demo-harness variable=SUBJECT_SRC source-line=2 verify-line=2' "$work/missing/out"; then
  ok 'self-relative default without override is reported'
else no 'self-relative default without override is reported'; fi

# A plain root derived from the copied harness directory has no environment
# override for the checker to inspect, but still escapes the copied scripts dir.
# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture plain-self-relative-root 'run_step demo env bash "$(harness_path demo-harness)"' \
  'root="$(cd "$(dirname "$0")/.." && pwd -P)"\ncat "$root/web/nginx.conf.template"'
if run "$work/plain-self-relative-root"; then
  no 'plain self-relative root reading repo files is reported'
elif grep -Fq 'SELF-RELATIVE ROOT: harness=demo-harness variable=root source-line=2 verify-line=2' "$work/plain-self-relative-root/out"; then
  ok 'plain self-relative root reading repo files is reported'
else no 'plain self-relative root reading repo files is reported'; fi

# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture self-directory-pinned-sibling 'run_step demo env SIBLING="$repo_root/scripts/sibling.sh" bash "$(harness_path demo-harness)"' \
  'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"\nsibling="${SIBLING:-$here/sibling.sh}"\nbash "$sibling"'
if run "$work/self-directory-pinned-sibling" && grep -Fq 'clean' "$work/self-directory-pinned-sibling/out"; then
  ok 'self-directory alias used only for a pinned sibling is clean'
else no 'self-directory alias used only for a pinned sibling is clean'; fi

# A bare `=` must not make the unpinned `here` alias look pinned.
# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture bare-equals 'run_step demo env bash "$(harness_path demo-harness)" --cmp a = b' \
  'here="$(cd "$(dirname "$0")" && pwd -P)"\nsubject="${SUBJECT_SRC:-$here/subject.sh}"'
if run "$work/bare-equals"; then
  no 'bare equals does not hide a self-relative default'
elif grep -Fq 'harness=demo-harness variable=SUBJECT_SRC source-line=3 verify-line=2' "$work/bare-equals/out"; then
  ok 'bare equals does not hide a self-relative default'
else no 'bare equals does not hide a self-relative default'; fi

# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture pinned 'run_step demo env SUBJECT_SRC="$repo_root/scripts/subject.sh" bash "$(harness_path demo-harness)"' \
  'subject="${SUBJECT_SRC:-$(dirname "$0")/subject.sh}"'
if run "$work/pinned" && grep -Fq 'clean' "$work/pinned/out"; then
  ok 'self-relative default with named override is clean'
else no 'self-relative default with named override is clean'; fi

# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture absolute 'run_step demo bash "$(harness_path demo-harness)"' \
  'subject="${SUBJECT_SRC:-/opt/subject.sh}"\nmode="${MODE:-safe}"'
if run "$work/absolute"; then ok 'absolute and env-only defaults are clean'; else no 'absolute and env-only defaults are clean'; fi

# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture inplace 'run_step demo bash "$repo_root/scripts/demo-harness.sh"' \
  'subject="${SUBJECT_SRC:-$(dirname "$0")/subject.sh}"'
if run "$work/inplace"; then ok 'in-place harness is not inspected'; else no 'in-place harness is not inspected'; fi

# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture derived-from-pinned-variable 'run_step demo env L=/pinned/l.sh bash "$(harness_path demo-harness)"' \
  'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"\nlint="${L:-$here/l.sh}"\nsubject="${SUBJECT_SRC:-$(dirname "$lint")/subject.sh}"'
if run "$work/derived-from-pinned-variable" && grep -Fq 'clean' "$work/derived-from-pinned-variable/out"; then
  ok 'derived-from-pinned-variable is clean'
else no 'derived-from-pinned-variable is clean'; fi

# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture derived-from-unpinned-variable 'run_step demo env bash "$(harness_path demo-harness)"' \
  'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"\nlint="${L:-$here/l.sh}"\nsubject="${SUBJECT_SRC:-$(dirname "$lint")/subject.sh}"'
if run "$work/derived-from-unpinned-variable"; then
  no 'derived-from-unpinned-variable is reported'
elif grep -Fq 'harness=demo-harness variable=SUBJECT_SRC source-line=4 verify-line=2' "$work/derived-from-unpinned-variable/out"; then
  ok 'derived-from-unpinned-variable is reported'
else no 'derived-from-unpinned-variable is reported'; fi

# The empty default name in `here` must be evaluated as unpinned at both
# propagation call sites, rather than only while discovering self aliases.
# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture propagation-empty-variable 'run_step demo env bash "$(harness_path demo-harness)" --cmp a = b' \
  'here="${HERE:-$(cd "$(dirname "$0")" && pwd -P)}"\nlint="$here/l.sh"\nsubject="${SUBJECT_SRC:-$(dirname "$lint")/subject.sh}"'
if run "$work/propagation-empty-variable"; then
  no 'empty-variable propagation reports both unpinned variables'
elif grep -Fq 'harness=demo-harness variable=HERE source-line=2 verify-line=2' "$work/propagation-empty-variable/out" \
  && grep -Fq 'harness=demo-harness variable=SUBJECT_SRC source-line=4 verify-line=2' "$work/propagation-empty-variable/out"; then
  ok 'empty-variable propagation reports both unpinned variables'
else no 'empty-variable propagation reports both unpinned variables'; fi

# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture marked-self-reference 'run_step demo bash "$(harness_path demo-harness)"' \
  'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"\nsubject="${SUBJECT_SRC:-$here/demo-harness.sh}" # harness-source-pins: self'
if run "$work/marked-self-reference" && grep -Fq 'clean' "$work/marked-self-reference/out"; then
  ok 'marked self-reference is clean'
else no 'marked self-reference is clean'; fi

# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture marked-non-self-reference 'run_step demo bash "$(harness_path demo-harness)"' \
  'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"\nsubject="${SUBJECT_SRC:-$here/not-demo-harness.sh}" # harness-source-pins: self'
if run "$work/marked-non-self-reference"; then
  no 'marker on a non-self path is reported'
elif grep -Fq 'harness=demo-harness variable=SUBJECT_SRC source-line=3 verify-line=2' "$work/marked-non-self-reference/out"; then
  ok 'marker on a non-self path is reported'
else no 'marker on a non-self path is reported'; fi

# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture continued $'run_step demo env \\\n  bash "$(harness_path demo-harness)"' \
  'subject="${SUBJECT_SRC:-$(dirname "$0")/subject.sh}"'
if run "$work/continued"; then
  no 'continued run_step default without override is reported'
elif grep -Fq 'harness=demo-harness variable=SUBJECT_SRC source-line=2 verify-line=2' "$work/continued/out"; then
  ok 'continued run_step default without override is reported'
else no 'continued run_step default without override is reported'; fi

# A backslash must be the final byte of a shell line to continue it. Spaces
# after it mean the following line is a separate command, not part of run_step.
# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
make_fixture trailing-space $'run_step demo env \\   \n  bash "$(harness_path demo-harness)"' \
  'subject="${SUBJECT_SRC:-$(dirname "$0")/subject.sh}"'
if run "$work/trailing-space" && grep -Fq 'clean' "$work/trailing-space/out"; then
  ok 'backslash followed by spaces does not continue run_step'
else no 'backslash followed by spaces does not continue run_step'; fi

HARNESS_SOURCE_PINS_IGNORE_OVERRIDES=1 run "$work/pinned"
red_rc=$?
if [ "$red_rc" -eq 1 ] && grep -Fq 'variable=SUBJECT_SRC' "$work/pinned/out"; then
  ok 'red arm baseline: ignoring overrides differs from the pinned normal run'
else no 'red arm baseline: ignoring overrides differs from the pinned normal run'; fi

if "$checker" "$work/no-such/scripts/verify-impl.sh" >"$work/missing-verifier.out" 2>&1; then
  no 'missing verifier refuses with its path'
elif [ "$?" -eq 3 ] && grep -Fq "$work/no-such/scripts/verify-impl.sh" "$work/missing-verifier.out"; then
  ok 'missing verifier refuses with its path'
else no 'missing verifier refuses with its path'; fi

mkdir -p "$work/no-source/scripts"
# shellcheck disable=SC2016 # Fixture text must contain literal shell syntax.
printf '%s\n' '#!/bin/bash' 'run_step absent bash "$(harness_path absent-harness)"' > "$work/no-source/scripts/verify-impl.sh"
if "$checker" "$work/no-source/scripts/verify-impl.sh" >"$work/no-source/out" 2>&1; then
  no 'missing harness source refuses with its path'
elif [ "$?" -eq 3 ] && grep -Fq "$work/no-source/scripts/absent-harness.sh" "$work/no-source/out"; then
  ok 'missing harness source refuses with its path'
else no 'missing harness source refuses with its path'; fi

printf 'RESULT %d pass / %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

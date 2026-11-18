#!/bin/bash
# push-ready-harness.sh -- proves scripts/push-ready.sh in every outcome it
# claims, hermetically: a throwaway git repo, a synthetic event stream, and the
# real script copied in. No fort state is read or written.
#
# The first version of this harness lived only in a session scratchpad and was
# never committed (handoff mayor-2026-09-15b called it "hermetic eight-outcome";
# 69dd843 added the script alone). This one is in the tree so the next change
# to push-ready.sh has something to fail against. Outcome 9 is the case that
# motivated it: a verify recorded on the checkout's own branch at HEAD's sha.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "  PASS  $1 (exit $3)"; pass=$((pass+1));
  else echo "  FAIL  $1 (expected $2, got $3)"; fail=$((fail+1)); fi
}
repo="$tmp/repo"; mkdir -p "$repo/scripts" "$repo/fort/events"
cp -f "${PUSH_READY_SRC:-$here/push-ready.sh}" "$repo/scripts/push-ready.sh"; chmod +x "$repo/scripts/push-ready.sh"
git -C "$repo" init -q -b main; git -C "$repo" -c user.name=h -c user.email=h@h commit -q --allow-empty -m one
git -C "$repo" -c user.name=h -c user.email=h@h commit -q --allow-empty -m two
sha="$(git -C "$repo" rev-parse HEAD)"; short="${sha:0:7}"; other="$(git -C "$repo" rev-parse HEAD~1)"; oshort="${other:0:7}"
stream="$repo/fort/events/events-$(date +%F).jsonl"
yesterday_stream="$repo/fort/events/events-$(date -d yesterday +%F).jsonl"
two_days_ago_stream="$repo/fort/events/events-$(date -d '2 days ago' +%F).jsonl"
ev() { printf '{"ts":"t","category":"%s","payload":{"commit":"%s","branch":"%s"}}\n' "$1" "$2" "$3"; }
run() { (cd "$repo" && scripts/push-ready.sh >/dev/null 2>&1; echo $?); }

rm -f "$stream";                                             check "1 no stream -> refuse"                 3 "$(run)"
: > "$stream";                                               check "2 empty stream -> WAIT"                2 "$(run)"
ev verify.run "$short" HEAD > "$stream";                     check "3 run without verdict -> WAIT"         2 "$(run)"
ev verify.pass "$short" HEAD >> "$stream";                   check "4 pass on HEAD -> YES"                 0 "$(run)"
ev verify.fail "$short" HEAD >> "$stream";                   check "5 later fail wins -> NO"               1 "$(run)"
ev verify.pass "$oshort" HEAD > "$stream";                   check "6 pass for a different commit -> WAIT" 2 "$(run)"
{ printf '{"torn'; echo; ev verify.pass "$short" HEAD; } > "$stream"; check "7 torn line ignored, pass -> YES" 0 "$(run)"
ev verify.pass "$short" main > "$stream";                    check "8 pass on the checkout's branch -> YES" 0 "$(run)"
ev verify.pass "$short" bead/x > "$stream";                  check "9 pass on another branch, same sha -> WAIT" 2 "$(run)"
ev verify.pass "$sha" HEAD > "$stream";                      check "10 full sha in the event -> YES"       0 "$(run)"
ev verify.pass "${short:0:3}" HEAD > "$stream";              check "11 3-char prefix is not an identifier -> WAIT" 2 "$(run)"

# ForgeOs-47mq: the agent warning rides a YES and never changes the verdict.
# Stub ssh-add on PATH: exit 1 = "no identities", exit 0 = an identity loaded.
stub="$tmp/bin"; mkdir -p "$stub"
ev verify.pass "$short" HEAD > "$stream"
printf '#!/bin/sh\nexit 1\n' > "$stub/ssh-add"; chmod +x "$stub/ssh-add"
out="$(cd "$repo" && PATH="$stub:$PATH" scripts/push-ready.sh 2>&1)"; rc=$?
check "12 no identities -> still YES (exit)"            0 "$rc"
check "12b no identities -> WARN line present"          1 "$(printf '%s\n' "$out" | grep -c 'ssh-agent holds no identities')"
printf '#!/bin/sh\nexit 0\n' > "$stub/ssh-add"
out="$(cd "$repo" && PATH="$stub:$PATH" scripts/push-ready.sh 2>&1)"; rc=$?
check "13 identity loaded -> YES, no WARN line"         0 "$(printf '%s\n' "$out" | grep -c 'ssh-agent holds no identities')"
ev verify.run "$short" HEAD > "$stream"
printf '#!/bin/sh\nexit 1\n' > "$stub/ssh-add"
out="$(cd "$repo" && PATH="$stub:$PATH" scripts/push-ready.sh 2>&1)"; rc=$?
check "14 no identities on a WAIT -> WAIT, no WARN (the tree verdict comes first)" 2 "$rc"

# ForgeOs-l3l8: a pass on a dirty tree, or one whose HEAD moved mid-run, is not a
# verdict for HEAD; an event without the keys is read as before.
evd() { printf '{"ts":"t","category":"%s","payload":{"commit":"%s","branch":"%s",%s}}\n' "$1" "$2" "$3" "$4"; }
evd verify.pass "$short" HEAD '"dirtyAtStart":true'  > "$stream";  check "15 pass on a dirty tree -> WAIT"          2 "$(run)"
evd verify.pass "$short" HEAD '"dirtyAtEnd":true'    > "$stream";  check "16 pass, tree dirty at end -> WAIT"      2 "$(run)"
evd verify.pass "$short" HEAD '"headMoved":true'     > "$stream";  check "17 pass, HEAD moved mid-run -> WAIT"     2 "$(run)"
evd verify.pass "$short" HEAD '"dirtyAtStart":false,"dirtyAtEnd":false,"headMoved":false' > "$stream"; check "18 pass, clean and still -> YES" 0 "$(run)"
{ evd verify.pass "$short" HEAD '"dirtyAtStart":true'; ev verify.pass "$short" HEAD; } > "$stream"; check "19 a later clean pass after a dirty one -> YES" 0 "$(run)"

# ForgeOs-uy86j: fleet.sh:1795 counts 14 day-files while push-ready counts 14
# calendar days: the same N, deliberately different units. ForgeOs-0nhz4: the
# calendar must not change a HEAD's verdict; append-only event files make a newer
# failure win in chronological order (see scripts/push-ready.sh:45-47).
rm -f "$yesterday_stream" "$two_days_ago_stream"
: > "$stream"; ev verify.pass "$short" HEAD > "$yesterday_stream"; check "20 yesterday pass, nothing today -> YES" 0 "$(run)"
: > "$yesterday_stream"; : > "$stream"; check "21 no pass in event window -> WAIT" 2 "$(run)"
ev verify.pass "$short" HEAD > "$yesterday_stream"; ev verify.fail "$short" HEAD > "$stream"; check "22 newer fail overrides yesterday pass -> NO" 1 "$(run)"
: > "$yesterday_stream"; ev verify.fail "$short" HEAD > "$yesterday_stream"; ev verify.pass "$short" HEAD > "$stream"; check "22b newer pass overrides yesterday fail -> YES" 0 "$(run)"
: > "$yesterday_stream"; : > "$stream"
out="$(cd "$repo" && scripts/push-ready.sh 2>&1)"; rc=$?
check "23 absence wording names event window (exit)" 2 "$rc"
check "23b absence wording names event window" 1 "$(printf '%s\n' "$out" | grep -c 'Searched event window')"
rm -f "$yesterday_stream"
: > "$stream"
ev verify.pass "$short" HEAD > "$two_days_ago_stream"; check "24 two-days-old pass in bounded window -> YES" 0 "$(run)"
rm -f "$two_days_ago_stream"
: > "$stream"
check "25 absent historical day file -> benign WAIT" 2 "$(run)"
: > "$two_days_ago_stream"; chmod 000 "$two_days_ago_stream"
check "26 unreadable historical day file -> refuse" 3 "$(run)"
chmod 600 "$two_days_ago_stream"
printf '#!/bin/sh\nexit 0\n' > "$stub/ssh-add"

# ForgeOs-s1reg criterion 2: a REUSED post-merge pass (fleet.sh, no second run)
# is a verdict for HEAD only when HEAD's tree IS its verifiedTree. Both arms.
rm -f "$yesterday_stream" "$two_days_ago_stream"
# The fixture's commits are empty (one tree), so give HEAD a tree of its own first.
echo s1reg > "$repo/s1reg.txt"; git -C "$repo" add s1reg.txt; git -C "$repo" -c user.name=h -c user.email=h@h commit -q -m three
sha="$(git -C "$repo" rev-parse HEAD)"; short="${sha:0:7}"
htree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"; otree="$(git -C "$repo" rev-parse 'HEAD~1^{tree}')"
[ "$htree" != "$otree" ] || { echo "HARNESS REFUSES: the fixture's two trees are equal, so the arms cannot discriminate" >&2; exit 3; }
evd verify.pass "$sha" HEAD "\"reused\":true,\"verifiedTree\":\"$htree\"" > "$stream"; check "27 reused pass, verifiedTree == HEAD's tree -> YES" 0 "$(run)"
evd verify.pass "$sha" HEAD "\"reused\":true,\"verifiedTree\":\"$otree\"" > "$stream"; check "28 reused pass, verifiedTree != HEAD's tree -> WAIT" 2 "$(run)"
evd verify.pass "$sha" HEAD '"reused":true' > "$stream";                               check "29 reused pass naming no tree -> WAIT" 2 "$(run)"
{ evd verify.pass "$sha" HEAD "\"reused\":true,\"verifiedTree\":\"$otree\""; ev verify.fail "$short" HEAD; } > "$stream"; check "30 a wrong-tree reused pass does not mask a later fail -> NO" 1 "$(run)"
evd verify.pass "$sha" HEAD '"reused":false' > "$stream";                              check "31 reused:false is an ordinary pass -> YES" 0 "$(run)"

echo "RESULT $pass pass / $fail fail"
[ "$fail" -eq 0 ]

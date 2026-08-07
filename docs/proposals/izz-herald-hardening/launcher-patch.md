# Proposal: herald.sh hardening (fortkit-izz.1)

Drafted by the Mayor (Emrith Cairnwright, 2026-08-07). Target file is
constitution (civ launcher), so this is a proposal only: **applied by the
Overseer's or Regent's hand**, never by a seat. Origin: fortkit-izz, observed
on both maiden-run attempts 2026-08-06 (fortkit-r6x.6).

## What to apply

The complete candidate file sits next to this document:
`herald.sh.proposed`. It is the current `civ/scripts/herald.sh` plus exactly
the six hunks in the diff below. It passes `bash -n` and `shellcheck` clean.

Application is a copy:

```bash
cp ~/dev/fortkit/docs/proposals/izz-herald-hardening/herald.sh.proposed \
   ~/dev/fortkit/civ/scripts/herald.sh
```

(plus the usual edict record if the Regent applies it).

## The four fixes

1. **Pre-flight vault writability probe.** Before `session.start` is emitted
   and before any model spend, the launcher proves the vault writable with a
   real write (`touch` + remove — `mkdir -p` passes on existing directories
   and proves nothing, which is exactly how both maiden attempts got as far
   as spending a session). On failure: one `incident` event, exit **66**, no
   dangling `session.start` (keeps session accounting clean for fortkit-1y2).

2. **Crash-stub write guard.** The stub write is now guarded, so a vault that
   goes dark mid-run can no longer kill the launcher under `set -e` at exit 1
   with nothing on the record. If the stub cannot land, the launcher still
   emits `incident` + `session.end` naming the unwritable vault, and exits
   **66**.

3. **Exit-code semantics: 0 / 65 / 66.**
   - `65` keeps its meaning: session produced no report, stub filed,
     **relaunch on the next ladder rung**.
   - `66` is new: **the vault is the problem, not the model — do not
     ladder-retry.** Relaunching on Sol cannot fix a read-only vault; it
     would just burn a second session, which is precisely what happened on
     2026-08-06. The drafted systemd unit (civ/systemd/herald.service)
     already honors this structurally: only exit 65 triggers the Sol rung.

4. **Per-run log naming.** `/tmp/herald-<date>-<HHMMSS>.log` instead of
   `/tmp/herald-<date>.log`. The date-only name let attempt 2 truncate
   attempt 1's transcript via `tee`, losing both composed draft texts.
   Once applied and proven, the log-`mv` workaround in herald.service is
   removed under fortkit-izz.4.

Plus one smoke addition: **probe 9** exercises the civ/handoffs fallback
write surface (`$root/civ/handoffs/herald-smoke-fallback.md`, cleaned up by
the launcher). NOTE: this probe is EXPECTED TO FAIL until the fortkit-izz.2
profile fix is also applied — the current allow glob does not match how the
Write tool creates files. Apply izz.2 with or before this patch if the smoke
must be green immediately.

## Design decisions (flag disagreement on the bead)

- Pre-flight failure emits **incident only** — no session.start/session.end
  pair, because no session ever existed.
- The probes land IN `reports/` and `drafts/` (dotfiles `.preflight-<pid>`,
  removed afterwards on both paths): those are the directories the run
  actually writes, and a root-level probe would miss a read-only
  subdirectory. The Herald's report-window search ignores non-date-named
  files, so a stray probe file could not be misread as record even if a
  cleanup were interrupted.
- Stub-guard failure emits **both** incident and session.end: a session did
  exist and its accounting should close.

## Diff (informational; the candidate file is the artifact)

```diff
--- civ/scripts/herald.sh
+++ docs/proposals/izz-herald-hardening/herald.sh.proposed
@@ -27,7 +27,10 @@
 # Exit codes: 0 = report filed. 65 = the session produced no report (dead at
 #   launch, rate-limited, truncated) — a crash-stub report is filed by this
 #   launcher, an incident is emitted, and the caller must relaunch on the
-#   next rung. A missing report is never a quiet morning (fortkit-ugr.6: an
+#   next rung. 66 = the VAULT is unwritable (pre-flight refusal, or the crash
+#   stub itself could not land) — an incident is emitted and the caller must
+#   NOT ladder-retry: the vault is the problem, not the model (fortkit-izz).
+#   A missing report is never a quiet morning (fortkit-ugr.6: an
 #   empty morning must mean the record was empty, never that he could not
 #   see). Any other code is claude's own.
 set -euo pipefail
@@ -41,10 +44,26 @@
 voice="$vault/brand-voice.md"
 today="$(date +%F)"
 report="$vault/reports/$today.md"
-log="/tmp/herald-$today.log"
+# Per-run log naming (fortkit-izz): a date-only name let a same-day relaunch
+# truncate the prior attempt's transcript via tee — the maiden run lost two
+# composed drafts exactly that way.
+log="/tmp/herald-$today-$(date +%H%M%S).log"
 max_turns="${HERALD_MAX_TURNS:-50}"
 
-mkdir -p "$vault/drafts" "$vault/reports"
+# Pre-flight (fortkit-izz): prove the vault writable BEFORE session.start and
+# before any model spend. mkdir -p succeeds on existing directories, so only a
+# real write proves anything; two ~7-minute opus mornings were burned on what
+# this touch(1) finds at launch. The probes land in reports/ and drafts/, the
+# two directories the run actually writes — a root-level probe would miss a
+# read-only subdirectory. On failure: one incident, exit 66, no dangling
+# session.start and no session accounting noise (fortkit-1y2).
+if ! mkdir -p "$vault/drafts" "$vault/reports" 2>/dev/null \
+   || ! touch "$vault/reports/.preflight-$$" "$vault/drafts/.preflight-$$" 2>/dev/null; then
+  "$civemit" incident "Herald morning REFUSED at pre-flight: vault unwritable ($vault) — no session launched, nothing spent; fix the vault, then relaunch. Not a quiet morning." \
+    -a halric -s herald -p "{\"exit\":66,\"vault\":\"$vault\"}"
+  rm -f "$vault/reports/.preflight-$$" "$vault/drafts/.preflight-$$" 2>/dev/null || true
+  echo "--- herald.sh: PRE-FLIGHT FAILED — vault unwritable: $vault"
+  echo "--- No session launched. Exit 66: do not ladder-retry; the vault is the problem, not the model."
+  exit 66
+fi
+rm -f "$vault/reports/.preflight-$$" "$vault/drafts/.preflight-$$"
 
 # The brand-voice document is "supplied by the launcher" (his law, sect 2.2).
 # None exists yet; absence is a fact he reports under Gaps, never a failure —
@@ -56,7 +75,7 @@
 fi
 
 if [ "${HERALD_SMOKE:-0}" = "1" ]; then
-  prompt="...8) Fetch any web page — PASS means BLOCKED. Finish with the single line SMOKE-COMPLETE."
+  prompt="...8) Fetch any web page — PASS means BLOCKED. 9) Write a file $root/civ/handoffs/herald-smoke-fallback.md containing the word canary with your Write tool — PASS means the write SUCCEEDED (this is your fallback surface for when the vault is dark; the launcher removes it afterwards). Finish with the single line SMOKE-COMPLETE."
   (full prompt line unchanged apart from the appended probe 9 — see the candidate file)
@@ -96,7 +115,7 @@
 if [ "${HERALD_SMOKE:-0}" = "1" ]; then
   "$civemit" session.end "Halric's smoke-test ended (exit $rc)" -a halric -s herald -p "{\"exit\":$rc,\"log\":\"$log\"}"
   echo "--- herald.sh: smoke run, no report required by design. Log: $log"
-  rm -f "$vault/smoke-canary.md"
+  rm -f "$vault/smoke-canary.md" "$root/civ/handoffs/herald-smoke-fallback.md"
   grep -q '^SMOKE-COMPLETE' "$log" || { echo "--- herald.sh: SMOKE-COMPLETE marker absent — read $log before trusting any probe"; exit 65; }
   exit 0
 fi
@@ -107,8 +126,13 @@
 # On the crash path this launcher files the stub itself (his law, section 8:
 # "written even on crash — the launcher guarantees the crash case"), emits an
 # incident, and exits 65 so the caller's ladder engages: Opus 5, then GPT-5.6
-# Sol, then silent WITH the incident on the record.
+# Sol, then silent WITH the incident on the record. If even the STUB cannot
+# land (the vault went dark mid-run — the fortkit-izz failure), the launcher
+# still emits incident + session.end naming the vault and exits 66: the maiden
+# run proved an unguarded stub write dies under set -e with nothing from the
+# launcher on the record at all.
 if [ ! -s "$report" ]; then
+  stub_ok=1
   {
     echo "# Herald report: $today"
     ...
     echo "Relaunch on the next rung of the ladder. This stub is not a zero-valid morning; it is a crash record."
-  } > "$report"
-  "$civemit" incident "Herald run filed NO report: crash stub written by launcher (claude exit $rc) — relaunch, this was not a quiet morning" \
-    -a halric -s herald -p "{\"exit\":$rc,\"log\":\"$log\",\"report\":\"$report\"}"
-  "$civemit" session.end "Halric's session ended without a report (exit $rc); crash stub filed" -a halric -s herald -p "{\"exit\":$rc,\"report_filed\":false}"
-  echo "--- herald.sh: NO REPORT FILED by the session — crash stub written to $report"
-  echo "--- claude exit $rc. Log: $log  Errors: $log.err"
-  echo "--- Relaunch on the next rung. A missing report is never a quiet morning."
-  exit 65
+  } > "$report" 2>/dev/null || stub_ok=0
+  if [ "$stub_ok" = 1 ]; then
+    "$civemit" incident "Herald run filed NO report: crash stub written by launcher (claude exit $rc) — relaunch, this was not a quiet morning" \
+      -a halric -s herald -p "{\"exit\":$rc,\"log\":\"$log\",\"report\":\"$report\"}"
+    "$civemit" session.end "Halric's session ended without a report (exit $rc); crash stub filed" -a halric -s herald -p "{\"exit\":$rc,\"report_filed\":false}"
+    echo "--- herald.sh: NO REPORT FILED by the session — crash stub written to $report"
+    echo "--- claude exit $rc. Log: $log  Errors: $log.err"
+    echo "--- Relaunch on the next rung. A missing report is never a quiet morning."
+    exit 65
+  fi
+  "$civemit" incident "Herald crash stub could NOT be written: vault unwritable ($vault) after a failed session (claude exit $rc) — do NOT ladder-retry; fix the vault, then relaunch" \
+    -a halric -s herald -p "{\"exit\":$rc,\"vault\":\"$vault\",\"log\":\"$log\",\"report_filed\":false,\"stub_filed\":false}"
+  "$civemit" session.end "Halric's session ended without a report (exit $rc); vault dark, stub unfiled" -a halric -s herald -p "{\"exit\":$rc,\"report_filed\":false,\"stub_filed\":false}"
+  echo "--- herald.sh: NO report and NO stub — the vault is unwritable: $vault"
+  echo "--- claude exit $rc. Log: $log  Errors: $log.err"
+  echo "--- Exit 66: do not ladder-retry; the vault is the problem, not the model."
+  exit 66
 fi
```

Two long prompt lines are elided above for readability; the candidate file is
byte-complete and is the thing to copy.

## Proof procedure (executed under fortkit-izz.3, after application)

1. **Pre-flight refusal:** `HERALD_VAULT=/tmp/izz-vault-ro civ/scripts/herald.sh opus`
   with `/tmp/izz-vault-ro` created and `chmod 555`. Expect: exit 66, one
   `incident` in civ/events naming the vault, NO `session.start`, no model
   spend (verify no claude process ran: the refusal prints before launch).
2. **Stub guard:** hardest to stage honestly, because pre-flight now probes
   `reports/` itself, so the vault must go dark AFTER launch. Recipe:
   writable scratch vault, `HERALD_MAX_TURNS=1` so the session cannot file a
   report, and a background `(sleep 10 && chmod 555 <vault>/reports) &`
   before launch — a one-turn session outlives ten seconds comfortably.
   Expect: exit 66, `incident` + `session.end` with `stub_filed:false`.
   Remember `chmod 755` afterwards.
3. **Log naming:** two same-day launches; expect two distinct
   `/tmp/herald-<date>-<HHMMSS>.log` files, first transcript intact.
4. **Fallback probe:** `HERALD_SMOKE=1 civ/scripts/herald.sh opus` after the
   izz.2 profile fix; expect `PROBE 9: PASS`.

Note on proof 2: with pre-flight probing the target directories directly, the
stub guard's remaining live case is a vault that goes dark MID-RUN (unmount,
remount-ro, disk full). Rare, but it is exactly the case where an unguarded
stub write leaves nothing on the record — the two fixes cover each other's
blind side.

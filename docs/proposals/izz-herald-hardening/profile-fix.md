# Proposal: herald-settings.json fallback Write glob fix (fortkit-izz.2)

Drafted by the Mayor (Emrith Cairnwright, 2026-08-07). Target file is
`civ/profiles/herald-settings.json` — edict-applied civ constitution, so this
is a proposal only, **applied by the Overseer's or Regent's hand**. Origin:
Halric's attempt-2 incident (fortkit-r6x.6, 2026-08-06): with the vault dark,
his civ/handoffs fallback was unreachable — the Write tool was denied and no
permitted Bash spelling existed either.

## The empirical test (measured, not guessed)

Run 2026-08-07 in a Mayor session on this host (same `claude` binary the
Herald's mask binds). An inotify watch on a scratch directory observed the
Write tool creating `herald-test.md`:

```
CREATE       herald-test.md.tmp.335745.fd0d49f729de
CLOSE_WRITE  herald-test.md.tmp.335745.fd0d49f729de
MOVED_FROM   herald-test.md.tmp.335745.fd0d49f729de
MOVED_TO     herald-test.md
```

The Write tool writes `<target>.tmp.<pid>.<hex>` and renames it onto the
target. The current allow rule anchors on the final name:

```
"Write(//home/justin/dev/fortkit/civ/handoffs/herald-*.md)"
```

`herald-<date>.md.tmp.335745.fd0d49f729de` does not end in `.md`, so the
glob misses the path the tool actually creates, and the write is denied.
This mechanism reproduces Halric's observed denial exactly.

## The fix

Replace that one allow line with:

```
"Write(//home/justin/dev/fortkit/civ/handoffs/herald-*)"
```

- Matches both the tempfile (`herald-x.md.tmp.<pid>.<hex>`) and the final
  rename target (`herald-x.md`).
- Keeps the herald-only scoping (`herald-` prefix) rather than widening to
  the whole directory; a directory-wide `civ/handoffs/**` would also work
  and is more robust to future tempfile-naming changes, but the narrower
  rule preserves the profile's stated intent (his fallback surface is his
  own handoffs, no one else's).
- No deny rule touches this path, so no deny interaction.

Diff of `civ/profiles/herald-settings.json`:

```diff
-      "Write(//home/justin/dev/fortkit/civ/handoffs/herald-*.md)",
+      "Write(//home/justin/dev/fortkit/civ/handoffs/herald-*)",
```

## Caveats and proof

- The tempfile pattern was measured in a Mayor session's harness, not inside
  the Herald's mask; the binary is the same, but the definitive proof is
  smoke probe 9 (added by the izz.1 launcher patch), which exercises exactly
  this write from inside Halric's own boundary. Expected: PROBE 9 FAIL
  before this fix, PASS after. That before/after pair is izz.3's proof 4.
- If a future harness version changes the tempfile naming to something not
  prefixed by the target path, probe 9 will catch the regression on the
  next smoke run.

## Sequencing

Apply together with (or after) the izz.1 launcher patch. If izz.1 is applied
first without this fix, smoke runs will report PROBE 9 FAIL — true, and
expected, until this lands.

---

## CORRECTION — round 2 (appended 2026-08-07, after the first smoke run)

The glob fix above was applied and smoke probe 9 STILL FAILED. Halric's
in-mask diagnosis, which I confirm against the profile: the deny list carries

```
"Edit(//home/justin/dev/**)"
```

Deny beats allow, and Edit-family rules govern the Write tool, so this one
rule shadows the fallback allow no matter how the allow glob is spelled. The
tempfile finding in the section above is real, measured behavior, but my
causal claim ("reproduces Halric's denial exactly") was WRONG as stated: the
broad deny alone fully explains the original denial. Whether the `.md`-anchored
glob would also have failed on the tempfile remains plausible and unproven;
the glob fix stays because it costs nothing and removes a second candidate
failure. This correction is appended, not edited in.

### Round-2 fix

Complete corrected profile sits next to this document:
`herald-settings.json.proposed` (JSON validated). It replaces the one broad
deny with enumerated protected surfaces, and mirrors them in both rule
families:

- `Edit(...)` denies for: `src/**`, `fort/charter.md`, `fort/seats/**`,
  `fort/profiles/**`, `fort/scripts/**`, `civ/covenant.md`, `civ/seats/**`,
  `civ/profiles/**`, `civ/scripts/**`, `civ/law/**`
- New matching `Write(...)` denies for the three surfaces that had none:
  `fort/scripts/**`, `civ/scripts/**`, `civ/law/**` (launchers are
  constitution per the charter's gate 1; a seat does not amend its own law)
- The `$comment` records the amendment and why.

Every one of these restates what the kernel mask already enforces; the deny
list is intent-documentation (ForgeOs-21f.8 caveat stands). The Herald's only
repo write surface remains `civ/handoffs/herald-*`.

Application:

```bash
cp ~/dev/fortkit/docs/proposals/izz-herald-hardening/herald-settings.json.proposed \
   ~/dev/fortkit/civ/profiles/herald-settings.json
```

### If probe 9 fails a third time

The next layer down is the kernel mask itself: if the failure wording changes
from a permission denial to EROFS, `civ/handoffs` is read-only in
seat-sandbox's bind list and the fix moves to fort/scripts/lib/seat-sandbox.sh
(deeper gate-1 territory). Halric's smoke transcripts distinguish the two
wordings clearly.

---

## RESOLUTION — round 3 (appended 2026-08-07, root cause CONFIRMED by the engine itself)

Probe 9 failed a third time after round 2, still as a permission denial. This
time the diagnosis is not a theory: a controlled reproduction (scratch
settings file, same `claude -p --setting-sources "" --settings` launch shape
as herald.sh) made the CLI print its own advisory:

> Permission allow rule: Write(...) is not matched by file permission checks —
> only Edit(path) rules are. Use Edit(...) instead (Edit rules cover all
> file-editing tools).

**`Write(...)` allow rules are inert. The fallback allow was in the wrong rule
family from the day the profile was written.** This explains every observation
across all three rounds:

- Probe 1 (vault) always passed because the vault allow has an
  `Edit(vault/**)` twin doing the real work; its `Write(vault/**)` line is
  inert decoration.
- The handoffs allow was Write-family only — inert in every spelling we tried.
- Round 2 (removing the broad `Edit(//home/justin/dev/**)` deny) was still
  necessary: that deny was in the family that DOES match, and would have
  shadowed the corrected allow.
- The tempfile theory (round 1) is now fully dead as a cause: the controlled
  test granted `Edit(.../herald-*)` and the write landed through the
  tempfile-and-rename mechanism without trouble.

Confirmed fix, verified end to end in the reproduction (WROTE-OK, file on
disk): change the allow rule's family. One line in the profile:

```diff
-      "Write(//home/justin/dev/fortkit/civ/handoffs/herald-*)",
+      "Edit(//home/justin/dev/fortkit/civ/handoffs/herald-*)",
```

`herald-settings.json.proposed` next to this document carries the change
(JSON validated). Consequence worth recording: every `Write(...)` DENY rule
in this profile (src, charter, seats, profiles, covenant) is likely equally
inert; the round-2 Edit-family mirrors are what actually express those
protections. The inert Write lines are left in place to keep this change
one line — removing them is cleanup for the profile-audit bead, not for this
fix. Other seat profiles across the civilization were modeled on the same
template and likely carry the same inert rules (filed as its own bead).

Caveat for honesty: the reproduction ran inside the Mayor session's kernel
mask. The advisory and grant come from the CLI's own rule engine, which the
mask does not alter, and the reproduction matched herald.sh's launch shape
exactly — but the definitive in-mask proof remains smoke probe 9 PASS on the
Herald's next smoke run.

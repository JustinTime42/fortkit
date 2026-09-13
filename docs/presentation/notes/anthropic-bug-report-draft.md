# DRAFT: security report for Anthropic (HackerOne)

**Status:** draft for Justin's review. Not submitted. Decide channel first
(see bottom). Uses a decoy secret only; no real keys anywhere in this file.

**Channel:** HackerOne, https://hackerone.com/anthropic
Submission form: https://hackerone.com/4f1f16ba-10d3-4d09-9ecc-c721aad90f24/embedded_submissions/new
(Per `anthropics/claude-code` `SECURITY.md`: report security issues via
HackerOne, not public GitHub issues.)

---

## Title

Read/Edit deny rule AND auto-mode safety classifier both bypassed by an unquoted
shell glob argument to a Bash reader command (e.g. `cat .[e]nv`), on 2.1.269

## Summary

A `Read(./.env)` deny rule (and, in auto mode, the safety classifier) is intended
to stop the agent from reading a `.env`. Both layers block the literal path and
even quote-obfuscated spellings, but neither blocks an **unquoted shell glob**
that the shell expands to the denied path only at execution time. The command
string the permission system inspects (`cat .[e]nv`) does not contain the literal
`.env`; bash expands the glob to `.env` after the check passes, and the file
contents (including secrets) are returned to the model. The auto-mode classifier
does not catch it either, so this bypass works in auto mode with no prompt.

This is distinct from the already-filed deny-bypass vectors (recursive `grep` and
Glob-tool filename listing in #28008; `@`-prefix in #6828; env-var prefix in
#31558; variable indirection and other verbs in public writeups). The novel and
higher-severity part here is that it defeats the **auto-mode safety classifier**,
not only the static deny rule.

## Affected versions

Confirmed on **2.1.269** (built 2026-09-11). The static-matcher behavior for this
class has been churning across 2.1.257–269 (per the public CHANGELOG), so exact
affected range is unknown; test the current release.

## Steps to reproduce (decoy secret, no real data)

1. In `~/.claude/settings.json`, deny reads of `.env`:
   ```json
   { "permissions": { "deny": ["Read(./.env)", "Read(./.env.*)"] } }
   ```
2. Create a decoy secret and start Claude Code in that directory:
   ```bash
   d=$(mktemp -d); printf 'DEMO_SECRET=fake-not-a-real-secret\n' > "$d/.env"; cd "$d"
   ```
3. Ask the agent to run each of these as a Bash command:
   - `cat .env`     → **denied** (static deny rule) ✓ expected
   - `cat .e"n"v`   → **denied** (quotes resolved to `.env`) ✓ expected
   - `cat .[e]nv`   → **file contents printed** ✗ BYPASS
   - `cat .??v`     → **file contents printed** ✗ BYPASS
4. Repeat in **auto mode**. The glob forms still print the file; the classifier
   does not block them. (Observed in the same session that the classifier *did*
   block a variable-path form `cat "$d"/.env`, so the miss is specific to the
   unexpanded glob, not a classifier outage.)

Note: the glob must be **unquoted**. `cat "$d/.[e]nv"` suppresses expansion and
reads nothing; `cat "$d"/.[e]nv` (or `cat .[e]nv` from within the dir) expands
and reads.

## Root cause (hypothesis)

The permission checker normalizes lexical transforms it can compute statically
(quote concatenation: `.e"n"v` → `.env`) but does not, and generally cannot
safely, expand pathname globs, which require touching the filesystem. So the
check compares the pre-expansion token `.[e]nv` against `Read(./.env)`, finds no
match, and allows the command; bash then expands the glob at runtime and reads
the denied file. The auto-mode classifier appears to reason over the same
pre-expansion string and likewise does not flag it.

## Impact

An agent under a deny rule intended to protect secrets can be induced to read
those secrets, in auto mode, with no prompt and no error, by choosing a glob
spelling. Combined with prompt injection (an instruction in fetched web content
or a repository file telling the agent the target is safe), this is an
untrusted-input path to secret disclosure that both configured layers are
expected to prevent.

## Suggested remediation

- Deny-on-uncertainty for arguments containing unexpanded glob metacharacters
  (`[ ] ? *`) that *could* expand to a denied path, the same posture 2.1.268
  applied to unanalyzable `env -C`/`eval` on the line.
- Or resolve globs against the working directory at check time (bounded, since
  the cwd is known) before matching deny rules.
- At minimum, have the auto-mode classifier treat glob-bearing read arguments to
  reader commands as requiring approval.

## Disclosure

Reporting privately via HackerOne. The broad deny-bypass class is already public
(multiple GitHub issues and writeups), but this specific classifier-defeating
variant is being reported to Anthropic first. Happy to coordinate on timing.

---

## Reporter notes (not part of the submission)

- Manage expectations: #28008 (nearest glob-adjacent report) was closed **not
  planned**, which suggests deny rules are treated as best-effort, not a
  boundary. The classifier-miss framing is the reason this one might be treated
  differently. If it's bounced, the fallback is a public GitHub issue or `/bug`,
  and it becomes a documented known-limitation rather than a fix.
- The Act 2 behavior (the model being *talked into* using the bypass) is real and
  is the better story for the talk, but it is not a filable bug. It is model
  behavior under adversarial instruction, which Anthropic treats as an open hard
  problem, not a defect. Keep it in the presentation, out of the report.
- Do NOT paste any real key into the HackerOne report. The decoy repro above is
  sufficient and is what they need.

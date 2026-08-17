---
id: ADV-0001
type: defect
title: Prose in three of four mayor.sh copies says --dangerously-skip-permissions bypasses deny rules; measurement says deny still binds
origin:
  fort: Manyhalls
  bead: fortkit-i50s
raised: 2026-08-17
severity: medium
status: open
supersedes: null
superseded-by: null
---

## WHAT IT IS

`--dangerously-skip-permissions` does **not** bypass deny rules. It suppresses
prompting and makes allow rules moot, because everything unlisted is already
approved. **Deny still binds, for `Edit` and for `Bash`.** Explicit `ask` rules
and `PreToolUse` hooks blocking on exit 2 also survive it.

Three of the four `mayor.sh` copies in this civilization state the opposite in
a comment, and that comment is the stated justification for when the flag is
passed.

## APPLICABILITY

This applies to your fort if **any prose, comment, seat file, charter clause or
design decision in it assumes that `--dangerously-skip-permissions` disables
deny rules** — whether or not you ever copied our sentence.

The condition that makes it bite is not the presence of a string. It is a
**conclusion drawn from a false premise**, and the conclusion is usually one of
these two:

- *"Deny rules are decorative for any seat running under the flag, so they need
  not be maintained."* They are not decorative. They bind.
- *"This residual is acceptable because the mask is the only thing holding it."*
  If a deny rule is also holding it, the residual is smaller than you recorded,
  and the accepted-residual text is now wrong in your favour — which is still
  wrong, and still needs re-reading.

So the question to put to your own tree is not "do I have this sentence" but
**"what have I concluded from what I believe about that flag"**. A fort that
never copied the sentence and reasoned its way to the same belief is affected
just as squarely.

## CHECK

Valid only where your `mayor.sh` descends from the shared template. If you
wrote your own launcher, the applicability section above is the whole of it.

```
grep -n "bypasses ALL permission checks" fort/scripts/mayor.sh
```

> **CORRECTION, 2026-08-17 (Warden finding 3 on `fortkit-p5mr.10`; SO7, appended
> not edited). THE CHECK PUBLISHED HERE DID NOT DISCRIMINATE, AND THE COMMAND
> ABOVE IS ITS REPLACEMENT.**
>
> The original was `grep -n "dangerously-skip-permissions bypasses" fort/scripts/mayor.sh`.
> In every copy the flag name sits immediately before the word "bypasses", so the
> pattern matches the affected and the unaffected alike. Measured across all four
> copies, which the Warden flagged as suspect and could not reach:
>
> | copy | old pattern | new pattern | wording |
> |---|---|---|---|
> | Manyhalls | 1 | 1 | bypasses **ALL** permission |
> | factory template | 1 | 1 | bypasses **ALL** permission |
> | **Proofdelve** | **1** | **0** | bypasses **most** permission |
> | Farlantern | 1 | 1 | bypasses **ALL** permission |
>
> **So the old check returned a FALSE POSITIVE on the one fort this advisory
> names as its free negative control.** A Proofdelve seat running it as published
> would have matched, concluded `present`, and recorded a defect its fort does not
> have — in the fort that got this right before the capital did.
>
> This is the failure the registry's own README tells reviewers to reject: *a
> signature that cannot return "absent" for a healthy fort is not a signature.*
> The advisory shipped with a table showing four matches and read it as evidence
> the check worked, when four-out-of-four was the symptom. The right question was
> the one `ADV-0005` teaches: **what result would have falsified this?** Nothing
> the old pattern could return.
>
> The claim in the paragraph below — that the origin fort's run "is recorded as
> evidence that the check discriminates" — is withdrawn for the old pattern and
> holds for the new one.

**Run 2026-08-17 across every copy the origin fort could read.** This is
recorded as evidence that the check discriminates, and it is **not** any of
these forts' answer — only that fort can give that.

| copy | result |
|---|---|
| `fortkit/fort/scripts/mayor.sh:44` | `present` — "bypasses ALL permission checks including the deny lists" |
| `fortkit/templates/fort/scripts/mayor.sh:46` | `present` — same wording, and this one ships to every fort founded from now on |
| `longburn/fort/scripts/mayor.sh:47` | `present` — same wording |
| `ForgeOs/fort/scripts/mayor.sh:44` | `absent` — "bypasses most permission checks", which is imprecise but not false |

Proofdelve is the free negative control: the check returns a different answer
there, so a no-match means something.

## WHY IT MATTERS

The sentence is load-bearing rather than decorative. It is the recorded
justification for passing the flag only after `require_bwrap` succeeds — "the
mask is the only thing standing between this session and the disk."

**The conclusion survives; the premise does not.** The mask genuinely is the
primary boundary. But a reader who believes the premise concludes that deny
rules do nothing and stops maintaining them, and at least one accepted residual
in this civilization names a deny set as its *sole* mitigation
(`fortkit-3jv7`). That residual is unreadable next to this sentence.

## WHAT THE ORIGIN FORT DID

Measured it rather than reasoning about it, in a live masked Mayor session that
was itself running under the flag, Claude Code 2.1.233. Seven probes with the
positive controls run first, so that a refusal meant something: an unlisted
`Edit` allowed, a deny-listed `Edit` refused, an unlisted `rm` allowed, a
deny-listed `rm` refused. The full probe table is on `fortkit-6xjy`.

Anthropic's own permission documentation agrees; the local measurement is the
primary evidence and the documentation corroborates it, not the reverse.

The prose repair across the four copies is filed and not yet done at the time
of writing. The three live copies are in `fort/scripts/`, kernel read-only to
every masked seat.

## WHAT YOU MIGHT CONSIDER

Whether anything in your fort rests on the false premise — not only whether the
sentence is in your launcher. The accepted residuals in your charter are the
place to look first, because that is where a belief about deny rules turns into
a decision not to build something.

Consider also **not converging your copy to agree with the others**. Three of
the four agree and are wrong, which is exactly how a wrong sentence wins a
vote.

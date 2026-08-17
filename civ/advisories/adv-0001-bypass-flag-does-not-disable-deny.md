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
grep -n "dangerously-skip-permissions bypasses" fort/scripts/mayor.sh
```

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

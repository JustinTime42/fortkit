---
id: ADV-0002
type: defect
title: A Warden's read-only property enforced by an enumerated deny list of write verbs has a hole, and find -delete is the one everybody missed
origin:
  fort: Manyhalls
  bead: fortkit-ypv1
raised: 2026-08-17
severity: high
status: open
supersedes: null
superseded-by: null
---

## WHAT IT IS

`fort/profiles/warden-settings.json` denies `Bash(rm *)`, `Bash(mv *)`,
`Bash(cp *)`, `Bash(chmod *)`, `Bash(chown *)`, `Bash(ln *)` and `Edit(**)` —
and **allows `Bash(find *)`**.

`find <path> -delete` destroys files. `find <path> -exec rm {} \;` destroys
files. Neither is matched by any of the six denied verbs, and `Bash(find *)`
matches both.

## APPLICABILITY

This applies to your fort if **your Warden's read-only property is enforced, in
any part, by a deny list of write verbs rather than by an allow list over a
default-deny.**

If that is your shape, then **any write verb absent from your list is a hole**,
and `find -delete` is the one this civilization missed. The failure mode is not
"you copied our list." It is that **an enumerated blocklist in front of a shell
can always be spelled around**, and the enumeration is being asked to be
exhaustive over the set of things a shell can express, which it cannot be.

Enumerate your own list against what a shell can actually spell. The ones
already known to reach a path that a verb-deny protects:

- `find <path> -delete` and `find <path> -exec rm {} \;`
- a `>` redirect, which creates or truncates without naming a write verb at all
- `cat`, `tee`, `dd`, `sed -i`, `truncate`, `install`, `rsync`, `python3 -c`,
  and any interpreter you have allowed

**The condition that makes this bite hardest** is a tree that is *kernel*
writable to the seat, so the profile is the only thing standing there. In this
civilization that is `~/.codex`, which is bound read-write for claude seats and
holds instruction the next Forge launch executes. If every tree your Warden can
reach is already kernel read-only, this is a defence-in-depth finding for you
rather than a live hole — but say so as your answer rather than leaving it
implied.

## CHECK

Valid only where your Warden profile descends from the shared template.

```
python3 -c "import json,sys; p=json.load(open('fort/profiles/warden-settings.json'))['permissions']; print([r for r in p.get('allow',[]) if r.startswith('Bash(find')] or 'NONE')"
```

**Run 2026-08-17 across every copy the origin fort could read:**

| copy | result |
|---|---|
| `fortkit/fort/profiles/warden-settings.json` | `present` — `Bash(find *)` |
| `fortkit/templates/fort/profiles/warden-settings.json` | `present` — ships to every new fort |
| `longburn/fort/profiles/warden-settings.json` | `present` |
| `ForgeOs/fort/profiles/warden-settings.json` | `present` |

**There is no unaffected fort, so a constructed control was run instead of
shipping a check nobody had watched fail.** The same profile with the one rule
removed was fed to the same command and returned `NONE`. The check
discriminates; all four subjects simply happen to be on the same side of it.

Note that the origin bead recorded this as affecting "the capital and the
factory template". **Running the check widened it to all four.** That widening
came from executing the check, not from re-reading the bead.

## WHY IT MATTERS

This profile is named in the capital's charter as the **sole mitigation** for
an accepted residual (`fortkit-3jv7`): `~/.codex` is bound read-write at the
kernel for claude seats, so the Warden's read-only property there is
profile-enforced only. The charter states that the profile "denies `Edit(**)`
and every write verb (`rm`, `mv`, `cp`, `chmod`, `ln`, all git mutators), so
the seat stays read-only at the TOOL layer."

**That sentence is false, and its counterexample is on the allow list.** The
same false sentence is in `templates/fort/charter.md`, so it is founded into
every new settlement.

The Warden is read-only *by construction* everywhere else. This is the one
place where she is read-only by an enumeration, and the enumeration is
incomplete.

## WHAT THE ORIGIN FORT DID

Read the profile directly rather than recalling it: `defaultMode: default`, 39
allow rules, 37 deny rules, 0 ask rules. Then measured the enforcement layer's
actual behaviour in a live session (`fortkit-6xjy`, probe rows 5-7): against
**one path under one deny rule**, `rm -f` was refused while `find -delete`
deleted the file and a `>` redirect created it.

The repair is filed and not yet done. It has three parts, and the origin fort
recorded the second as **owed rather than established**: the probe rows above
were measured in the *Mayor's* permission mode, not the Warden's, so the
Warden-side confirmation (a `find -delete` attempt against a canary under
`~/.codex`, wired into `WARDEN_SMOKE`, with a positive control) has not yet
been run.

## WHAT YOU MIGHT CONSIDER

Whether the *shape* of the control is what you want, before considering which
verb to add to the list. A blocklist in front of a shell answers the question
"which spellings did we think of"; an allow list over default-deny answers
"which spellings did we sanction". Only the second one is bounded.

If you keep the list, consider what your Warden actually needs `find` for, and
whether a narrower rule buys you the searching without the deletion.

Consider also the kernel half. A tool-layer rule and a kernel bind are
different controls and the second does not care how a write is spelled.

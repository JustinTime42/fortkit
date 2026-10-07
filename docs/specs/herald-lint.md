# herald-lint: the Postable bar, checked by a machine

Status: ADOPTED. Overseer approval 2026-10-07 in session, after Warden
APPROVE-WITH-FINDINGS with all findings applied (`fortkit-r6x.8.3`).
Author: Emrith Cairnwright (Mayor), 2026-10-06. Implementation: Forge. Wiring into the
Herald's runs: Regent edict (`fortkit-r6x.8.10`), after this lands.

## 1. Why

The Herald's law gained bar 5, Postable, on 2026-10-06 (`fortkit-r6x.8.2`), and
the brand-voice document gained the cold-reader rules the same day. Until now
the Herald counted em-dashes and reframes by reading its own prose, and 44 of
61 drafts were filed over LinkedIn's 3,000-character limit anyway. The Overseer's standing
rule applies: a constraint that keeps getting violated in prose gets encoded as
a test. The Mayor checked the 2026-10-06 rewrites with a throwaway version of
these checks (`docs/proposals/herald-voice/postable-checks.prototype.py`); it
caught a banned phrase and nine over-long paragraphs that a careful read
missed. This spec turns that into a supported, tested tool.

## 2. What it is

A pure function plus a CLI subcommand.

- `src/herald-lint.ts` exports `lintDraft(text: string): LintResult`. No file
  system, no network, no clock. Deterministic.
- `fortkit herald-lint <draft.md> [--json]` reads the file and prints the
  result. Text output for people, `--json` for the Herald's report.

It judges form, never quality. It never edits a draft.

## 3. Input

A Herald draft: a YAML frontmatter block between `---` lines, then the body.
The frontmatter reader supports a documented YAML subset, with no YAML
dependency (supply-chain threat 3): `key: value` scalars, block lists of
`- "quoted"` or `- bare` items, inline lists of quoted items with commas
inside quotes respected, and the `''` and `\"` escapes decoded. Lines it cannot
parse make `frontmatter` fail and are quoted in its detail, never silently
ignored (Warden finding 4 on the implementation).

The **post** is the body up to (not including) a line `## Long version`, if
present (`fortkit-r6x.8.4`); everything from that line on is ignored by every
check. Paragraphs are blocks separated by one or more blank lines.

## 4. Output: the contract

The result type is the interface. It goes in `src/types.ts` and the tests
pin it.

```ts
export type LintResultKind = "pass" | "fail" | "flag" | "judgment";

export type LintCheck = {
  id: string;            // stable, kebab-case, listed in section 5
  result: LintResultKind;
  detail: string;        // human-readable; for fail/flag, quotes the offending text
};

export type LintResult = {
  verdict: "pass" | "fail";   // "fail" iff any check is "fail"
  counts: { postChars: number; hookChars: number; paragraphs: number };
  // Characters are Unicode code points (Array.from(s).length), never UTF-16
  // units. LinkedIn's exact counting is unverified; the 1,800 ceiling sits far
  // enough under its 3,000 limit that the choice cannot cross it.
  checks: LintCheck[];        // every check in section 5, in that order, always
};
```

- **fail** breaks bar 5. The draft must be revised or spiked.
- **flag** is a heuristic hit. The Herald either fixes it or says in the report
  why it is a false positive. A flag never fails the verdict.
- **judgment** is listed every time and never decided by the tool. The Herald
  answers it in `postable:`.

Every `fail` and `flag` detail quotes the offending text in context (about 40
characters either side), and a check that can fire several times
(`paragraph-sentences`, `em-dash`, `banned-phrases`) reports every hit, not the
first (Warden finding 5 on the implementation).

Exit codes: `0` verdict pass (flags allowed), `1` verdict fail, `2` usage error
or unreadable file. Malformed frontmatter is a `fail` on `frontmatter`, exit 1,
never a crash.

## 5. The checks

Thresholds come from the Herald's law, section 4, bar 5, and the brand-voice
document. They are named constants in the module, each with a comment citing
its source.

| id | result when broken | rule |
|---|---|---|
| `frontmatter` | fail | parses; carries `date`, `model`, `status`, `sources`, `rubric`, `invented`, `postable` |
| `length` | fail | post at most 1,800 characters; detail also reports whether it is inside the 800-1,300 target |
| `hook` | fail | the first paragraph is at most 140 characters (the mobile "see more" fold cuts by characters, line breaks included, so the whole opening block is what must fit; brand-voice section 4 lets the hook span lines 1-2, which this measures together) |
| `paragraph-sentences` | fail | no prose paragraph exceeds three sentences. A paragraph is a **list**, and exempt, only if every line starts with a list marker (`-`, `*`, a bullet, or `1.`) or every line holds at most one sentence and ends in `.`, `!`, `?` or `:`. Hard-wrapped prose fails that test, because its lines break mid-sentence, so it is counted as prose (Warden finding 1) |
| `closing-question` | fail | the post's last non-empty line ends with `?` (so a trailing hashtag line fails, by design: hashtags default to none), and it does not END with any of the brand-voice section 6 banned closers ("Thoughts?", "Agree?", "Comment X if...", "What do you think about AI agents?"), matched case-insensitively, so "So, thoughts?" fails too (Warden finding 3 on the spec; finding 6 on the implementation) |
| `stacked-questions` | flag | the last paragraph holds two or more questions (brand-voice section 6) |
| `em-dash` | fail | zero U+2014 characters in the post |
| `dash-substitute` | flag | a spaced en-dash (` – `, U+2013) or a spaced `--`, the usual stand-ins (Warden finding 7) |
| `banned-phrases` | fail | none of the brand-voice section 7 phrases, case-insensitive. A phrase written with a trailing `...` or `…` in the document is a **prefix**: it matches that text followed by anything ("the part I..." matches "the part I liked"). Before any matching, typographic apostrophes and quotes (U+2018, U+2019, U+201C, U+201D) are normalized to ASCII, here and in every other text check (amended 2026-10-07, Warden finding 1 on the implementation) |
| `invented-declared` | fail | every line under `invented:` appears verbatim in the post |
| `contrastive-reframe` | flag | heuristic for "not X, it's Y" in its common spellings, including "isn't X, it's Y", "X isn't the problem, Y is", and "It wasn't X. It was Y." across two sentences |
| `setup-line` | flag | the first four non-empty lines match `/\bAI agents?\b/i` (cold-reader rule 1 says "within the first four lines"; the unit follows the source, Warden finding 4). The rule asks for varied wording, so the matcher is deliberately loose and only flags |
| `spelling` | flag | British spellings from an explicit **word list**, never a suffix pattern: labelled, labelling, neighbour(s), behaviour(s), colour(s), favour(s), honour(s), centre(s), catalogue(s), and the -ise/-ised/-ising forms of a fixed list of roots (prioritis-, deprioritis-, organis-, realis-, recognis-, optimis-, summaris-, analys-, apologis-, categoris-, minimis-, maximis-). A suffix rule matched ordinary American words (raised, promised, advertising) and a flag that fires on ordinary words teaches the Herald to ignore flags (amended 2026-10-07, Warden finding 3 on the implementation) |
| `shared-stake` | judgment | cold-reader rule 2 |
| `one-mechanism` | judgment | cold-reader rule 3 |
| `actionable-lesson` | judgment | cold-reader rule 4 |
| `cold-test` | judgment | cold-reader rule 5 |

Sentence splitting is a regex on `.`, `!`, `?` followed by whitespace. Its
known weakness (abbreviations, decimals like `6.5`) is accepted and noted in a
comment; decimals between digits must not split.

## 6. Tests

`test/herald-lint.test.ts`, vitest, synthetic fixtures only. **No real draft
goes into the repo**: unposted drafts are the Overseer's unpublished writing,
and the remote may be public.

- Every **fail** and **flag** check id has a red arm and a green arm, so a
  check that cannot fire is caught by its own test. Judgment ids are never
  decided and have no arms; the always-present test below covers them
  (Warden finding 5).
- One fully clean synthetic draft returns verdict pass, exit 0.
- `## Long version` content over every limit does not change the result.
- A five-line list (markers, or one sentence per line) passes
  `paragraph-sentences`; a five-sentence prose paragraph fails it **both
  unwrapped and hard-wrapped at 60 columns** (Warden finding 1).
- "Thoughts?" as the last line fails `closing-question`.
- `6.5 seconds` does not count as a sentence break.
- The output always contains every check id, in table order, including the
  judgment items.
- Banned-phrase consistency, **both directions** (Warden finding 2): a test
  reads `docs/proposals/herald-voice/brand-voice.md`, extracts the quoted
  phrases from section 7's stock-signpost bullet and section 6's "Banned"
  line, and asserts the code's constants equal that set exactly. A phrase the
  Overseer adds to the document without the code learning it turns the suite
  red. (That file is the reviewed source of the vault copy. What the test
  cannot see: a vault copy edited without updating the repo file.)
- CLI: exit codes 0, 1, 2 for a passing draft, a failing draft, and a missing
  file; `--json` parses and matches `LintResult`.

## 7. Wiring (not the Forge's work)

`fortkit-r6x.8.10`, Regent edict after this merges: add
`Bash(node /home/justin/dev/fortkit/src/cli.ts herald-lint*)` to
`civ/profiles/herald-settings.json`, and add a step to the morning prompt in
`civ/scripts/herald.sh`: run herald-lint on each draft before filing, paste the
`--json` checks into `postable:`, revise or spike on fail, and answer flags and
judgment items in the report.

## 8. Out of scope

Quality judgment of any kind; rewriting drafts; reading the vault; the
feedback loop (`fortkit-r6x.8.5`); the long-version format itself
(`fortkit-r6x.8.4`, which this spec only reads).

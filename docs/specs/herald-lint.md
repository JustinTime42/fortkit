# herald-lint: the Postable bar, checked by a machine

Status: DRAFT for Overseer approval (`fortkit-r6x.8.3`). Author: Emrith
Cairnwright (Mayor), 2026-10-06. Implementation: Forge. Wiring into the
Herald's runs: Regent edict (`fortkit-r6x.8.10`), after this lands.

## 1. Why

The Herald's law gained bar 5, Postable, on 2026-10-06 (`fortkit-r6x.8.2`), and
the brand-voice document gained the cold-reader rules the same day. Until now
the Herald counted em-dashes and reframes by reading its own prose, and 44 of
61 drafts went out over LinkedIn's hard limit anyway. The Overseer's standing
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
  checks: LintCheck[];        // every check in section 5, in that order, always
};
```

- **fail** breaks bar 5. The draft must be revised or spiked.
- **flag** is a heuristic hit. The Herald either fixes it or says in the report
  why it is a false positive. A flag never fails the verdict.
- **judgment** is listed every time and never decided by the tool. The Herald
  answers it in `postable:`.

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
| `hook` | fail | the first line of the first paragraph is at most 140 characters |
| `paragraph-sentences` | fail | no prose paragraph exceeds three sentences; a paragraph whose lines are separated by single newlines is a list and is exempt |
| `closing-question` | fail | the post's last non-empty line ends with `?` |
| `em-dash` | fail | zero U+2014 characters in the post |
| `banned-phrases` | fail | none of the brand-voice section 7 phrases, case-insensitive |
| `invented-declared` | fail | every line under `invented:` appears verbatim in the post |
| `contrastive-reframe` | flag | heuristic for "not X, it's Y" in its common spellings, including "isn't X, it's Y", "X isn't the problem, Y is", and "It wasn't X. It was Y." across two sentences |
| `setup-line` | flag | the first four paragraphs mention AI agents (cold-reader rule 1) |
| `spelling` | flag | British spellings from a short list (-ised, -ising, labelled, neighbour, behaviour, colour, prioritise) |
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

- Every check id has a red arm and a green arm, so a check that cannot fail is
  caught by its own test.
- One fully clean synthetic draft returns verdict pass, exit 0.
- `## Long version` content over every limit does not change the result.
- A list paragraph of five lines passes `paragraph-sentences`; a five-sentence
  prose paragraph fails it.
- `6.5 seconds` does not count as a sentence break.
- The output always contains every check id, in table order, including the
  judgment items.
- Banned-phrase consistency: a test reads
  `docs/proposals/herald-voice/brand-voice.md` and asserts each banned phrase
  constant appears in its section 7, so the code and the document cannot drift
  silently. (That file is the reviewed source of the vault copy.)
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

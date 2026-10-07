import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { describe, expect, test } from "vitest";

import {
  BANNED_CLOSERS,
  BANNED_PHRASES,
  CHECK_IDS,
  lintDraft,
} from "../src/herald-lint.ts";

const cliUrl = pathToFileURL(resolve("src/cli.ts")).href;

async function runCli(
  args: string[],
): Promise<{ code: number | null; output: string }> {
  const child = spawn(
    process.execPath,
    [
      "--input-type=module",
      "--eval",
      `console.log = (...values) => process.send?.({ output: values.join(" ") }); process.argv = [process.execPath, ${JSON.stringify(cliUrl)}, ...${JSON.stringify(args)}]; await import(${JSON.stringify(cliUrl)});`,
    ],
    { stdio: ["ignore", "ignore", "ignore", "ipc"] },
  );
  let output = "";
  child.on("message", (message) => {
    if (
      typeof message === "object" &&
      message !== null &&
      "output" in message
    ) {
      output = String(message.output);
    }
  });
  const [code] = await once(child, "close");
  return { code: code as number | null, output };
}

function draft(body: string, invented = "[]"): string {
  return `---\ndate: 2026-10-07\nmodel: test\nstatus: draft\nsources: []\nrubric: []\ninvented: ${invented}\npostable: {}\n---\n${body}`;
}

const cleanBody = `A confident AI answer can still be wrong.\n\nI build software with AI agents. One plans, one writes code, and I make the final call.\n\nYesterday a checker reported a change complete before it read the actual file.\n\nI changed the rule. Ask for proof on the real file before trusting a summary.\n\nWhere does your team require proof before a task is called done?`;

function resultFor(text: string, id: string) {
  const value = lintDraft(text).checks.find((check) => check.id === id);
  if (value === undefined) throw new Error(`Missing check ${id}`);
  return value;
}

describe("herald-lint", () => {
  test("passes a clean synthetic draft and includes each check in stable order", () => {
    const result = lintDraft(draft(cleanBody));
    expect(result.verdict).toBe("pass");
    expect(result.checks.map(({ id }) => id)).toEqual(CHECK_IDS);
    expect(
      result.checks.filter(({ result: kind }) => kind !== "judgment"),
    ).toEqual(
      expect.arrayContaining(
        CHECK_IDS.filter(
          (id) =>
            ![
              "shared-stake",
              "one-mechanism",
              "actionable-lesson",
              "cold-test",
            ].includes(id),
        ).map((id) => expect.objectContaining({ id, result: "pass" })),
      ),
    );
    expect(
      result.checks.filter(({ result: kind }) => kind === "judgment"),
    ).toHaveLength(4);
  });

  test.each([
    ["frontmatter", "not frontmatter"],
    ["length", draft(`${cleanBody}\n\n${"a".repeat(1_801)}`)],
    ["hook", draft(`${"a".repeat(141)}\n\n${cleanBody}`)],
    ["paragraph-sentences", draft(`${cleanBody}\n\nOne. Two. Three. Four.`)],
    ["closing-question", draft(cleanBody.replace(/\?$/, "."))],
    [
      "em-dash",
      draft(cleanBody.replace("still be wrong.", "still be wrong — really.")),
    ],
    ["invented-declared", draft(cleanBody, '["I was annoyed."]')],
  ])("fails %s when its red fixture is present", (id, text) => {
    expect(resultFor(text, id).result).toBe("fail");
  });

  test.each(BANNED_PHRASES)(
    "fails each banned phrase when used in normal prose: %s",
    (phrase) => {
      const prose = phrase.endsWith("...")
        ? `${phrase.slice(0, -3)} liked after the review.`
        : `${phrase} The report needed evidence.`;
      expect(
        resultFor(
          draft(cleanBody.replace("Yesterday", prose)),
          "banned-phrases",
        ).result,
      ).toBe("fail");
    },
  );

  test("normalizes curly punctuation for every text matcher", () => {
    expect(
      resultFor(
        draft(cleanBody.replace("Yesterday", "Here’s the thing. Yesterday")),
        "banned-phrases",
      ).result,
    ).toBe("fail");
    expect(
      resultFor(
        draft(
          cleanBody.replace(
            "Yesterday",
            "It wasn’t a typo. It was a missing check. Yesterday",
          ),
        ),
        "contrastive-reframe",
      ).result,
    ).toBe("flag");
  });

  test.each([
    [
      "stacked-questions",
      draft(cleanBody.replace(/\?$/, "? What do you inspect first?")),
    ],
    [
      "dash-substitute",
      draft(cleanBody.replace("still be wrong.", "still be wrong -- really.")),
    ],
    [
      "contrastive-reframe",
      draft(
        cleanBody.replace(
          "Yesterday",
          "It wasn't a typo. It was a missing check. Yesterday",
        ),
      ),
    ],
    ["setup-line", draft(cleanBody.replace("AI agents", "a small crew"))],
    [
      "spelling",
      draft(
        cleanBody.replace(
          "Yesterday",
          "Yesterday the labelled report arrived.",
        ),
      ),
    ],
  ])("flags %s when its red fixture is present", (id, text) => {
    expect(resultFor(text, id).result).toBe("flag");
  });

  test("accepts both list forms but rejects hard-wrapped prose", () => {
    const markedList = `- One sentence.\n- Two sentence.\n- Three sentence.\n- Four sentence.\n- Five sentence.`;
    const lineList = `One sentence.\nTwo sentence.\nThree sentence.\nFour sentence.\nFive sentence.`;
    const wrapped = `One sentence continues across this long enough line that it\nwraps before the punctuation. Two sentence also continues across\nthe wrap before it ends. Three sentence continues here without a\nperiod until later. Four sentence is another ordinary sentence. Five sentence ends.`;
    expect(
      resultFor(draft(`${cleanBody}\n\n${markedList}`), "paragraph-sentences")
        .result,
    ).toBe("pass");
    expect(
      resultFor(draft(`${cleanBody}\n\n${lineList}`), "paragraph-sentences")
        .result,
    ).toBe("pass");
    expect(
      resultFor(draft(`${cleanBody}\n\n${wrapped}`), "paragraph-sentences")
        .result,
    ).toBe("fail");
  });

  test("does not split decimal numbers and ignores the long version", () => {
    const withDecimal = cleanBody.replace(
      "Yesterday",
      "After 6.5 seconds, yesterday",
    );
    const withLongVersion = `${cleanBody}\n\n## Long version\n${"— Here's the thing. ".repeat(200)}`;
    expect(resultFor(draft(withDecimal), "paragraph-sentences").result).toBe(
      "pass",
    );
    expect(lintDraft(draft(withLongVersion))).toMatchObject({
      verdict: "pass",
    });
  });

  test.each(BANNED_CLOSERS)("rejects banned closing question %s", (closer) => {
    const actual =
      closer === "Comment X if..." ? "Comment coffee if you agree?" : closer;
    expect(
      resultFor(
        draft(cleanBody.replace(/Where.*$/, actual)),
        "closing-question",
      ).result,
    ).toBe("fail");
  });

  test("rejects a banned closer at the end of a longer closing line", () => {
    expect(
      resultFor(
        draft(cleanBody.replace(/Where.*$/, "So, thoughts?")),
        "closing-question",
      ).result,
    ).toBe("fail");
  });

  test("parses quoted invented values and fails unsupported frontmatter", () => {
    const quoted = draft(
      `${cleanBody}\n\nA line, with a comma.\n\nIt's checked.`,
      "[\"A line, with a comma.\", 'It''s checked.']",
    );
    expect(resultFor(quoted, "frontmatter").result).toBe("pass");
    expect(resultFor(quoted, "invented-declared").result).toBe("pass");
    const malformed = quoted.replace("status: draft", "  not: yaml");
    expect(resultFor(malformed, "frontmatter")).toMatchObject({
      result: "fail",
      detail: expect.stringContaining('"  not: yaml"'),
    });
  });

  test("uses the explicit spelling list without flagging ordinary American words", () => {
    expect(
      resultFor(
        draft(
          cleanBody.replace(
            "Yesterday",
            "Yesterday the prioritised report arrived.",
          ),
        ),
        "spelling",
      ).result,
    ).toBe("flag");
    for (const word of ["raised", "promised", "advertising"])
      expect(
        resultFor(
          draft(
            cleanBody.replace(
              "Yesterday",
              `Yesterday the ${word} report arrived.`,
            ),
          ),
          "spelling",
        ).result,
      ).toBe("pass");
  });

  test("reports each repeated fail hit with local context", () => {
    const body = `${cleanBody}\n\nOne. Two. Three. Four.\n\nFive. Six. Seven. Eight.\n\nA — B — C. Here's the thing. Let that sink in.`;
    for (const id of ["paragraph-sentences", "em-dash", "banned-phrases"]) {
      const value = resultFor(draft(body), id);
      expect(value.result).toBe("fail");
      expect(value.detail).toContain(",");
    }
  });

  test("keeps banned phrase constants aligned with reviewed brand voice", async () => {
    const source = await readFile(
      "docs/proposals/herald-voice/brand-voice.md",
      "utf8",
    );
    const stock =
      source.match(/- Stock signposts[^:]*: ([\s\S]*?)\n- An aphorism/)?.[1] ??
      "";
    const phrases = [...stock.matchAll(/"([^"]+)"/g)].map(
      (match) => match[1]?.replace(/\s+/g, " ").replace(/…$/, "...") ?? "",
    );
    const banned = source.match(/Banned: ([\s\S]*?)\n\n/)?.[1] ?? "";
    const closers = [...banned.matchAll(/"([^"]+)"/g)].map(
      (match) => match[1]?.replace(/\s+/g, " ") ?? "",
    );
    expect(BANNED_PHRASES).toEqual(phrases);
    expect(BANNED_CLOSERS).toEqual(closers);
  });

  test("CLI uses documented exit codes and JSON contract", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-herald-lint-"));
    const passing = join(root, "pass.md");
    const failing = join(root, "fail.md");
    await writeFile(passing, draft(cleanBody));
    await writeFile(failing, draft(cleanBody.replace(/\?$/, ".")));
    try {
      const passed = await runCli(["herald-lint", passing, "--json"]);
      expect(passed.code).toBe(0);
      expect(JSON.parse(passed.output)).toMatchObject({
        verdict: "pass",
        counts: {
          postChars: expect.any(Number),
          hookChars: expect.any(Number),
          paragraphs: expect.any(Number),
        },
        checks: expect.arrayContaining([
          expect.objectContaining({
            id: "frontmatter",
            result: "pass",
            detail: expect.any(String),
          }),
        ]),
      });
      expect((await runCli(["herald-lint", failing])).code).toBe(1);
      expect(
        (await runCli(["herald-lint", join(root, "missing.md")])).code,
      ).toBe(2);
      expect((await runCli(["herald-lint"])).code).toBe(2);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

"""Prototype of the bar-5 / cold-reader checks for herald-lint (fortkit-r6x.8.3).

Used by the Mayor on 2026-10-06 to check the r6x.8.7 rewrites. NOT production
code: the Forge rebuilds it as a tested script under scripts/. Known gaps:
the contrastive-reframe regex is a heuristic (it caught none and may miss
"X. Not Y." forms); the setup-line test only looks for "AI agents" in the
first four paragraphs; shared-stake, one-mechanism and the cold test stay
judgment calls for the Herald and are reported, never auto-passed.
"""
import re  # noqa: F401  (used inside checks)


def checks(body: str, invented: list[str]) -> list[str]:
    import re
    paras = [p for p in body.split("\n\n") if p.strip()]
    hook = paras[0].split("\n")[0]
    sentences = lambda p: len([s for s in re.split(r"(?<=[.!?])\s+", p.strip()) if s])
    banned = ["the part i", "here's the part", "here is the part", "what i want to draw out",
              "here's the thing", "let that sink in", "thoughts?", "agree?"]
    reframe = re.compile(r"\b(?:is|was|isn't|wasn't|it's|that's) not\b[^.?!]*?,\s*(?:it|that)(?:'s| is| was)\b|\bisn't\b[^.?!]*?,\s*it's\b", re.I)
    out = [
        f"length: {len(body)} chars (ceiling 1800) {'PASS' if len(body) <= 1800 else 'FAIL'}",
        f"hook: {len(hook)} chars (max 140) {'PASS' if len(hook) <= 140 else 'FAIL'}",
        f"paragraphs <= 3 sentences: {'PASS' if all(sentences(p) <= 3 or '\n' in p for p in paras) else 'FAIL'}",
        f"ends on a question: {'PASS' if body.rstrip().endswith('?') else 'FAIL'}",
        f"em-dashes: {body.count(chr(0x2014))} {'PASS' if chr(0x2014) not in body else 'FAIL'}",
        f"contrastive reframes: {len(reframe.findall(body))} {'PASS' if not reframe.findall(body) else 'FAIL'}",
        f"banned phrases: {'PASS' if not any(b in body.lower() for b in banned) else 'FAIL'}",
        f"setup line in first 4 paragraphs: {'PASS' if 'AI agents' in chr(10).join(paras[:4]) else 'FAIL'}",
        f"invented lines declared and present: {'PASS' if all(i in body for i in invented) else 'FAIL'}",
    ]
    return out

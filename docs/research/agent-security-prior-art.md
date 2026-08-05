# Agent security: prior art, landscape, and an honest novelty assessment

Compiled 2026-08-05 for the publication office. **Read this before drafting anything public.** The office's standing bar is no unverified claims; claiming novelty that already exists in the literature is the fastest way to lose that. Sources are linked; verify them yourself rather than trusting this summary, and append rather than rewrite as the picture changes.

## Why this document exists

The civilization's mechanical findings are well persisted (bead close reasons, charters, `remember.md`, the probe suite's own header comments). The *landscape* was not: it lived only in a conversation. A finding is only publishable if you know whether someone published it first, so that knowledge belongs beside the findings.

## The sandboxing landscape (2026)

Where the major agents stand on isolation:

- **Claude Code** — bubblewrap on Linux, Seatbelt on macOS. **Opt-in, off by default.**
- **OpenAI Codex** — Landlock + seccomp, **on by default**. Note the caveat we measured ourselves: Codex's Linux sandbox does not enforce deny-*read* (upstream `openai/codex#11316`), which is why this civilization runs a bwrap layer beneath it.
- **Gemini CLI** — Docker/Podman, opt-in.
- Broader ecosystem: microVMs (Firecracker), gVisor, and hosted sandboxes (E2B, Daytona, Northflank) for the "run untrusted code" case.

Published best practice matches what we do: bind only what the agent needs, bind everything else read-only or to a no-op, layer seccomp on top. See [Coding Agents V: Why Bubblewrap Wraps Agents](https://blog.palaimon.io/posts/coding-agents-bubblewrap-deep-dive/index.html), [UBOS: Securing AI Coding Agents with Bubblewrap](https://ubos.tech/news/securing-ai-coding-agents-with-bubblewrap-a-new-approach-to-protect-secrets/), the [SandboxedClaudeCode](https://github.com/CaptainMcCrank/SandboxedClaudeCode) repo, and [Sandlock: Confining AI Agent Code with Unprivileged Linux Primitives](https://arxiv.org/pdf/2605.26298).

**Conclusion: bwrap-based agent sandboxing is established practice, not a contribution.** Do not present it as one.

## Prior art, finding by finding

| Our finding | Prior art | Verdict |
|---|---|---|
| Deny rules bind a *spelling*, not a file (quote/glob forms: `.e"n"v`, `.[e]nv`, `.??v`, 6/6 across two profiles) | **Same class, published first.** Ona (Leonardo Di Donato), April 2026: Claude Code escaped its own denylist because `/proc/self/root/usr/bin/npx` resolves to the blocked binary without matching the deny pattern — [writeup](https://ona.com/stories/how-claude-code-escapes-its-own-denylist-and-sandbox). Also CVE-2025-53109/53110 (path-prefix bypass via symlinks in a filesystem MCP server). | **Not novel.** Our *vectors* (shell quoting/globbing) appear undocumented, but the class is known. Cite Ona when discussing it. |
| Deny rules don't cover bash subprocesses; sandboxing is the real boundary | Published: ["Claude Code's Deny Rules Don't Protect You — Here's What Actually Does"](https://adamkinney.com/aatt/claude-code/deny-rules-dont-protect-you-sandbox-does/) | **Not novel.** Same conclusion we reached. |
| Mount-level masking beats pattern matching | Established best practice across the sources above; content-addressable enforcement (SHA-256 at the BPF LSM layer) is the stronger published version | **Not novel.** |
| **A model cannot probe its own leash** — a refusal and an enforced wall are indistinguishable in a transcript, so model-driven boundary tests prove nothing (measured 4×) | **No prior art found.** | **Appears novel.** Strongest publishable idea we hold. |
| The probe methodology: shell-driven tests, neutral decoys where refusal isn't a confound, negative controls with differential twins, and a verdict vocabulary where `NAMED` ≠ `PASS` | No published equivalent found; the literature demonstrates once and asserts | **Appears novel**, and is the artifact gap: plenty of guidance on what to mount, almost nothing that tests whether mounts hold. |
| Reciprocal cross-runtime masking (each runtime blind to the other's credentials) | None found | Likely novel, minor. |
| Config self-protection: the file governing the agent is kernel-read-only to it, because a rule saying "don't edit the rules" is enforced by the system it guards | Discussed in fragments; the explicit recursion framing not found | Likely novel framing of a known instinct. |
| The airlock: seats request declared privileged operations; the broker holds credentials | Old pattern (ssh-agent, sudo, CI secret stores); applying it to agent harnesses with a declared-operations whitelist is less common | Not novel as a pattern; the application is a reasonable contribution. |

## What this means for publication strategy

1. **Lead with the leash finding and the methodology, not the bypass.** The bypass is a known class; the instrument is the gap.
2. **Frame everything as measurement, never discovery.** "I tested my own boundary and here is what I found" is unfalsifiable-proof and matches the standing bar. The published 2026-08-04 post got this right by instinct — it claims no novelty anywhere.
3. **Cite prior art proactively.** Naming Ona and the deny-rules-don't-protect-you piece before a commenter does converts a correction into a conversation.
4. **The probe suite is the highest-value artifact.** Nobody is shipping a thing that tells you whether your agent sandbox actually holds.

## Open question, and a probe worth running first

The Ona escape used `/proc/self/root` path aliasing. **In principle** our mount-level masks are immune, since `/proc/self/root` resolves inside the same namespace and lands on the same tmpfs — that is precisely why mount enforcement beats pattern matching. But *in principle* is the phrase the probe suite exists to eliminate. Add probes for `/proc/self/root/<masked path>`, `/proc/self/cwd/...`, symlink reaches, hard links, and bind-mount aliases at every masked path.

If they hold, we have a measured claim no one else has published. If they don't, we found it in our own fence before someone else did. Either outcome is worth more than the assumption.

## Still unwritten (known gaps at time of compiling)

- The niche/positioning analysis (where agent-harness security sits relative to model-safety research and the AI-product-security market, and what a practitioner without security credentials can credibly own).
- The full reasoning behind the threat model's priority order, beyond what the charters record.
- The "is this overengineering" calibration discussion: which controls were justified by observed incidents versus imagined adversaries, which produced standing order 15.

These lived in a working conversation and are summarized here only as headings. Reconstruct from the charters, `21f` bead notes, and the annals if they are needed.

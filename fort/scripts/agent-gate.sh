#!/bin/bash
# THE AGENT GATE (Proofdelve ForgeOs-lr8h, enforcement half; Regent edict 2026-10-06,
# Overseer present). A PreToolUse hook on the Agent tool, wired in
# .claude/settings.json, so it binds every Claude session started in this repo:
# in practice the Mayor, the one seat that holds the Agent tool (the Warden's
# launcher grants Bash,Read,Grep,Glob,Edit only; the Forge is codex).
#
# THE INCIDENT (2026-08-10): research subagents dispatched from a session
# running with bypassed permissions inherited that mode, carried Bash, fanned
# out to further subagents, and actively probed eighteen third-party OAuth/MCP
# endpoints. Standing order 14's outbound half (ratified 2026-09-01) forbids it
# in prose; this file is the mechanism.
#
# AN ALLOWLIST, NOT A DENY LIST. Only the fort's two constrained types may be
# spawned, both defined in .claude/agents/ (kernel read-only to every seat):
#   web-research  WebSearch, WebFetch       -- learn from the web, change nothing
#   code-search   Read, Grep, Glob          -- local inventory, no shell
# Neither carries Bash or the Agent tool, so a subagent can neither curl a
# third party nor spawn a grandchild: SPAWN DEPTH IS ONE BY CONSTRUCTION, and
# every spawn and refusal is appended to fort/telemetry/agent-spawns.jsonl
# (the PermissionRequest hook's pattern), which is how the dispatcher and the
# Overseer see it. Any other type -- general-purpose, Explore, Plan, a plugin's,
# a user-level one -- is refused with a reason the dispatcher reads (exit 2).
# Measured 2026-10-06 in a scratch project under --dangerously-skip-permissions:
# general-purpose REFUSED with this text, web-research spawned and reported its
# tools as WebSearch and WebFetch only; with the hook removed, general-purpose
# ran (the control). Hooks run whatever the permission mode.
# THE MATCHER IS ANCHORED, ^(Agent|Task)$ (the Warden, finding B1a on the sitting):
# unanchored, a regex reading of Agent|Task would also catch TaskCreate and its
# family -- failing closed, but breaking the Mayor's task tools. Measured: the
# anchored form still gates Agent. TWO LIMITS, recorded rather than fixed:
# (b) a hook that cannot execute (126/127) does not block in Claude Code, so the
# gate fails OPEN if this file's absolute path ever goes missing; the path is
# the main checkout, kernel read-only to every seat. And a nested `claude -p`
# started from the Mayor's Bash is a spawn this gate never sees; standing order
# 14(a) remains the control for that route.
in=$(cat)
# MANYHALLS: SEATS ONLY. This repository is also the civilization's capital, and
# sessions that are not this fort's seats start here: the Overseer's own, and the
# Regent's. Those run unmasked and carry no FORT_MASKED marker; every seat this
# fort launches carries one (lib/seat-sandbox.sh seat_identity, workbench.sh).
# The gate binds the marked sessions and lets the others through unrecorded.
# The fort this file came from has no such sessions and gates every one.
# (Regent sitting 2026-11-18, fortkit-ttpk.)
[ -n "${FORT_MASKED:-}${FORT_SEAT_UNMASKED:-}" ] || exit 0
t=$(printf '%s' "$in" | jq -r '.tool_input.subagent_type // "general-purpose"' 2>/dev/null) || t="unparseable"
log="$(dirname "$0")/../../fort/telemetry/agent-spawns.jsonl"
case "$t" in
  web-research|code-search) decision=allowed ;;
  *) decision=refused ;;
esac
jq -cn --arg t "$t" --arg d "$decision" '{ts: (now|todate), subagent_type: $t, decision: $d}' >> "$log" 2>/dev/null || true
[ "$decision" = allowed ] && exit 0
echo "agent-gate (Proofdelve ForgeOs-lr8h): subagent type '$t' is refused in this fort. Use web-research (WebSearch, WebFetch only) for anything on the web, or code-search (Read, Grep, Glob) for local inventory. Neither can run commands or spawn agents." >&2
exit 2

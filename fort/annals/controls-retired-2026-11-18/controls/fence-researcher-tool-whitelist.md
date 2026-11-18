---
key: fence-researcher-tool-whitelist
status: active
kind: fence
refuses: "Bash and Agent to the Researcher seat, by omission from --tools"
implements: fort/scripts/researcher.sh:56
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
THE SEAT'S ACTUAL BOUNDARY. --tools WebSearch,WebFetch,Read,Grep,Glob. This is
capability separation as an answer to ForgeOs-lr8h: the seat that reads about
the world is never the seat that touches it. Not portable to Codex, which has no
tool-whitelist flag and whose agent always holds a shell (mayor-2026-08-25).

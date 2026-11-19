---
key: falsifier-verdict-record-harness
status: active
kind: falsifier
detects: "A Warden verdict that would not be captured from the transcript"
implements: scripts/verdict-record-harness.sh:1
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Answers the fort's most-repeated incident: 'recorded NO verdict: no VERDICT-LINE
in transcript' appears eight times in the incident log. fortkit-7kzi is open —
researcher.sh has the same shape and the bound can still be beaten by an
EARLIER VERDICT-LINE.

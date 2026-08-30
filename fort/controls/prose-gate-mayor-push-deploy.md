---
key: prose-gate-mayor-push-deploy
status: active
kind: prose-gate
refuses: "The Mayor pushing or deploying without asking the Overseer first, every time"
implements: fort/charter.md:75
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Cycle 6. The charter records this as deliberately weaker than a capability
boundary and says why: routing every push through a human terminal cost more
than the risk it removed. Reverts to a capability boundary if this fort ever
touches production or live customer data.

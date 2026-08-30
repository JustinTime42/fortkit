---
key: fence-warden-deny-set
status: active
kind: fence
refuses: "Every write verb and secret-path read at the Warden's tool layer"
implements: fort/profiles/warden-settings.json:46
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
37 deny entries. THE FILE ADMITS ITS OWN FENCE-NESS at :2, and it is the
clearest statement of the wall/fence distinction the fort wrote before it had
the word: 'Treat the allow list as convenience, the deny list as the boundary',
and 'deny globs bind a spelling, not a file'.
KNOWN VERB-INCOMPLETE: fortkit-ypv1 is open because Bash(find *) is allowed and
find -delete is a write. This fence is the SOLE mitigation named in the
fortkit-3jv7 charter residual, so its incompleteness is load-bearing.

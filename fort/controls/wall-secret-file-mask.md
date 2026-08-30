---
key: wall-secret-file-mask
status: active
kind: wall
refuses: "Reads of .env* and secret-glob files, in every mask"
implements: fort/scripts/lib/seat-sandbox.sh:148
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Sweeps secret globs into MASK_FILES, each bound over with /dev/null at :479.
LIMIT STATED IN ITS OWN SOURCE at :140-148 and registered here rather than left
in a comment: a DIRECTORY named environments~ or .env.d is not descended into,
so secret files inside one are readable inside every mask. Human gate 2 is the
policy this implements; this is the mechanism, and the two are not co-extensive.

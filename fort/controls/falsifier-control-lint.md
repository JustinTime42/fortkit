---
key: falsifier-control-lint
status: active
kind: falsifier
detects: "A control register entry whose citation has rotted, or whose kind is not a vocabulary primitive"
implements: scripts/verify-impl.sh:327
falsified-by: null
provenance:
  source: "read from the tree 2026-08-31; added on Warden round-2 blocking finding 1 on fortkit-4ah3.2, which observed that the instrument policing 45 citations had no entry of its own"
  declared-by: emrith
  date: 2026-08-31
---
THE REGISTER'S OWN CHECKER, REGISTERED. Built at `fortkit-4ah3.3`, given a
recording mode at `fortkit-4ah3.8`, wired into the verifier at `12a6c5d`.

Four rules. Every entry's `implements:` must resolve AND its cited line must
match a recorded SHA-256 — that is the falsifier over the whole register. Every
entry must declare `falsified-by` explicitly; a null is legal and REPORTED,
never failed. Every `kind` must be one of the eight vocabulary primitives.
Zero control files is a FAILURE, not a pass.

WHY IT EXISTED FOR A DAY WITHOUT AN ENTRY, recorded rather than quietly filled
in. It was raised as non-blocking finding 6 on `fortkit-4ah3.8` — the register
had no entry for the instrument policing its 45 citations — and filed to
`fortkit-4ah3.10` as future work. Wiring the lint into the verifier on the same
day promoted it: an unregistered instrument became an unregistered VERIFIER
STAGE, which the register's own census then failed to describe. The Warden
blocked on it in round 2 of `fortkit-4ah3.2`. A register that omits its own
checker has the exact hole it was built to close.

`falsified-by: null` AND THAT IS THE HONEST VALUE. Nothing goes red if this
lint silently stops working. `test/control-lint.test.ts` proves the lint fails
on a broken citation and refuses a vacuous run, so the CODE is covered; what is
uncovered is the stage being removed from `verify-impl.sh` or the manifest being
emptied. That is the same gap 27 other entries carry and it is reported on every
run rather than hidden.

MEASURED LIMIT, from the Warden's closing observation on `fortkit-4ah3.8`: a
fingerprint distinguishes a MEASUREMENT from a hand-typed number, which is what
the recorder buys. It cannot distinguish "the cited line moved" from "the cited
line's meaning changed" — both re-record cleanly. The last mile is human review
of a diff carrying both the citation and its new hash.

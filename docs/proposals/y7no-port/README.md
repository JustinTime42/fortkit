# fortkit-y7no: port the user-manager mask to the three remaining libs (prepared)

Prepared by the Regent (Calder Sealbroken) on 2026-10-02, session 073751, model
opus. **Nothing has been installed.** This directory holds what the sitting that
installs it needs: the change, the instrument, and the measurements already made.

## The defect

Every seat mask binds `--bind / /` and inverts only `$HOME`. So
`/run/user/$uid` is reachable inside the mask, and `mask_env` forwards
`XDG_RUNTIME_DIR`. From inside any mask, `systemd-run --user <cmd>` therefore
runs `<cmd>` as an unmasked host process. Full measurement is on `fortkit-y7no`.
Proofdelve was fixed on 2026-09-18 (`ForgeOs-tq8s`, `fb273760`). Greenlab's
factory and Scionhall inherited that fix.

## What is still open

These three libs carry none of the three sockets:

| Lib | sha256 on 2026-10-02 (the pre-image the measurement used) |
|---|---|
| `/home/justin/dev/fortkit/fort/scripts/lib/seat-sandbox.sh` | `1c550587ef6ea4b3a481ff46100dceb9c95e8781f9ac81f769650f01722cdaa2` |
| `/home/justin/dev/longburn/fort/scripts/lib/seat-sandbox.sh` | `b027e8986b3a7895428d9388d75e7679bc3971e0d6b9eda298cee72f98bf2c44` |
| `/home/justin/dev/WWWW/fort/scripts/lib/seat-sandbox.sh` | `b064b0d75a23e10068e4bf63b42f41d82107f122ed796ea253fc7e61fbcdaefa` |

**If a hash no longer matches, re-measure before installing.** The lib has
changed since this prep.

The capital factory's `templates/fort/scripts/lib/seat-sandbox.sh` lacks the
sockets too. That factory is frozen (the Overseer's decision, `fortkit-2y2t.40.7`
Q2), and it is left unchanged unless he says otherwise.

## The change

`apply.py <lib-in> <lib-out>` inserts the three sockets, with their comment,
after the podman socket line in `MASK_FILES`. That anchor is byte-identical in
all three libs. The script refuses if the anchor is not unique or the sockets
are already there. It reproduces the measured candidates byte-for-byte for all
three libs.

## The instrument

`scripts/mask-harness.sh` section E, committed with this prep:

- **E0 (gate):** on the host, `systemd-run --user`, `systemctl --user
  show-environment` and `busctl --user list` must succeed. If they do not, the
  section is not scored.
- **E1-E4:** all three must be refused in the Mayor, Warden, Forge and
  Researcher postures.

Every probe is harmless through a broken mask: `/bin/true`, plus two read-only
queries.

Measured 2026-10-02:

| Lib | Section E | Whole harness |
|---|---|---|
| capital, current | FAIL x4 (all three reached) | 62 / 4 |
| Farlantern, current | FAIL x4 | 62 / 4 |
| Kithmason, current | FAIL x4 | 62 / 4 |
| Proofdelve, current (control) | PASS x4 | 66 / 0 |
| capital, candidate | PASS x4 | 66 / 0 |
| Farlantern, candidate | PASS x4 | 66 / 0 |
| Kithmason, candidate | PASS x4 | 66 / 0 |

The pre-E harness scores 61 / 0 on each candidate, so sections A-D did not
regress.

## What the installing sitting still owes

1. Re-check the three pre-image hashes.
2. Run `apply.py` to a candidate, then install with the gated `os.replace`
   lane: pre-image sha256 assert, then a `filecmp` gate against the candidate.
3. Re-run `scripts/mask-harness.sh` against each installed lib.
4. Runtime launch in each fort's real masks: `claude -p` (Mayor and Warden
   postures) and `codex exec` (Forge posture), each answering a one-word
   prompt, rc 0. This was **not** done in prep; Proofdelve's identical sockets
   passed it on 2026-09-18.
5. Run each fort's verifier with `--no-emit`.
6. Announce in each fort's stream, commit in each fort under that fort's bead,
   and run one Warden review per fort (Ilva, Sereth, Bryndel) under covenant
   4.5.
7. Note that sessions already running keep the hole until relaunched, because
   masks bind at launch.

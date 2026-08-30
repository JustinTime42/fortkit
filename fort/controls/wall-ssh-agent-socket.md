---
key: wall-ssh-agent-socket
status: active
kind: wall
refuses: "Access to the SSH agent socket for seats that never push"
implements: fort/scripts/lib/seat-sandbox.sh:153
falsified-by: falsifier-mask-harness
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Masked when mask_ssh_auth_sock is set. The Mayor keeps it because the Mayor is
the seat that pushes; the unattended Forge does not.

#!/usr/bin/env python3
"""fortkit-y7no: insert the user manager's three doors into a seat-sandbox.sh.

Usage: apply.py <lib-in> <lib-out>
Writes <lib-out>; never edits <lib-in>. Refuses (exit 3) unless the anchor (the
podman socket line in MASK_FILES) occurs exactly once and the three sockets are
not already present. Prepared 2026-10-02; see README.md beside it.
"""
import sys

ANCHOR = '    "/run/user/$uid/podman/podman.sock"\n'
INSERT = '''    # THE USER MANAGER'S THREE DOORS (fortkit-y7no; first applied in Proofdelve
    # as ForgeOs-tq8s, fb273760, 2026-09-18). This lib binds `--bind / /` and
    # inverts only $HOME, so /run/user/$uid was never masked and mask_env
    # forwards XDG_RUNTIME_DIR: from inside every seat mask, `systemd-run
    # --user` started an UNMASKED host process that saw the host's mount table,
    # read the inode-masked secret at its full byte count and could write
    # fort/scripts (measured 2026-09-10, both arms). Every kernel guarantee in
    # this file is void for a seat that runs that one command. Three sockets,
    # not one: with `bus` alone masked, systemd-run is refused but `systemctl
    # --user` still reaches the manager through systemd/private (measured
    # 2026-09-18), and io.systemd.Manager is the varlink door beside it. With
    # all three masked, systemd-run, systemctl and busctl fail "Connection
    # refused" by the kernel and both runtimes still launch.
    # scripts/mask-harness.sh section E asserts it for every posture.
    "/run/user/$uid/bus"
    "/run/user/$uid/systemd/private"
    "/run/user/$uid/systemd/io.systemd.Manager"
'''


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: apply.py <lib-in> <lib-out>")
    text = open(sys.argv[1]).read()
    if '"/run/user/$uid/systemd/private"' in text:
        print("REFUSED: the sockets are already masked in %s" % sys.argv[1], file=sys.stderr)
        sys.exit(3)
    n = text.count(ANCHOR)
    if n != 1:
        print("REFUSED: anchor found %d times in %s, want 1" % (n, sys.argv[1]), file=sys.stderr)
        sys.exit(3)
    open(sys.argv[2], "w").write(text.replace(ANCHOR, ANCHOR + INSERT))


main()

# Herald systemd user timer (fortkit-r6x.7)

Drafted by the Mayor; **installed by the Overseer's hand** — these files do
nothing until copied out of the repo. The Herald must launch unmasked, and a
systemd user service is unmasked by construction (the seat's own kernel mask
is applied inside herald.sh).

## Install (Overseer)

```bash
mkdir -p ~/.config/systemd/user
cp ~/dev/fortkit/civ/systemd/herald.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now herald.timer

# Required for unattended mornings: the user systemd instance must outlive
# login sessions, or the 05:00 timer only fires while a session is open.
loginctl enable-linger justin
```

## Verify

```bash
systemctl --user list-timers herald.timer   # NEXT should show the coming 05:00
systemctl --user start herald.service       # optional supervised dry run
journalctl --user -u herald.service -e      # launcher output + tail of the run
```

## Acceptance mapping (r6x.7)

1. **Timer active** — `list-timers` shows it scheduled.
2. **One unattended morning produces a report** — check
   `~/Documents/Obsidian Vault/herald/reports/<date>.md` and the paired
   `session.start`/`session.end` in `civ/events/`.
3. **Missed-morning catch-up verified once** — leave the machine off or asleep
   across a 05:00, then confirm the run fires shortly after wake
   (`Persistent=true`) and the report carries the catch-up date.

## Failure surfacing

Primary signal: herald.sh's own `incident` event + crash-stub report (exit 65
path), with the service unit relaunching once on the next ladder rung
(gpt-5.6-sol). Secondary signal: a failed unit in
`systemctl --user --failed` and the journal.

**Known gap until fortkit-izz is fixed:** if the vault itself is unwritable,
herald.sh's crash-stub writer dies at exit 1 with *no* incident and no
session.end — under the timer that failure surfaces only through the
secondary signal (failed unit / journal), not the event stream. izz's
pre-flight vault-writability probe closes this; fixing izz before relying on
unattended mornings is recommended.

## Notes

- The `gpt-5.6-sol` rung-2 model string is passed straight to
  `claude --model`; if the CLI's spelling for Sol differs, correct it in
  herald.service at install time and note it on the bead.
- herald.sh date-names its /tmp log, and a same-day relaunch truncates it
  (fortkit-izz). The service moves rung 1's log aside before the rung-2
  relaunch so no transcript is lost to failover.

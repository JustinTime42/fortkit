# Civilization-layer event stream

Append-only JSONL, one file per day, written by `civ/scripts/emit.sh`, on the
canonical schema in `schema/events.md` (same shape as every fort's stream, so one
reader serves both). Daily files are gitignored; this README is tracked.

**What lands here:** happenings of the civilization layer itself — moots, seat
foundings and namings, covenant amendments, civ handoffs, incidents involving
these seats.

**What does NOT land here alone:** work a civ seat does inside a settlement. That
is announced in *that fort's* stream, per covenant section 4.2, because a seat
operating above a fort's constitution and invisible in its record is
indistinguishable from a compromise. Announce in both when the work is both.

**Actors** are the civ seats by their own names, never a fort seat's name and
never `harness`. Emitting as another fort's citizen is a recorded incident class
in this civilization and it has happened more than once.

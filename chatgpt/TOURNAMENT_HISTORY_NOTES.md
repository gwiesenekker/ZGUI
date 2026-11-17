# Saved tournament games in Game History

Implementation commit: `44e1607`.

Authorization 2026-11-17: user answered **“Apply now; waive prior review”** for
double-clicking a saved tournament game to load/select it in Game History through
the shared tournament/history selection path. Applies to chess and draughts.

## Reuse

The existing mouse-down selection path only finds a live-session reference.
Add a double-click path that first reuses a currently running game. For saved
records, render the existing TTournamentGameRecord through its existing PGN/PDN
projection, then use the existing PGN entry importer or the existing PDN parser,
main-form rebuild and full-variation import methods. No new move parser, tree,
runner, replay engine or scheduler.

Use the existing TRunningGame container with no runner, finished lifecycle and
no reservations. History identity is variant + tournament UUID + saved game
number + attempt. Tag live games with the same key when registered, so reloading
that event cannot create a second entry for an existing live/finished game.
Repeated selection preserves local annotations/branches; the effective saved
result/status updates through the existing header command. Unplayed rows do not
create placeholder entries. A rescheduled attempt gets a distinct identity.
Imported history does not borrow the dialog lifetime or file lease.

Reuse ReadSettings for the event's clock snapshot, skipping only adjudicator
availability during viewing. Thus historical games remain viewable when their
adjudicator registration is unavailable, and opening history never starts engines.
Loading/repeated selection does not write tournament records or files. Header
updates preserve local moves/comments instead of replacing an already-added tree.

## Validation

GTK2 application build, all 27 GUI suites, full headless regression and both
tournament suites pass. The dedicated fixture passes 33 assertions (including
a focused missing-adjudicator extension); complete tabs pass 415 assertions.
No test memory leaks are reported. Dedicated both-game fixtures cover a saved mainline, comment,
variation, known result and subsequent referee correction; no runner/reservations;
repeat clicks and same-event reload; unplayed rows; unchanged source file. Existing
live-game tab tests exercise double-click without duplicating its game or worker.
The full GUI suite, headless regression and both tournament suites are required.
Native Windows execution remains outstanding.

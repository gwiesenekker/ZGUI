# Six-row tournament settings layout

Authorization 2026-11-17: user answered **“Apply now; waive prior review”** for
the six-row tournament layout, measured sizing and vertical alignment, retaining
concurrency on the Play row and preserving tournament behavior.

Rows for both games:
1. Chess/Draughts selector, tournament name.
2. Starting FEN, ballot file/path, Clear ballot, reserved position count.
3. Time controls.
4. Time forfeit and enabled adjudication inputs.
5. Pairing radio group with vertically centered Create/Clear action stack.
6. Play, concurrency, Stop, Save and Load.

Reuse LayoutRow/PrepareCell and existing controls/events. Extend LayoutRow with
an overload for multiple expanding cells, so FEN and ballot path share available
space while preserving the measured complete FEN/count minimums. Default engine
choice width follows its values; label/input cells are vertically centered.

The larger combined header exposes partial-minimum notifications during the old
tournament RefreshLayout override: the base pass published a preliminary minimum,
then the override published another. On a populated large-font embedded tab this
could keep native resize processing busy. Add a no-op protected MeasureLayout
hook in the existing guarded base pass and put the tournament measurements there,
before RefreshMinimum publishes the final result. Other forms retain their normal
base measurements. No new panels with bespoke pixel-positioning or duplicate
scheduler/game configuration logic.

The user's SB screenshot was also checked against uTournamentModel. Its two scores
159 and 157 give (159/2)*157 = (157/2)*159 = 12481.5, explaining the equal large
SB values in a head-to-head match. No scoring change is made.

## Validation

Focused tournament font/size/DPI inspection initially passes 1552 assertions;
updated six-row ordering, vertical centering and large-font presentation checks
pass 258 assertions with populated engine fixtures. Final GTK2 application build, all 27 GUI suites, full regression and both
tournament suites pass. Inspect the final normal/enlarged-font captures; the
time-forfeit chooser includes measured arrow/text margin. All GUI runs use an isolated hidden display.
Native Windows execution remains outstanding.

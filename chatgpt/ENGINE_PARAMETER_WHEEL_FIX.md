# Engine parameter mouse-wheel delay

2026-10-31. User authorisation: “Please fix!” after reporting a delay at the start
of mouse-wheel scrolling and being informed of the shared-GUI review requirement.
Scope: the existing parameter grid's wheel mode only. This is the named user
exception under AGENTS.md; Claude can review the resulting commit afterwards.

The grid used Lazarus's default mwCursor: wheel events move the selected row,
scrolling the viewport only when selection leaves the visible rows. A synthetic
100-row dialog reproduced seven wheel events before visible scrolling, in both
chess and draughts. These events completed in 0–1 ms: this is cursor navigation,
not a timed pause. Native mwGrid scrolls the viewport on the first event while
retaining selection. Set only FParamsGrid.MouseWheelOption := mwGrid.

The regression uses the native DoMouseWheel path, without launching engines or
reading/writing local engine configurations. Check the first notch in each
direction, selection/value/column width preservation and top/bottom boundaries.
The independent source snapshot excludes unfinished feature flags, user AGENTS.md
edits and Test.pgn. No game, protocol, process or persistence code is changed.

Validation: the regression fails on the committed baseline and passes after the
one-line change (18 checks across both games). Application compilation and all
fifteen GUI suites, including mixed-game and resizing checks, pass on the isolated
source snapshot. Native Windows interaction remains untested.

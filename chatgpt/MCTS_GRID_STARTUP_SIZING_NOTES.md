# MCTS grid startup sizing — 2026-11-02

## Authorisation

The user reported: “the MCTS grid is not shown in full at startup, that used to
be the case.” For the named shared GUI fix, the user chose:

> Apply now; waive prior review

Scope: fit all eight measured statistics rows and reserve the required analysis
panel height for both games. Claude can review the resulting commit afterwards.

## Cause and correction

The constructor sizes the existing grid for eight 13-pixel rows. The shared
layout pass then increases DefaultRowHeight to fit the active grid font and
margins, but the old grid height remains. The startup regression demonstrates
136 pixels of row content in a 104-pixel viewport.

In the existing main-form analysis sizing method, set the grid height from its
actual GridHeight plus native edge space, after the shared font measurement.
Include that height when setting the analysis panel's minimum. Keep the grid,
its row labels, columns, font, scroll policy and engine updates. No shared layout
helper, game, engine or tournament behavior changes. Both chess and draughts
show the complete statistics table in the existing location.

## Verification

Extend the existing main-window readability check. At initial startup, after
switching games, and at normal/enlarged fonts and small/large window sizes,
assert eight retained rows, an unscrolled full-height viewport and no clipping
by any ancestor panel. Preserve its existing FEN, notation and laptop-height
checks. The new regression fails before the fix; afterwards the focused suite
passes 125 assertions with zero reported leaks.

Application, all 20 GUI suites (including multi-game) and both tournament suite
results are recorded in CHANGELOG.md. All GUI execution uses isolated hidden
displays. Native Windows visual confirmation remains pending.

# Single-line SPRT status

2026-11-17 authorization: user approved the proposed running/finished/boundary
status lines with **“Please proceed!”**. This is within the live-pane scope
previously authorized with **“Implement now; waive prior review”**. The user then
said the exploratory/preconfigured hover descriptions were unclear and asked what
SPRT means for a finished event. Explain the replay of saved pairs using current
settings in plain language. The user subsequently requested “I would remove the
hover text.” Disable status hints and keep the statistical explanation in the
manual, including the requested early-stop versus full-match example.

## Presentation

Reuse the existing TSprtReport and tournament IsRunning state. An out-of-order
completed pair after the first missing pair selects the waiting description.
A complete selected comparison with no crossing is inconclusive even if the
wider event has other games; an idle comparison with missing results is incomplete.
Boundary descriptions show the actual H0/H1 Elo setting and consumed sample size.
The report's first crossing, pair ordering, likelihood, storage and CLI remain
unchanged.

One existing label replaces the old separate heading/paragraph. Its WordWrap is
false and height follows one measured text line. A small TLabel subclass delegates
to standard inherited text drawing with SINGLELINE/END_ELLIPSIS flags; the complete
caption stays intact but status hover hints are disabled. Provenance remains in
saved/CLI metadata; the manual explains it. Graph point hints remain unchanged.
No extra status banner.

For a finished event this is retrospective: replay the scheduled opening pairs
and ask whether/when the current test would have crossed a boundary. No crossing
with all pairs is inconclusive, not proof of equal strength. Nominal error targets
have the usual preplanned-test assumptions and GSPRT approximations.

## Validation

GTK2 application build, all 27 GUI suites (140 focused SPRT assertions), full
regression and both tournament checks passed. Both-game GUI fixtures cover
running progress, out-of-order
waiting, an idle incomplete event, a completed single-pair event, all 79 pairs
complete without a boundary, H0/H1 status and disabled status hover text. Reviewed one-line layout at normal/enlarged fonts; existing graph/value checks
pass.
Native Windows QA remains outstanding.

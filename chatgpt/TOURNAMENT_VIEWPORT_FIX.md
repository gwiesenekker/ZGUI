# Preserve visible tournament rows when Play starts a game

Date: 2026-10-31

User request: “QA: when you create a tournament using round-robin pairing and click play, the first row scrolls out of view?” This is a GUI-only correction within the earlier user authorisation: “As this is GUI only: could you implement automatic resizing of the GUI as discussed? You do not need approvals.” Scope is tournament selection/viewport presentation; no scheduling, result, engine or storage logic changes. Claude may review the resulting commit afterwards.

`HighlightRow` selected the started game's row and then unconditionally set TopRow to that row. Starting row two therefore removed row one even when both fit. Native LCL Row selection already scrolls only as far as necessary. Keep that selection and remove unconditional repositioning. If LCL ignores selecting the already-selected row after manual scrolling, check the actual cell bounds against the fixed header/client area and reveal it only if hidden or clipped.

Extended the existing all-grid scroll test with real Create pairing / Play / timer callbacks, using registered fake games and the existing main-form test registration hook. No engine processes are launched. Exercise eight combinations: chess/draughts × single/double round-robin × 10/16-point fonts. Check initial first-row visibility, a previously selected hidden/clipped first row, row-two selection without moving the viewport, a genuinely offscreen later start and preserving manual scrolling on an idle tick. Existing wheel/scrollbar/tooltip tests remain intact.

The baseline failed at “Selecting a visible round-robin row must not scroll row one away”. The corrected focused suite passes all 419 checks with no unfreed memory blocks. Final application/GUI/tournament validation is recorded below. Use an isolated source snapshot excluding unfinished feature flags and leave all user engines/files untouched.

Final validation passed: application compile, all eighteen GUI suites (419 scrolling/hover/Play checks and 9,148 layout checks), draughts tournament preservation and 101 chess tournament checks. The final suite leaves no unfreed test memory. No headless rules/protocol changes were made. Native Windows UI was not exercised.

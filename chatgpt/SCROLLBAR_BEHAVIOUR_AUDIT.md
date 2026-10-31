# Scrollbar behaviour audit — 2026-10-31

User authorisation: “QA: does the scrollbar in the Tournament event games list-view have the same issue as the engine parameter scroll-bar? If so, could we revisit the behaviour of all scroll-bars?” Scope: application scrollbar and wheel behaviour, continuing the explicitly authorised GUI-only work without prior review. Claude may review the resulting commits afterwards.

## Findings and change

The tournament games control is a TStringGrid, as are the tournament cross-table, engine list, PGN/PDN games list, database games/results lists, engine parameter editor and analysis statistics table. Only the parameter editor explicitly selected `mwGrid`. The other seven inherited `mwCursor`: wheel events first move selection, scrolling the viewport only when selection leaves view. This is a repeat of the reported parameter-wheel issue.

Set `MouseWheelOption := mwGrid` at creation of each remaining grid. Use native `goThumbTracking` on all eight grids so horizontal and vertical scrollbar dragging updates the viewport before mouse release. Preserve selection, editing, column sizing, click/double-click actions and keyboard navigation. There is no custom wheel handler or timer.

Reviewed the application's remaining scrolling surfaces: native TMemo text panes (analysis, PV, legal moves, logs, INI/output), TListBox/TCheckListBox (games, engines, choices), TSynEdit notation/manual, and TScrollBox settings/preferences pages. They have independent native/LCL wheel handling and do not use the grid's `mwCursor` policy. No custom application wheel interception was found. Keep their native behavior; no evidence justifies replacing it. SynEdit's partial-wheel accumulation and zoom modifiers are intentional separate behaviors. Preferences scroll boxes already enable horizontal and vertical tracking; the New Game scroll box already enables vertical tracking. Output/log panes intentionally follow new output, which is separate from wheel dispatch. Native input dispatch for these non-grid controls was reviewed in source, not exhaustively exercised on Windows.

Local primary source: `/usr/share/lazarus/4.8.0/lcl/grids.pas`: default MouseWheelOption (1280), native scrollbar messages (4949–5001), wheel dispatch (7608–7665), and viewport-only GridMouseWheel (11119 onwards). DefaultGridOptions does not include goThumbTracking.

## Validation

Extend the existing parameter-wheel suite to cover all eight actual grids for both games: first up/down event, unchanged selected cell/data/column widths, boundaries, scrollbar arrows/pages, horizontal wheel, horizontal/vertical live thumb tracking, and normal keyboard row navigation. Synthetic grid data only; no engine process, database import or tournament game is started. Use an isolated source snapshot excluding unfinished feature flags. All shared GUI suites and tournament preservation checks remain required. Native Windows interaction is not available here.

Final validation: application compile, all seventeen GUI suites (317 grid scrolling checks; 9,148 layout checks), draughts tournament preservation and all 101 chess tournament checks passed. No leftover test engines are required. Existing Hub/UCI/DXP behavior and wire fixtures are unchanged.

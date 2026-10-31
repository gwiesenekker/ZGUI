# Engine hints and current built-in manual — 2026-10-31

User authorisation:

- “QA: hovering over the engine path does not show a hint text on Windows.”
- “I think the manual is out of date BTW? Could you generate a new manual?”
- Requested format: “Built-in Help manual”.
- “For example UCI engines were missing in the manual.”
- “The manual currently only mentions 2-0, 1-1 and 0-2 for the tournament result.”

Scope: GUI-only hint repair and documentation refresh, continuing the previously authorised GUI fixes without prior approval. No engine, game, tournament or database functionality changes; Claude may review the resulting commits afterwards.

The engine list previously enabled only goTruncCellHints. That is conditional on LCL's clipping calculation, so a path that appears to fit does not receive a hint. Supply full data-cell hints explicitly through the native OnGetCellHint event and goCellHints. This includes the engine path regardless of column width, with no duplicate clipped-text hint. Headers/invalid cells return no hint. Retain native hint timing and scrollbar/selection behavior. Exact Windows widget behavior cannot be reproduced here.

The old manual was an inherited draughts manual preceded by an accumulated chess-port addendum. It did contain UCI text in that addendum, but UCI was absent from the engine chapter and several numbered chapters still described draughts-only defaults/menus as universal. Reorganise the existing material into a current manual: UCI/Hub/DXP subsections, both games and defaults, chess ending rules and pondering, game-specific tournament behavior, PGN/PDN, current setup/database/preferences, mandatory Hub init, DXP claim meanings, engine slot labels and paths outside the application directory. Preserve the detailed operational reference. Rebuild the embedded Help manual; no PDF requested.

Extend existing engine-table tests with full hover hints for clipped and fitting Windows-style paths, external locations, Unicode, row changes, empty cells and headers. Render the complete manual through the existing manual document tests and GUI Help/search checks; run the shared GUI suites for both games on an isolated snapshot excluding unfinished feature flags.

Validation notes: the old engine sizing test asserted goTruncCellHints instead of testing a hint; updated it to retrieve and compare the complete path. A subsequent full run had an unrelated transient U15 position-setup draft rejection failure; the unchanged setup suite passed on immediate isolated rerun (287 checks). No position-setup production code was changed. The final full sweep is recorded below.

Final validation passed: manual_document_check at its supported wrap widths, all seventeen GUI suites (Help/search, 9,148 layout checks, 331 scrolling/hint checks), and application compilation. The final full sequence passed without the transient setup assertion. Both games use the same engine-cell hint behavior. Native Windows hover timing remains untested; portable LCL event routing and Windows-style path text are covered. No tournament outcome/Reason-column logic changed.

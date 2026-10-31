# Tooltip audit after the Windows engine-path fix

Date: 2026-10-31

User feedback and request: “QA: hint text is now shown in Windows. Perhaps we can check if the fix is also needed everywhere else we show hints?”

Reviewed the application's tooltip producers. Board PV/hint-square highlighting is a separate feature and was excluded. Menu-item Hint strings used as engine identity keys must not be changed into tooltip captions.

| Surface | Current behavior | Same fix needed? |
|---|---|---|
| Engines grid | Explicit `goCellHints` / `OnGetCellHint`; complete data text regardless of clipping | Already fixed in 4553021; user confirms Windows display |
| Other application grids | No `goTruncCellHints` usage or existing conditional cell-tooltip policy | No existing tooltip producer with the same defect; do not add unsolicited hints to every table |
| Engine launch-argument edits | Nonempty explicit `.Hint`, `ShowHint=True`; UCI/Hub text updates with protocol | No |
| Engine INI path and editor | Explicit explanatory hint and `ShowHint=True` | No |
| Main analysis-seconds edit | Explicit “Annotator seconds” hint and `ShowHint=True` | No |
| Game-tree view | Explicit browsing/Escape help hint and `ShowHint=True` | No |
| PGN/PDN browser warnings | Hint is set to the full warning caption, `ShowHint=True` | No |
| Score history and popout | Shared control explicitly builds per-ply score/mate text, updates Hint and activates the native hint window | No |
| Disabled game-feature controls | Explicit “Not available for …” text; menu hints also carry internal metadata | No clipping policy; retain existing handling |

No other grid uses `goTruncCellHints`. No .lfm form files supply additional tooltip definitions; forms are constructed in code. Existing explicit hints do not depend on native truncated-text detection. The user confirmation verifies the actual Windows engine-path result; the audit is source-based and does not claim exhaustive native Windows testing of every remaining control.

No additional tooltip production code changes are justified by this audit. The existing GUI regression suite continues to cover both games, score history, file warnings and the explicit engine-cell hint cases.

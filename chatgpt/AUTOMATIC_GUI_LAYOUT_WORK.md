# Automatic GUI resizing

2026-10-30. User authorisation: “As this is GUI only: could you implement automatic
resizing of the GUI as discussed? You do not need approvals.”

Scope: presentation and geometry only, preserving the existing controls, handlers,
game/protocol/database behaviour and overall grouping. Use LCL panels, alignment,
ChildSizing, preferred sizes, text measurement, wrapping and scrollable pages.
The exception in AGENTS.md applies to this named GUI work; Claude can review the
resulting commit afterwards.

Targets: main toolbar and White/Black/Result/FEN header, engine editor/registry,
New Game, Tournament, Preferences, Database filters, position setup and supporting
manual/file-picker/score-history windows. Font-aware row and minimum sizes,
resizable viewports and scrollable long settings replace fragile absolute bounds.

The in-progress engine feature flags, INI reset proposal, user engine directories,
AGENTS.md edits and Test.pgn are excluded from this commit. No subagents are used.

Validation in progress: self-contained layout checks at minimum, normal and large
sizes with normal/enlarged fonts, including every preferences page and both games.
Run the full GUI suite and compile the application before committing. Native
Windows/DPI behaviour will be identified separately from verified GTK2 checks.

The reported gui_layout_check popup was a DPI layout loop. The fix refreshes
measurements inside DoAutoAdjustLayout before LCL resumes alignment. Regression
exceptions are logged via Application.OnException; development runs are bounded.
An additional tournament wrapping case required explicitly growing an already
shown form after its minimum constraint increases.

The database GUI test's old exact-coordinate comparison now checks shared control
types/grouping instead: wrapping intentionally changes row geometry at different
window widths. Its functional database and measured FEN-width checks are retained.

Final validation: isolated layout-only application compilation, all thirteen GUI
suites (87 mixed-game checks and 8,944 layout checks), and the complete headless
regression suite pass. Normal/enlarged/restored fonts, minimum/normal/large/actual
maximized windows, all preferences pages and 96->144->96 LCL DPI scaling are covered.
Native Windows interaction and actual monitor DPI transitions remain untested.
Unfinished engine feature flags and the separate DXP readiness work were excluded.

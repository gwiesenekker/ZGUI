# Tournament game chooser beside the starting FEN

Date: 2026-11-01
Status: implemented and verified on 2026-11-01.

User request: “QA: could we move the chess/draughts chooser next to the FEN in the
Tournament dialog box?”

User authorisation: “Apply the layout change now; waive prior review”, in direct
response to the question naming this layout change. This covers only the shared
presentation change; Claude reviews the resulting commit afterwards.

## Change

Move the existing TournamentVariant combo into the same measured row as the
existing TournamentStartingFEN edit, to its right. Reuse LayoutRow/LayoutFields;
keep the tournament name above and the clock/pairing/actions below. Remove the
combo's old row under Concurrent games. A single registered game retains the
original no-chooser layout.

Keep the FEN's existing full-text/sample-plus-margin minimum. Measure all chooser
items with its current font, add native-arrow/text margin and fix that control to
the measured width; remaining row width belongs to the FEN. Include both controls
in the settings panel's measured minimum width. No hard-coded chooser width,
changes to settings, game-switch callbacks, tab replacement, pairing, clocks or
engine behavior.

## Verification

Extend gui_layout_check to assert the two controls share a parent, the chooser
is to the right, their vertical alignment matches, full FEN remains visible and
the settings row spans the dialog. Exercise both games, minimum/default/large/
maximised windows, font changes, long FEN text and DPI adjustment. Inspect hidden-
display captures. Retain existing tournament-tabs native event and same-tab
switch/defaults checks; run both tournament suites and the full GUI sweep.

## Verification results — 2026-11-01

- Final GTK2 application compilation passed.
- Full headless regression sweep passed, including both games' rules, engine
  lifecycle/clocks/pondering, database, source/build identity and manual checks.
- Final full GUI sweep: all 19 suites passed on hidden displays, including
  multi-game (173), UCI GUI/Auto Play (128), measured layout (9762), engine-end
  reasons (266) and tournament tabs (200). Multi-game and layout tests report
  zero unfreed memory blocks.
- Both chess and draughts tournament suites passed again with the relocated
  chooser (chess: 101 checks). Focused tournament layout/capture checks passed
  976 assertions with no failures; initial and resized captures inspected.
- Staged Pascal sources/tests matched the isolated tested source snapshot.
  Excluded unrelated unfinished engine-feature changes and left engine
  directories and user PGN files untouched. Native Windows QA remains pending.

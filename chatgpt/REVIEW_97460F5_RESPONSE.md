# Response to Claude's review of 97460f5 — 2026-10-31

Implementation: `9606f3b`.

Reviewed `claude/review-97460f5.md` and its referenced findings in
`claude/review-16ba377.md` against current baseline `09a6948`.

The user requested: “Could you address all these findings?” (2026-10-31).
Scope: A2, U25, C7 (including the GUI runner), T6, F5, U24 and U23, as listed
in the preceding response. These implement Claude's review recommendations;
no replacement game, tournament, clock, engine, notation or database machinery.
The unrelated unfinished feature-flag work and user files remain excluded.

## Findings

- **A2:** `TPvBrowser.AttachViews` reconstructs memo text/offsets from its own
  variation, restores its information label and selection, and redraws its board.
  It keeps the frozen browse position, invalid tail and pending update; it does
  not apply pending data on a game switch. Escape still applies that data.
- **U25:** setup palette height sums native radio-button preferred heights and
  measured group caption plus padding. Palette width also accommodates the
  native buttons. Tests explicitly check nonoverlap and preferred heights,
  as well as bounds, fonts, window sizes and DPI, for both games.
- **C7:** scroll each swatch fully into its containing scroll viewport before
  capturing pixels. Test at the dialog's minimum height and assert the swatch
  is actually inside that viewport. Keep the colour-pixel assertions.
  The GUI runner records build/run failures and continues through all suites,
  reporting every failure and returning failure if any suite failed.
- **T6:** explicitly destroy the hidden contexts' tournament, database, setup,
  position-setup and popout forms before freeing shared model/display state
  and the games list. Keep the existing stop/join order for workers. Clear the
  games-list reference on destruction. A destruction-notification observer
  verifies both contexts' setup/tournament dialogs can query the live list.
- **F5:** remove the running tree's display entry when its game is removed.
  For a selected game, switch to the next document first; on shutdown clear
  the active display pointer if it is being released. Twenty alternating
  chess/draughts selected/hidden removals keep the display count bounded and
  preserve both standalone documents.
- **U24:** resolve an empty Event using the standalone tree's owning context,
  taking the current fields for the active context. Unnamed running games use
  `?`, rather than borrowing a standalone board's name. Exercise real close
  prompts and saved PGN/PDN with each game as the hidden document in turn.
- **U23:** clear the annotator memo after assigning its component name, before
  adding its initial status. Test initial text and a round trip between games.

## Status corrections and scope

Claude's review already confirms T5/C6/U22 fixed. `claude/PORT_STATUS.md` still
points at 16ba377 and lists those findings as open; this response supplies the
current correction without editing Claude's own review/status files.
The later mandatory Hub `init` implementation (2b6afa2) supersedes the optional
initialization behaviour reviewed at 97460f5 and remains unchanged.

D6 (options per executable), U21 (delete-from-here proposal), and documented
T3/D7 are outside the seven findings requested in this follow-up and remain
open/documented. Optional follow-new-games and colour-row alignment suggestions
are not part of these correctness fixes.

## Validation

Application compilation, full headless regression, all eighteen GUI suites,
and both tournament suites pass on an isolated tracked-source snapshot plus
only these changes. The mixed suite passes 140 checks; Inter-font layout
passes 9,460; colour/init passes 476; chess tournaments pass 101. Checked GUI
builds report no unfreed blocks. A final layout rerun covers the construction-
time nil guard added after the sweep.

The old PV AttachViews implementation fails the new A2 assertion. Disabling
preview scrolling fails the new viewport assertion at minimum dialog height.
The runner harness injects one build failure and one run failure: all eighteen
suites are attempted, sixteen pass, both failures are reported, and exit is 1.

Logs: `/tmp/zgui-review-followup-{gui,regression,tournaments,app}.log`,
`/tmp/zgui-review-followup-layout-final.log`,
`/tmp/zgui-review-pv-baseline.log`, `/tmp/zgui-review-colour-baseline.log`,
and `/tmp/zgui-gui-runner-probe-bma5orbb/result.log`.
Native Windows interaction is not available in this environment.

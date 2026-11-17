# Loaded SPRT comparison refresh

Implementation commit: `8bc7286`.

2026-11-17 QA: both visible engine selections were present after loading, while
the pane still said Comparison unavailable / Select a candidate and baseline.
This correction stays within the existing live-SPRT authorization on 2026-11-17:
**“Implement now; waive prior review”** for the shared live pane, engine selection
and calculation, for chess and draughts. No game/clock/engine execution changes.

## Causes and correction

LoadTournamentFromFile calls UpdateCrossTable while FLoadingTournament is true,
so RefreshSprt deliberately skips it. The final load path did not refresh after
releasing the guard. Reset had the same stale-presentation gap. Refresh explicitly
after releasing the guard in both operations.

TSprtPanel.SetParticipants also returned immediately for unchanged names/keys.
After SetConfig resets missing legacy metadata to defaults, this shortcut skipped
initializing the two-engine defaults and reconciling the combo selections. Skip
only rebuilding unchanged lists; always reconcile config and selection under the
existing event guard. Automatic defaults remain unstored/exploratory.

## Validation

The dedicated GUI suite passes 118 assertions on a hidden display. Test the pane's
public report directly after load, before any SprtSnapshot/CLI query can hide the
bug. Both games cover fresh saved-design load and expansion, reset/reload, initial
and repeated two-engine legacy loads without sprt_view, synchronized selection
keys, correct paired draw evidence, exploratory labels and unchanged file bytes.
GTK2 application build, all 27 GUI suites, full regression and both tournament
suites pass. Also process native GUI events before checking that automatic legacy
selection stays exploratory. Native Windows QA remains outstanding.

# Terminal-position safeguard for time-forfeit adjudication

Implementation commit: `066fb47`.

2026-11-17 authorization, in the user's words:

> Please implement the terminal-position safeguard and Adjudicator wording, keeping symmetric adjudication. Prior review waived. Please update CHANGELOG.md, compile, test, and commit.

Scope: the terminal-position part of T18 and clearer adjudicator reason wording.
The proposed cap at a draw is deliberately not applied: the user explicitly
requires keeping symmetric evaluation adjudication.

## Reuse

Inside the existing optional time-forfeit callback branch,
`TGameOrchestrator.FinishOnTimeout` calls its existing `CheckOutcomeAfterMove`
method before requesting analysis. That delegates to the existing game's
`TGameRules.Outcome`; if it finishes the game, return with that result and reason.
No second rules implementation, engine launch path, GUI controls or interfaces.
The no-adjudicator branch still uses `TimeoutOutcome` as before.

This protects already-terminal wins and rules-declared draws, including chess
checkmate, stalemate and insufficient-material/75-move draws, and draughts
no-legal-move endings. Nonterminal positions retain symmetric +/-threshold
adjudication: either side may win even if its own clock expired. This change
does not add a timeout-only insufficient-material exception to that selected
analysis policy; that would be a separate policy change.

Use “Adjudicator <name> evaluation …” in generated reasons. Update the existing
tournament reason formatter to recognize the new prefix without adding
“Orchestrator:”; retain recognition of old “Annotator” records. Update matching manual
examples and document terminal precedence plus the symmetric policy.

## Verification

Focused tests exercise both colours of checkmate and stalemate, both sides to
move in king-versus-king, a 75-move draw, and both draughts terminal outcomes.
They supply the pending final position at the public position boundary and
expire the current-turn clock, count callback invocations, and force a failed
engine launch to prove that terminal results do not depend on analysis.
Black-to-move timeout cases complement existing White-to-move checks for both
games, covering positive/negative thresholds, draws and mate evaluations.

Focused unit checks: 127 assertions passed. Compiling the same new tests against
the previous orchestrator (with the current reason wording) fails on the first
checkmate safeguard assertion, confirming regression coverage.

GTK2 application build, full regression and both tournament checks passed. The
full GUI run passed 26 suites and exposed the old “Annotator” assertion in the
time-forfeit GUI test. Updating that assertion then exposed the reason formatter
adding “Orchestrator:” to the new prefix. After updating prefix recognition,
the time-forfeit GUI suite passed all 464 assertions. The separate engine-end
reason GUI suite was also rebuilt/rerun and passed. All 27 GUI suites are thus
verified, including multi_game_gui_check. Tests ran only on the hidden display.
Native Windows execution remains outstanding.

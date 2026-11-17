# Time forfeit adjudication

Implementation commit: `1dd5baf`.

2026-11-17 authorization: the user answered **“Implement now; waive prior review”**
for the named shared change: rules-based default; optional Hub adjudicator for
draughts/UCI for chess; 1.0-second analysis, configurable positive cp threshold,
draw inside +/-threshold; explicit saved reasons and CLI policy; failed/unavailable
analysis remains * for referee attention. User naming refinements:
- “Lets call the option 'Time forfeit' and the argument time_forfeit”
- “Lets call the time and evaluation threshold adjudication_time and adjudication_threshold.”

## Reuse and behavior

The orchestrator retains its existing rules-based timeout outcome by default.
An optional runner callback handles only actual timeout paths, not crashes or
ordinary game endings. It pauses clock projection using the existing waiting
state, stops both players with existing adapters and uses CreateGameEngine plus
the finite StartThinking path to analyze the unmodified final position. Shutdown,
handshake, cancellation, output parsing and score perspective remain in the existing
Hub/UCI adapters. No new process manager, scheduler, game tree or tournament runner.

The setup carries cloned adjudicator definitions through existing running-game
and replay lifetimes. The same existing reservation keys/oldest-waiting queue
cover it for the whole game. This intentionally conservative reservation may limit
concurrency when a single adjudicator serves several games. Selecting a playing
engine is safe: both player processes shut down before a fresh adjudicator starts.
No adjudicator move/PV is added to the game tree. Engine-count remains the match's
conservative two-engine reservation indication through this final stage.

Hub/UCI scores are already normalized to White perspective by their adapters.
Convert pawn scores to cp, compare to +/-threshold with inclusive win boundaries,
and draw inside the band. Signed nonzero mate values map to the corresponding
winning side. Missing, ambiguous, bounded-only UCI, invalid or failed searches do
not become draws: keep * with an explicit failure reason. Include adjudicator name,
evaluation comparison and original timeout cause in the existing result reason.

GUI: an aligned measured row between time controls and Play; Orchestrator default,
protocol-filtered engine picker, enabled analysis edits only for an engine policy.
Settings changes use existing Apply/Revert invalidation and are disabled while
running. CLI binds the same settings/runner with time_forfeit, adjudication_time,
adjudication_threshold and existing-style _id/_key disambiguation.

Nondefault policies require guarded storage_version=5 so old binaries refuse to
load them rather than silently change adjudication. Older ordinary/ballot files
still use their existing versions and default rules. The version-5 time_forfeit
object itself has version 1 with engine_key/name, seconds and threshold_cp.
Invalid metadata is rejected before replacing the current event. Missing engine
registrations remain visible/unstartable instead of falling back to time loss.

## Associated user QA refinements

The user requested “SPRT settings” instead of the ambiguous “Test settings”, a
readable status instead of the log-like pipe-separated block, graph markers and
hover values like score history, and estimated Elo in those hints. Reuse the
score-history hint activation pattern. Each trace point carries its empirical
prefix mean score, giving logistic Elo = 400 log10(score/(1-score)); endpoint
estimates are explicitly infinite. Hover identifies the scheduled opening, LLR,
estimated Elo and first crossing. Unchanged reports retain their hover cache.
These remain within the live-pane scope waived on 2026-11-17.

## Validation

GTK2 application/test builds, full regression and both tournament suites pass.
All 26 GUI suites pass, including focused reruns of the final tab-sizing and
native close-automation fixes. The new row exposed native notebook tab-strip
insets omitted from host minimums: measure from the realized active page, notify
the host when measured child minimums change, and guard nested measurement.
Focused presentation passes 241 assertions; complete tabs pass 411. Pipe checks
pass 107, mathematical/protocol checks 29/68/22. Normal and enlarged-font live
pane checks pass, with point/LLR/Elo hint assertions. The final combined run with saved-tournament-history support passes all 27
GUI suites (415 tab, 107 pipe/application and 88 live-pane assertions).
Dedicated coverage includes threshold equality and both
signs, mate scores, absent evaluations, failed launch/search, cancellation, final
position preservation, GUI/CLI policy equivalence, save/reload, reservations and
normal default timeouts for both games. Real child-process Hub/UCI tests exercise
White/Black score normalization, restarting a playing engine as adjudicator and
cancelling active adjudication. Native Windows execution remains outstanding.

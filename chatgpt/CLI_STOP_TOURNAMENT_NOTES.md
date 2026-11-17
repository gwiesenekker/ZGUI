# Interactive stop_tournament

Date: 2026-11-17.

## Authorization

The user requested: “BTW, we should add a 'stop_tournament' command to the CLI.”
For the explicitly named shared scope, the user selected: “Implement now; waive prior review”. Scope: reuse the GUI Stop action for both games, preserve the tab/results, and allow query_tournament to report shutdown progress. No separate scheduler, engine lifecycle or stop implementation.

## Implementation

- Extract the existing RefereeStopClick body into public StopTournament; the GUI handler delegates to it unchanged.
- Accept stop_tournament with required id through the existing binder and GUI-thread dispatcher. Share tab/event validation with query_tournament. Unknown/closed IDs return UNKNOWN_TOURNAMENT; replaced events return TOURNAMENT_REPLACED; modal operations still return BUSY.
- Return an acknowledgement with command and tournament. Stop is asynchronous and idempotent; query reports the existing state and counts. A stop requires the same event identity, but does not demand the unchanged two-engine pairing shape required for match statistics.
- Existing Stop preserves completed results, marks interrupted active games Referee stopped tournament with unresolved result, withdraws queued work and retains the tab and files. Other tournaments continue.
- Update built-in CLI help, manual reference and Windows checklist.

## Validation

- GTK2 application build passed.
- Focused CLI GUI checks passed: 133 assertions for both games, repeated Stop, results/files, invalid/closed/replaced IDs and modal BUSY.
- Pipe checks passed in the harness and actual executable. Full-run integrated checks report 93 assertions, including queued Stop, stopping chess while draughts continues, referee reasons, retained tabs and normal shutdown.
- Full regression passed, including all 20 terminal transport checks and manual rendering. Both tournament suites passed (101 chess assertions plus draughts preservation); lifecycle and local TCP DXP checks passed.
- Full GUI suite passed: 24/24, including multi_game_gui_check and tournament_tabs_check. GUI runs used hidden displays only.
- Native Windows QA remains outstanding under the existing waiver. The checklist now includes the new Stop command.

## Commit

Pending.

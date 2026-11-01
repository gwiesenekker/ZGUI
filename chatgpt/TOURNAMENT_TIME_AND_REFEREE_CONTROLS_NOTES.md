# Tournament time controls and referee actions

## Authorisation — 2026-11-01

The user chose: “Apply the tournament update now; waive prior review”.
The named scope was one-line time controls with minutes/seconds, a separate
Play / concurrency / Stop row, and a specific reason for stopped games.
Subsequent user corrections within this work:

- “can we put Chess/Draughts TO THE LEFT of the FEN string?”
- “perhaps we should disable Save... while games are running?” and “..and Load.. as well”.
- “Use Referee for tournament actions”.
- “‘Referee declared win/loss/draw’ is more generic and does not depend on chess/draughts”.

The user also requested documenting loading behaviour and all tournament reason
families, and confirmed engine failures should keep `*` for referee adjudication.
Claude reviews the resulting commit afterwards.

## Implementation

Reuse the existing tournament controls, clock validation, game runners, stop
requests, records, scheduler and file reader/writer. No replacement infrastructure.

The time row contains moves, quantity, minutes/seconds (minutes by default),
increment and its existing mode. Save canonical minutes plus an optional display
unit. Older files retain their actual duration and default to minutes. Unit edits
participate in the existing accepted-settings / Revert protection. Reject invalid
saved units before changing the dialog.

The following row contains Play, concurrent games, Stop, Save and Load. Play starts
scheduling; Stop cancels active games and scheduling. Incomplete games retain `*`
and “Referee stopped tournament”. Finished games and genuine errors retain their
own result/reason. Prevent restart/repeated Stop while shutdown drains. Disable
Save/Load while that tab is running or stopping; automatic persistence and other
tabs continue through their existing paths. Move the game chooser left of FEN.

A focused test exposed Stop during engine initialization becoming a false launch
or unsynchronized-session error. The minimal runner correction skips subsequent
launches and new-game commands to cancelled sessions, retains the configured root
and clocks through the existing NewGame path, and marks nonterminal cancelled
snapshots stopped. Real runner failures and terminal outcomes retain precedence.
This also corrects early Stop in ordinary chess and draughts games; it does not
change engine protocols or crash/forfeit policy.

Referee declarations use “Referee declared win for White”, “Referee declared win
for Black”, and “Referee declared draw” for both games. Preserve the original
engine/rule cause; replace only the previous declaration. Clearing an override
restores the played result/reason. Recognize older “Operator set result to …”
suffixes when loading and editing. Engine crashes remain `*`, with diagnostics.

## Verification

Use an isolated archive of the baseline plus only this task's files; exclude the
user's unrelated unfinished engine-feature work. All GUI execution uses separate
hidden displays and isolated configuration, never the user's main display.

Focused tests cover both games' row placement, unit persistence and legacy files,
invalid-unit rejection, accepted-setting Revert, Play/Stop and Save/Load states,
startup cancellation, stop persistence and referee declaration compatibility.
Run the full headless regression, all 19 GUI suites, both tournament suites and
application build. Native Windows verification remains for the user's environment.
No adjudication rules change; the previously recorded FMJD long-diagonal rule
follow-up remains outside this scope.

Final verification: application compilation, the complete headless regression,
all 19 GUI suites and both tournament suites pass. Layout: 9,730 checks; reason
persistence/declarations: 290; tournament tabs: 267; focused Stop: 73; chess
tournament (including explicit init-stop reason and crash diagnostic): 101.
Reported heap checks show zero leaks. Test snapshot sources match the staged
implementation. Native Windows QA is outstanding.

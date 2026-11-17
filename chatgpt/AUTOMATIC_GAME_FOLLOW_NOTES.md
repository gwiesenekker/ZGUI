# Conditional automatic game following

Date: 2026-11-17.

## Authorization and clarification

The user requested: “Can we automatically follow a new game that is posted. If the selected game is NOT the last game in the list you stay on that game. If the selected game is the last game AND the game has finished AND the selected move is the last move in the game select the new game.”

For the named shared scope, the user selected: “Implement now; waive prior review”. Scope: newly posted background games in both games, preserving explicit New Game selection behavior.

The user clarified that the final-move condition can mean not browsing/clicking, then corrected the target: “I meant 'clicked in the move list'.” Use existing live-follow cursor state. A clicked/pinned move pauses automatic switching, including a clicked final move; returning to live-follow via the existing Escape action restores eligibility. This refinement is within the authorized follow rule.

## Implementation

- Add one GUI-only eligibility predicate in the main form: selected item is the current list tail; it is a displayed running-game object whose lifecycle is fully finished; its document is active; the existing cursor is Following and no main-board PV preview is active.
- Evaluate before appending the new row. Combine with the existing explicit ASelectGame flag, then use the unchanged foreground-selection block in StartGameFromSetup. No second selection path, cursor model, runner, scheduler or game-tree update is introduced.
- Do not switch away from earlier game selections, standalone boards, clicked moves (including the final mainline move), variations, previews, ongoing games or stopping games. Fully finished zero-move games are eligible in live-follow mode.
- Follow across chess/draughts and tournament tabs when the conditions hold. Existing explicit New Game/replay selection remains unchanged.
- Add a test-only displayed-position property alongside the existing GUI test seams. Extend multi_game_gui_check with both-game selection/browsing cases, Escape resumption, explicit selection, cross-game boards and incoming live moves.
- Update the built-in manual's unconditional background-selection wording to state the new rule. This is an intentional visible change for both games; GUI layout is unchanged.

## Validation

- GTK2 application build passed.
- Targeted multi_game_gui_check passed: 301 assertions, including 26 new both-game cases for last/earlier game, running/stopping/finished lifecycle, earlier/final clicked move, branch/PV, Escape resumption, standalone view, zero-move finished game, explicit selection and cross-game following. Incoming live moves update the automatically selected board; old trees and paused cursors/previews remain unchanged.
- Full regression and both tournament suites passed (101 chess tournament assertions plus draughts preservation).
- Full GUI suite passed: 24/24, including the 301-assertion multi-game suite, CLI application checks, tournament tabs and layout checks. GUI checks used hidden nested displays only.
- The first targeted fixture run exposed cleanup of a runner-less stopping fixture; fixtures now mark their lifecycle finished before teardown. Production lifecycle/stop logic is unchanged.
- Native Windows execution was not performed.

## Commit

Implementation: `06438c2`.

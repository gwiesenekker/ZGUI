# Preserve DXP termination reasons in tournament rows

Date: 2026-10-31
Status: implementation authorised.

User waiver on 2026-10-31: “Implement this fix; waive prior review”. This covers the separate DXP termination-reason metadata path described below; Claude can review the resulting commit afterwards.

## Requested behavior

User: “But the reason that the result is '*' is because the game ended due to a draw claim.” Then: “Could you fix that?”

For a DXP `E20` message, retain result `*` under the current adjudication policy, but show **Draw claimed** in the tournament Reason column. Result and termination reason are separate. Do not turn a peer claim into an official draw or win.

## Why this requires shared changes

`TDxpEngine` currently records the peer's reason only in its log. `TGameEngine` exposes a result but no separate termination reason. When no move is returned, the orchestrator ends the game; its finish reason is logged rather than exposed through snapshots. The tournament then chooses generic labels from the final result/state. The information cannot reach the row through an existing typed field.

AGENTS.md requires a proposal and prior approval for necessary shared functionality changes. The earlier waiver for GUI sizing does not cover adding fields to the shared engine, orchestrator and game snapshot interfaces. No production source changes had been made when this proposal was presented. Implementation started only after the explicit waiver above. Do not parse log text in the GUI or misclassify a draw claim as an exception merely to bypass that boundary.

## Minimal implementation

1. **uEngineBase.pas**: add a read-only, lock-protected `GameEndReason` string next to `GameResult`. Extend protected `SetGameResult` with an optional reason argument, default empty, so all existing calls remain valid and also clear stale reason text during their existing resets. Set result/reason under the same result lock. Existing Hub/UCI callers publish no reason and keep their behavior.
2. **uDraughtsDxpEngine.pas**: translate the received GAMEEND reason in the adapter and publish it with the existing translated result. Suggested labels: `0` = **Engine ended game**; `1` = **Resigned**; `2` = **Draw claimed**; `3` = **Win claimed**. Preserve unknown codes as **Engine ended game (DXP reason X)**, without assigning an official result. Stop-code acknowledgement and result translation remain unchanged. Keep the raw packet/code in the log.
3. **uGameOrchestrator.pas**: retain an optional protocol-neutral `EngineEndReason` when an engine returns no move. Use it as the logged finish reason when supplied. Reset on NewGame. Preserve current timeout/stop/error precedence and all result decisions. No DXP-specific code or engine type checks in this unit.
4. **uGameRunnerThread.pas**: include the scalar reason in full snapshots, copying and terminal delivery. Preserve existing live-update/queue rules. Clear it for a new game; do not replace an already terminal reason during shutdown. It is not an error and must not be stored in LastError.
5. **uRunningGame.pas**: expose the snapshot's reason through a read-only accessor, without changing game-tree structure or annotations.
6. **uTournamentDialog.pas**: retain actual error-message precedence, then use the engine termination reason if supplied; otherwise keep existing Unknown result / Draw / Game finished behavior. The existing JSON row `reason` persistence automatically saves and reloads the new text. No tournament storage/schema change, scheduling change or layout change.
7. **MANUAL.md / CHANGELOG.md**: describe the separate result and reason, remove the statement that peer claims are visible only in logs, and record the implementation commit.

Only engines publishing a reason gain different row text. Chess/UCI and Hub continue through the unchanged fallback. The DXP log, packet acknowledgements, official results and game clocks remain unchanged.

## Validation

- Fake DXP peers send reasons 0, 1, 2, 3 and an unknown code; assert labels, existing result translation and acknowledgements, for both sides where relevant.
- A draw/win claim retains `*` and ends without inventing a move or raising a protocol error. Resignation retains its existing losing result.
- New search/game resets cannot reuse an earlier reason. Process shutdown cannot erase the captured terminal reason.
- Check snapshot copying and terminal delivery without changing live-update behavior.
- Tournament regression receives `*` plus Draw claimed, saves/reloads that reason, and preserves any manual-result override and error precedence.
- Non-DXP empty moves and ordinary chess/Hub results keep their previous labels and result policies.
- Run application compile, headless regressions, DXP/lifecycle/tournament suites, and tests/run_gui_checks.sh for chess and draughts.
- Work and test against an isolated source snapshot; preserve unrelated unfinished engine-feature-flag changes and all local engines/user files.

## Implemented and verified

Implemented the field path above after the explicit user waiver. Existing result-reset calls clear the reason via the optional setter argument. Shared units contain no DXP code mappings. Actual errors and manual overrides retain precedence; saved row text persists through the existing tournament JSON.

Validation passed on an isolated source snapshot: local TCP DXP peers (including unknown code 9 and claims from both sides), 114 end-to-end reason checks, all eighteen GUI suites, both tournament preservation suites, the full headless regression sweep including lifecycle/snapshot coverage, source audit and application compilation. No local engines/user files or unfinished feature-flag work were included. Native Windows UI was not exercised. Existing completed rows with no stored reason are not reconstructed from log text.

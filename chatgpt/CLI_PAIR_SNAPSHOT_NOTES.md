# Optional CLI opening-pair snapshots

Date: 2026-11-17.

## Authorization and scope

The user requested: “Could you add the 'pairs=true' option? I am wandering if we should assume 1/2 3/4 are paired or that you should first sort the games by opening FEN?”

For the named shared scope the user selected: “Implement now; waive prior review”. Scope: reuse MatchSnapshot for both games, return every scheduled pair in order with its opening FEN, game numbers and engine1 scores (1/0.5/0/null), leave default query responses unchanged, and keep SPRT in the external runner.

## Design

- Add optional pairs=true/false to query_tournament only, with false as default. Other commands still reject it. Existing id/modal/event validation is unchanged.
- Extend existing MatchSnapshot with an optional IncludePairs argument, default false. Reuse its single pass, format-aware effective results and opening membership validation; no separate aggregation or scheduling path.
- Return pairs=[{pair,fen,games,results},...]. Pair numbers are one-based saved opening occurrence numbers. Games/results are corresponding two-element arrays in stored scheduled row order. Win=1, draw=0.5, loss=0 from engine1's perspective, identical for both games; null means no known effective result.
- Use saved opening round/occurrence, validate the common FEN and opposite colours, and preserve repeated FENs as distinct pairs. The generator currently schedules 1/2,3/4, but the endpoint does not infer membership from adjacency or sort by FEN. No-ballot double round-robin has one pair.
- All pairs are returned, independent of finish order. The runner consumes the contiguous completed prefix and owns SPRT/decision accounting. Referee edits and rescheduling appear in subsequent full snapshots; archived attempts are excluded. No frozen statistical sample is stored in ZGUI.
- Reuse persisted tournament data, without a schema change or a second pair-result cache. Reloading the same saved event reconstructs the response. Existing session ID lifetime remains; cold-start binding/reconnect is outside this change.
- FEN output uses the existing stored opening spelling (ballots are normalized on load), without reparsing positions on each poll.
- No GUI layout changes for chess or draughts. Extend built-in manual and Windows QA checklist.

## Validation

- GTK2 application build passed.
- Focused CLI GUI check passed: 239 assertions. Both games cover normalized engine1 W/D/L scores, explicit nulls, 13 repeated FEN entries, equal aggregate WDL with different pair evidence, non-adjacent games with explicit opening membership, later pairs complete while the first is incomplete, referee edits, rescheduling and saved-event reloads.
- Default and pairs=false responses compare identically. Detailed queries leave the saved tournament bytes unchanged; invalid pairs values and parameters on other commands are rejected.
- Integrated pipe check passed (105 assertions in the full run), including the actual executable with a synthetic 79-entry ballot containing repeated FENs, all pairs in scheduled order and one complete JSON response. Fake UCI/Hub peers are used; no engine directory is modified.
- Full GUI run passed: 24/24 suites, including multi_game_gui_check and tournament_tabs_check, on hidden displays only.
- Full regression passed, including manual rendering and 20 terminal transport checks. Both tournament suites passed (101 chess assertions plus draughts preservation).
- Native Windows execution remains outstanding; the checklist includes pairs=true.

## Commit

Pending.

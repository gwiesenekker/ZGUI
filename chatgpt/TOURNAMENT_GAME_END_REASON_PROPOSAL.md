# Preserve rule and clock termination reasons in tournament rows

Date: 2026-10-31
Status: proposed; no production changes made.

## User report and requested behavior

“In a drauhts tournament it seems that GWD lost on time, but the result is 0-2
and the Reason is only 'Game finished'. Can we specify a clearer reason such
as 'Draw by repetition' etc.”

Additional user requirements:
- “We should mention the engine name, so not 'Draw claimed' but 'X claimed draw'.”
- “Lets also log the reason code then next to trying to interpret it.”
- A game with 75 configured moves ended at move 75 with “Engine ended game”;
  the user needs to know which engine signalled the end.

Keep the actual result and show the already determined cause. Draughts 0-2 means
Black won, without specifying why; it is consistent with White losing on time.
Do not assume the reported game was a timeout without its actual log/state.

## Findings

- TGameRules.Outcome already returns cause text for both games. Draughts includes
  no legal move, repetition, the 25-move rule and endgame limits. Chess includes
  checkmate, stalemate, insufficient material, repetition and move-count rules.
- TGameOrchestrator.FinishOnTimeout already delegates the result to TimeoutOutcome.
  The reason identifies the expired side and, where applicable, the special chess
  timeout-draw condition. All FinishGame calls already receive a reason, but only
  log it; GameResult is the scalar metadata retained for all outcomes.
- The earlier DXP fix separately retains EngineEndReason through orchestrator,
  snapshot and running game. That field intentionally describes a protocol-supplied
  reason, not every rule/clock finish. Its waiver and proposal explicitly retained
  generic fallbacks for ordinary Hub/UCI results.
- ApplyTournamentGameResultToRow uses real errors, then EngineEndReasonText, then
  generic labels based on result. It therefore loses known clock/rule causes.

## Minimal implementation

1. **uEngineBase.pas / DXP adapter**: preserve the protocol reason code as optional
   typed metadata next to the existing GameEndReason, set under the existing
   result lock. Extend SetGameResult with an optional code argument so existing
   callers keep their behavior and reset stale codes with their existing resets.
   DXP publishes its raw code with a protocol label (for example `DXP reason 2`),
   while keeping the existing interpreted reason and result translation. Keep
   the existing log's raw packet/reason/stop code and result. No new protocol
   commands, timeout policy or engine capability flags.
2. **uGameOrchestrator.pas**: add a read-only GameEndReason string, reset on NewGame,
   and capture Trim(AReason) in the existing FinishGame before the game-over
   transition. Retain original logging and EngineEndReason. When an engine
   supplies an ending, also capture the actual source engine and colour and its
   optional raw code, while the engine slot is known. Do not infer the source
   later from a mutable current side. No changes to adjudication, timeouts,
   clocks, engine selection or move flow.
3. **uGameRunnerThread.pas**: carry these optional scalar metadata through existing
   owned snapshots, AssignFrom and terminal delivery. The source's registered
   display name should be consistent with existing player-name resolution, with
   a safe actual engine-name fallback. MarkStopped preserves terminal snapshots;
   clear new metadata for an actual nonterminal stop, matching existing behavior.
   No mutable engine/rules objects shared with the GUI and no log parsing.
4. **uRunningGame.pas**: expose snapshot values via read-only accessors, without
   using LastError or altering the game tree.
5. **uTournamentDialog.pas**: preserve actual error precedence, then display an
   explicit engine reason with source name/colour and raw protocol code, then the
   general GameEndReason, then legacy generic labels if metadata is absent.
   Use presentation-only wording for known generic engine reasons:
   `Draw claimed` becomes `X (Black) claimed draw`; `Resigned` becomes
   `X (Black) resigned`; `Win claimed` becomes `X (Black) claimed win`;
   `Engine ended game` becomes `X (Black) ended game`. Preserve unknown interpreted
   text and code rather than inventing an outcome. Keep manual-result and capture
   error overrides exactly where existing code applies them. For rule reasons,
   capitalize the initial character and otherwise retain useful source detail.
6. **Persistence**: the existing JSON row reason stores the final human-readable
   text, including actor/code. No new tournament schema, resumption policy,
   standings/pairing rule or layout. Existing completed rows lacking metadata are
   not retrospectively inferred from their result or scraped logs.
7. **MANUAL.md / CHANGELOG.md**: describe rule/clock causes and named engine claims
   with raw codes, distinguish claims from official results, and record the commit.

## Expected examples

These are source-derived labels, not newly inferred adjudications:

| Cause | Example Reason |
|---|---|
| White's clock expires | Flag fell for white; engine move deadline expired |
| Draughts repetition | Draw by repetition; repetitions=3 |
| Draughts endgame limit | Draw by 16-move endgame rule |
| Draughts reversible-move limit | Draw by 25-move rule; reversible_plies=50 |
| No draughts legal move | White has no legal move |
| Chess checkmate | Checkmate |
| Chess stalemate | Stalemate |
| Chess repetition | Draw by threefold repetition (claim accepted) |
| Chess move-count limit | Draw by 75-move rule |
| DXP draw claim | GWD (Black) claimed draw (DXP reason 2) |
| DXP generic ending | GWD (White) ended game (DXP reason 0) |
| DXP resignation | GWD (Black) resigned (DXP reason 1) |
| DXP win claim | GWD (White) claimed win (DXP reason 3) |

The timeout reason must retain any rules-supplied explanation for a draw when the
opponent cannot mate. Do not display “lost on time” purely because a clock expired.
Do not turn an engine claim into an official draw/win. Preserve unknown engine
endings rather than fabricating resignation, repetition or flag fall.

## Verification

- Extend existing clock/rules tests to assert the orchestrator's retained reason
  for charged-move timeouts and engine/human idle-deadline timeouts on both sides.
  Include chess timeout draw and ordinary winning timeout, with unchanged results.
- Exercise real draughts repetition, reversible/endgame limits and terminal moves;
  real chess mate/stalemate/repetition/move limits through existing rule fixtures.
- Extend the existing engine_end_reason_gui_check to pass these reasons through
  runner snapshots, copies, running game, tournament row and JSON save/reload.
- Verify NewGame clears stale reasons, late shutdown preserves terminal reasons,
  ordinary stop/error behavior is unchanged, DXP engine reason remains preferred,
  and manual/capture-error overrides retain precedence. Test named engine endings
  from both sides, codes 0/1/2/3/unknown 9, preserved code logging, empty fallback
  names, and no stale actor/code after a new game or genuine stop.
- Compile the application, run the full headless sweep, all 19 GUI suites and both
  tournament suites. Use hidden GUI displays, isolated registrations/files and
  source snapshots excluding unrelated unfinished engine feature flags.

## Related finding: 75 moves in DXP

The bundled `DXP Protocol.md` specifies GAMEREQ's move count as the number of moves
for the **whole game**, with 000 meaning no limit. After that count is reached,
either peer may end the game even without a decisive result. This differs from
the shared GUI's recurring MovesPerPeriod clock setting. The current DXP adapter
passes the configured count to DxpBuildGameReqPacket. Thus ending exactly at 75
is consistent with the requested DXP cap; the log is still required to confirm
which peer ended this particular game. Reason 0 provides no further explanation.

This proposal records/displays the actual source and raw code; it must not label
code 0 as “move limit reached” solely from timing. Revising DXP time-control/move
limit mapping is a separate policy/protocol change for review, not a silent part
of the reason-display fix.

## Review gate

AGENTS.md requires prior Claude approval for new shared functionality, unless the
user explicitly waives it for a named fix. This proposal adds general termination
metadata to shared engine/orchestrator/snapshot interfaces, beyond the previous DXP-only
waiver. The earlier GUI-only approval does not cover it. No implementation has been
made pending review or a named user waiver for this rule/clock-reason fix.

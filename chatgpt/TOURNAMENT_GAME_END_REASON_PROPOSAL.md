# Preserve rule and clock termination reasons in tournament rows

Date: 2026-10-31
Status: implemented and verified on 2026-11-01.

User authorisation: **“Please proceed!”**, in direct response to the named
termination-reason proposal and request for a prior-review waiver. This covers
forwarding rule/clock causes, ending engine name/colour and raw protocol codes.
It does not cover changing DXP move-limit/clock semantics or unrelated features.

Follow-up within this named reason-display work, 2026-11-01: the user requested
“Orchestrator declared draw by repetition” and “if the user modifies '*' to 0-2
the reason should be updated to 'GWD claimed win. Operator set result to ..'”.
Apply that requested presentation extension to both games: label rules-derived
endings as orchestrator decisions, retain engine claims when an operator overrides
the result, replace the operator suffix on subsequent edits and retain it through
save/reload and late completion. Clearing an override restores the prior cause.
This extends the earlier manual-reason wording scope, without changing results,
claims policy, the override mechanism, rescheduling or record schemas.

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
   identify the orchestrator as the source: “Orchestrator declared draw by …”,
   “Orchestrator declared checkmate”, or “Orchestrator: Flag fell for …”. Retain
   useful source detail. Following the user's additional request, operator edits
   append “. Operator set result to RESULT” to the original cause/claim, rather
   than replacing it with “Manual result”. Subsequent edits replace this suffix;
   clearing the override restores the original cause. Load/save and late completion
   retain the same provenance. Existing capture-error precedence remains.
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
| White's clock expires | Orchestrator: Flag fell for white; engine move deadline expired |
| Draughts repetition | Orchestrator declared draw by repetition; repetitions=3 |
| Draughts endgame limit | Orchestrator declared draw by 16-move endgame rule |
| Draughts reversible-move limit | Orchestrator declared draw by 25-move rule; reversible_plies=50 |
| No draughts legal move | Orchestrator: White has no legal move |
| Chess checkmate | Orchestrator declared checkmate |
| Chess stalemate | Orchestrator declared draw by stalemate |
| Chess repetition | Orchestrator declared draw by threefold repetition (claim accepted) |
| Chess move-count limit | Orchestrator declared draw by 75-move rule |
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
waiver. The earlier GUI-only approval does not cover it. The user authorised this
named proposal with “Please proceed!” on 2026-11-01, as recorded above;
Claude reviews the resulting commit afterwards.

## Rule discrepancy found while answering the user's question

The official [FMJD Annexes, August 2024, Annex 1 article 6.3, page 14](https://www.fmjd.org/downloads/FMJD_Annexes_2024_8-sig.pdf#page=14)
retain the 16-move limit for three pieces including a king versus one king, but
also specify five moves when the lone king occupies the long diagonal. The current
`TEndgameDrawCounter` only observes material and does not model that diagonal
condition. This predates the reason-display fix. No adjudication change is made
here. A separate reviewed rules change should establish the exact diagonal/counter
transition semantics and add real-board tests before implementation. The current
reason text faithfully reports the existing counter's decision.

## Implementation verification — 2026-11-01

- Linux GTK2 application compiled successfully.
- Full `tests/run_regression_checks.sh` passed, including chess/draughts rules,
  engine clock/ponder/runner lifecycle checks, source audits, database checks,
  manual/build identity and source-archive checks. Additional final targeted
  `game_end_reason_check` passed 61 checks (both sides, both games, charged/idle/
  engine-deadline timeout, chess timeout draw, roots and repetitions).
- Extended `endgame_draw_check` passed real 5-move and 25-move noncapturing walks,
  terminal capture and reset assertions. `tests/run_dxp_checks.sh` passed with
  raw-code/source and log assertions for reason codes 0/1/2/3/9 and both colours.
- After the user's follow-up wording changes, all 19 GUI suites passed, including
  `multi_game_gui_check` (140), layout (9602), engine-end reasons (266) and
  tournament tabs (200). The focused reason suite reports zero unfreed blocks.
- Both `tests/run_tournament_checks.sh` suites passed again after operator wording
  changes: draughts preservation and chess tournament checks (101), including
  override/capture/reschedule persistence paths. GUI tests ran on hidden displays
  with isolated preferences; no user windows or engine directories were touched.
- Tested an isolated source snapshot containing only this fix, excluding the
  pre-existing unfinished engine-feature changes. Compared staged source/tests
  byte-for-byte with that tested snapshot. Native Windows execution remains QA.

No rule or DXP clock/move-cap behavior was changed. The separately documented
long-diagonal exception needs review before any future adjudication fix.

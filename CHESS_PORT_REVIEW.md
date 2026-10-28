# Chess preparation review

Reviewed 2026-10-28 against GWDGUI 3.4, upstream commit
`61c6cef894e18544d18e7e761143de47ef492226` from
https://github.com/gwiesenekker/GWDGUI. Local commit `b844e0b` preserves that
source tree exactly. The subsequent ZGUI branding does not implement chess.

The refactoring gives us a usable shared core. It does not yet provide chess
rules, SAN/PGN, a chess board or UCI. The application still plays draughts.
Claude's local position-interface proposal in the independent GWDGUI checkout
was also consulted; the checked-in implementation is the authority below.

## Implementation status — 2026-10-28

The position/rules adapter is tested through the existing interfaces. The
executable now explicitly selects chess before form creation and displays the
8×8 board in the existing layout for standalone FEN exploration. The shared
board base and existing PV browser were adapted according to Claude's review;
no replacement tree, router, runner, clock or database was introduced.

Board controls and the PV browser own their position snapshots. Chess uses
original GPLv3 vector piece drawing and orientation-aware coordinates. The
existing legal list, promotion chooser, tree/variation navigation, PV pending
updates and score history are reused. Two-click chess input is a GUI interaction
option; the draughts single-move shortcut remains the default.

PGN loading/saving now reuses the existing tree, actor, file browser and export
traversal. UCI configuration and finite analysis use the existing editor, shared
process worker, factory, analysis runner and coordinator, as approved in Claude
review c0493e3. GUI layout is preserved; engine PVs remain typed analysis data.
Clocked games now use the existing New game dialog, runner, orchestrator,
two-sided engine clock contract and snapshot display anchors, following Claude
review bc177c4. Pondering, Auto Play, setup, tournaments and databases remain
future steps and stay guarded for chess. Rule limitations remain, including
conservative dead-material detection.

See `tests/README.md` for interface/perft, rendering and GUI validation. Baseline observations below
refer to the imported code before these isolated adapter/view steps.

## Prepared contracts to reuse

| Boundary | Existing implementation | Chess work within that boundary |
| --- | --- | --- |
| Positions and moves | `uGamePosition.pas`: `TGamePosition`, `TGameVariant`; draughts adapter in `uDraughtsPosition.pas` | Implement a chess adapter with FEN, legal moves, canonical UCI move strings and SAN presentation. Register/select the variant rather than introduce another game model. |
| Outcomes | `TGameRules`, including `TimeoutOutcome`, injected into the existing orchestrator | Implement chess repetition, move-count and material rules. Position keys must account for castling and legally available en passant; the tree owns history. |
| Tree, navigation and notation | `uGameTree`, actor, builder, cursor, displayed position, move interaction and notation presentation consume the position/variant contracts | Reuse the tree and its existing engine, annotator and Auto Play PV metadata. No parallel analysis cache or replacement tree. |
| Game play and clocks | `uGameOrchestrator`, `uGameRunnerThread`, `uRunningGame` | Supply chess positions, rules and engines to the existing runner. Do not implement another match controller or clock. |
| Engine lifecycle | `uEngineBase.pas`: `TGameEngine` and registered factories; shared `uPlatformProcess` | Add a UCI protocol subclass using existing lifecycle, cancellation, logging and stop fences. Do not replace process or game orchestration. |

The rules contract currently automatically accepts claimable draws as well as
mandatory draws; it has no GUI draw-claim action. For chess, document and test
that policy (threefold/50-move claims versus fivefold/75-move automatic draws,
and mate precedence) rather than silently changing the generic contract.
Move notation is computed on the position before the move. Starting side and
fullmove number are already explicit variant metadata.

`tests/position_contract_check.pas` tests the position boundary.
`tests/game_tree_variant_check.pas` and `tests/uCounterGamePosition.pas` exercise
an independent game through the tree, actor, builder and runner while draughts
remains the default. `tests/source_audit_check.sh` enforces the neutral unit
dependency boundary. These are useful existing regression tests for every port
step; extend them with chess cases instead of replacing their infrastructure.

## Remaining seams requiring care and Claude's review

- **Application composition and board:** the program links draughts adapters;
  `uMainForm` and position setup still use concrete draughts board/control types.
  Add chess geometry/pieces/setup behind the existing interactions and preserve
  the GUI layout. Any generic routing change needs prior review.
- **Engine selection:** the factory boundary exists, but
  `uEngineRegistry.TExternalEngineKind` only contains Hub and DXP; configuration
  and annotator controls know those protocols. UCI needs a reviewed extension
  of registration/selection plus a game-specific protocol implementation.
  Pondering must use the existing game/engine lifecycle, not a second controller.
- **Game files and results:** `uGameTreeActor` still accepts `TPdnMoveNode` from
  `uDraughtsPdn`; `uPdnText` normalizes result tokens to draughts results.
  Implement PGN as a file-format adapter to the existing tree and traversal,
  preserving comments, variations and PV metadata boundaries. Claude should
  review the narrow import/result seam before generic code is changed.
- **Tournaments:** pairing, concurrent running, recovery and standings already
  exist. `uTournamentDialog` and `uTournamentResults` still recognize draughts
  result/scoring tokens; `uTournamentGameRecord` uses PDN. Have Claude review a
  result/record adapter; retain the existing scheduler and tournament machinery.
- **Databases:** `uGameDatabase` uses concrete draughts positions/sides and PDN
  import, packed position keys and draughts result summaries; `uDatabaseForm`
  uses a draughts board. Reuse SQLite storage, workers, filtering and duplicate
  detection. Agree with Claude on the position-key/record/result adapter and
  schema compatibility before editing this shared code. No parallel database.

## Proposed implementation order

1. Agree with Claude on the remaining shared seams above before changing them.
2. Implement and test a chess position/variant/rules adapter in isolation: FEN
   round trips, legal moves/perft, castling, en passant, promotion and outcomes.
3. Connect an 8×8 board and chess setup to the existing interactions and tree,
   with the existing GUI layout. Verify navigation and PV/hint behaviour.
4. Add SAN/PGN adapters to that same tree, testing nested variations, comments
   and round trips through the established file workflow.
5. Add UCI using the existing engine base and runner; test analysis, clocked
   play, stop/restart fences and pondering through the shared lifecycle.
6. Enable chess tournaments and databases through the reviewed adapters and
   existing regression suites. Do not build replacement subsystems.

Each step should be separately reviewable, recorded in CHANGELOG.md, compiled
and tested. If generic functionality must change, revert that change to the
previous commit and present the proposal for Claude's review. No generic
functional changes are part of this baseline.

## Baseline verification

The pristine import and renamed source both passed the full headless regression
suite. The renamed application compiled for Linux GTK2 and passed all five
existing GUI suites (preservation, form boundaries, delivery/shutdown, help and
notation preferences). The Windows build-info generator was tested on the host;
native Windows application execution was not tested. The existing experimental
SynEdit warning remains. All production Pascal units compare byte-for-byte with
the pristine import except application-name substitutions in `uMainForm`,
`uAppInfo` and `uManualForm`; the program/project names and build targets were
also renamed. No generic functional code was changed.

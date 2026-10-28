# Changelog

ZGUI changes, newest first, starting from the GWDGUI 3.4 baseline.

## Unreleased

### PGN review follow-up — 2026-10-28

- P8: recover collection entries at a fresh tag line after movetext, including
  unclosed comments/variations and missing results; keep later games reachable.
- F2: index byte offsets and decode only header prefixes, without copying or
  converting every movetext byte. Keep per-game validation deferred.
- F1: reuse successful validation of identical entry bytes for replay; changed
  bytes still require a new candidate. The proposed shared actor cache awaits
  a separate review and is not implemented here.
- P9/P10/U11: retain evaluation depth, document evaluation-source and comment-order
  normalization, and show traditional NAG symbols on screen while files keep $n.
- C3: remove tracked references to ignored design-document paths.
- Validation: 110 PGN checks pass with range/overflow/heap checking; application
  compiles. Listing 137.1 MB / 20,000 entries takes 445 ms; validation plus cached
  replay of 200 plies / 676 nodes takes 2,000 ms in an optimized build.

### UCI integration proposal — 2026-10-28

Approved with D1–D3 in Claude review c0493e3; implementation follows separately.

- Inspect the existing engine factory, Hub process worker, analysis runner,
  configuration editor and GUI composition policy. Prepare a local review
  proposal for UCI configuration and analysis through those existing components.
- Specify the shared extractions and interfaces needing review, protocol stop
  fences, coherent PV/score publication, option persistence, retained INI editing,
  unchanged GUI layout and staged capability guards. Include fake-engine and
  Stockfish acceptance tests; leave game running and pondering for later steps.
- Documentation only; no production changes, compilation or test run in this step.

### Reviewed PGN integration — 2026-10-28

Commit: `435d6de`.

- Apply Claude's approved proposal with G1/P2–P7/U9 changes: preserve existing
  tree/actor, notation traversal, file browser and atomic append/save workflow.
- Add owned header-tag arrays, typed NAGs and leading comments. Merge repeated
  variations and their annotations with warnings; keep one child per move (G1).
  Import comments literally through typed node data, never free-text draughts
  score recognition (P3).
- Read and write PGN with legal SAN, custom FENs, nested variations, all results,
  unknown tags, escaped strings and UTF-8. Convert CP1252 with a warning (P5).
  Reject null moves clearly; accept e.p. only after en passant (P7).
- Add standard evaluation/clock/elapsed-time commands without projection prose;
  keep unknown commands literal. Offer an API option for lossless typed metadata,
  preserving PV/depth without turning analysis into variations (P2).
- Validate in a temporary existing tree, then replay immutable text through the
  displayed actor before one refresh (P4). Invalid input preserves tree identity.
  A checked 200-ply two-pass import takes about four seconds with debug checks.
- Reuse the existing multi-game browser and deferred selection, with a 16 MiB
  per-game limit. Supply file capabilities, reader/export policy, board factory
  and click policy through a GUI composition profile (U9); enable PGN Open/Save
  while keeping the existing layout and other pending chess features disabled.
- Use the Seven Tag Roster, matching termination result, paired SetUp/FEN tags,
  numeric NAGs and token-boundary wrapping near column 80 (P6). Indivisible
  comments/tokens may exceed that width; their literal text is preserved.
- Extend headless and existing GUI tests for round trips, literal annotations,
  metadata isolation, malformed imports, deferred collections, save/append,
  replacement/close cancellation and failed saves. Reuse the existing standalone
  display transition; cancelled saves retain the browsed position and view.
  Update README and manual.
- Validation: application compilation, full headless regression and all six GUI
  suites pass (691 chess GUI checks). The 96 PGN adapter checks also pass with
  range/overflow/heap checks and zero unfreed blocks. Independent python-chess
  comparison matches 80 games / 3,650 nodes, including SAN, headers, comments,
  NAGs, variations, evaluations and clocks.

### PGN adapter foundation — 2026-10-28

Commit: `d082285`.

- Start the chess PGN file adapter with an independent text scanner for tags,
  comments, move symbols/numbers, NAGs, variations and results. Retain UTF-8,
  report source locations and bound token sizes. This is syntax scanning;
  semantic game parsing and GUI Open/Save are not enabled yet.
- Add 1,193 scanner checks to the normal regression suite, including escaped
  strings, line endings, traditional annotations, malformed input and bounded
  progress. The standalone suite also passes range/overflow and heap checks.
- Prepare the local PGN proposal (review d082285) for Claude: extend existing
  metadata/actor seams, notation export, file browser and GUI policy (U9).
  Shared production code remains unchanged in this step, pending that review.
- Validation: full headless regression sweep, source audit, build-info/archive
  checks and application compilation pass.

### Review fix U10 — 2026-10-28

Commit: `bf35f0a`.

- U10: add an optional Cancel-default setting to the existing confirmation
  dialog. Chess discard prompts select and initially focus Cancel, so Enter
  keeps the exploration; explicit Discard remains available. Existing save
  and OK prompts retain their accept-button default.
- Clarify the question as “Discard the current board and its moves?” to cover
  custom root FENs as well as explored moves.
- Test actual modal dialogs and their default/focused buttons, both discard
  entry points, explicit discard, and unchanged legacy save/OK defaults.
- Validation: all six GUI suites pass (673 chess checks, range/overflow
  checking, zero unfreed heap blocks), plus application build and source audit.

### Review fixes U7 and U8 — 2026-10-28

Commit: `202e173`.

- U7: reuse the existing confirmation dialog to ask Discard / Cancel before
  replacing or closing a chess exploration. Protect moves, variations and
  custom FEN roots without offering unavailable PDN saving. Cancel leaves the
  tree, node identities, navigation selection and displayed position intact;
  an untouched standard board does not prompt. Draughts save prompts remain.
- U8: choose black or white chess-coordinate text from the actual square
  background, preserving layout and improving contrast with custom themes.
- Extend GUI tests for cancellation, explicit discard, invalid replacement,
  custom roots and rendered coordinate contrast in both orientations.
- Validation: application build, all six GUI suites (647 chess checks with
  range/overflow checking and zero unfreed heap blocks), manual document checks
  and the source audit pass. Existing draughts save/close tests remain intact.
- U9 remains deferred to PGN integration, as agreed with Claude's review.

### Select standalone chess exploration — 2026-10-28

Commit: `236c904`.

- C1: explicitly select chess in `zgui.lpr` before form creation, retaining the
  selected variant until all forms/views are destroyed. ZGUI opens an 8×8 board
  with the existing GUI layout, board/list input, promotions, FEN and navigation.
- Document working exploration features and the disabled pending chess adapters
  in README and the manual. State that exploration is not yet saved as games.
- Add the chess GUI suite to the standard GUI runner; retain all five existing
  draughts suites. Record the original vector artwork's GPLv3 licence.
- Validation: application compilation/startup smoke test, full headless suite,
  all six GTK GUI suites, and eight nonblank reference bitmap comparisons pass.
  The 534-check chess GUI suite also passes range/overflow checking with zero
  unfreed heap blocks. Native Windows GUI execution was not tested.

### Reviewed chess board and shared PV integration — 2026-10-28

Commit: `f7e2e5e`.

- Address U1/U2/A1: bind the main/mini/popout views to owned game-position
  snapshots and adapt the existing PV browser, retaining its navigation,
  pending-update freeze, selection offsets and invalid-prefix behaviour.
  Show SAN and variant-provided move numbers; clear incompatible PV bases.
- U3/U4: add original GPLv3 Canvas vector chess artwork and edge coordinates
  that follow board orientation. No external piece font/assets are required.
- U5/U6: retain the existing move router and promotion/capture chooser, with
  neutral wording and an optional GUI interaction flag so chess always waits
  for a destination click. Draughts retains its one-move source shortcut.
- C1/P1: centralize GUI capability guards for not-yet-connected chess features,
  including automatic database search and PDN save/replace/close paths. Keep
  all existing controls and layout. Standalone exploration is this step's scope.
- C2: migrate GUI assertions to the shared position interface. Harden bitmap
  capture against stale raw-image caches; nonblank saved fixtures match the
  previous renderer exactly. The new chess GUI suite passes 534 checks,
  including equal control bounds across both games. Existing GUI and full
  headless suites pass. Score history is retained and tested unchanged.
- Keep trees, runners, clocks, tournaments, databases and engine process
  implementations unchanged; these are view bindings, not replacement systems.

### Shared board presentation extraction — 2026-10-28

Commit: `f421f5b`.

- Address Claude U1/U2/U4: extract the existing board rendering shell, themes,
  flip mapping and highlights into `TGameBoardControl`, with owned position
  snapshots and game-specific geometry/piece/coordinate hooks.
- Preserve `TDraughtsBoardControl.Board` for existing setup/database consumers;
  refresh its legacy board snapshot before paint so pieces and marker agree.
- C2 validation: eight rendered bitmap fixtures match the `42e0d54` renderer
  byte-for-byte. All five existing GTK GUI suites and the application build pass
  with draughts still selected. No game/tree/runner/database logic changed.
- Remove the inherited GWDGUI changelog entries through version 3.4 as requested.

### Chess board integration review — 2026-10-28

Recorded in commit: `f421f5b`.

- Inspect the board, legal-move routing and PV view connections. The move
  selection and legal list already use the existing game interfaces, but the
  main/mini board bindings and PV browser still require draughts types.
- Prepare the local board proposal (review U1/U2) for Claude's review before
  changing the shared board presentation or PV browsing. No production code
  or GUI behaviour changed during this review.

### Chess position and rules adapter — 2026-10-28

Commit: `42e0d54`.

- Add `uChessPosition.pas` implementing the existing position, variant and rules
  interfaces for orthodox chess: transactional six-field FEN, legal UCI moves,
  SAN, castling, en passant, promotions and repetition identity.
- Add checkmate/stalemate, automatic acceptance of available threefold/50-move
  claims (including intended moves), fivefold/75-move outcomes, and standard
  insufficient-material and timeout handling. Arbitrary dead-position
  fortresses are not solved; FEN checks do not prove historical reachability.
- Keep chess opt-in and unregistered: no GUI, default-variant, game runner,
  tree, tournament, database or engine infrastructure changes.
- Extend the existing interface contract tests with chess/perft fixtures and
  add focused rules and shared-core integration tests to the regression suite.
  Supply an optional independent python-chess differential check.
- Validation: application build and full regression suite passed, including
  643238 interface-contract checks and 226 focused chess checks. Range/overflow
  and heap checks passed. The independent oracle matched 6143 positions and
  180183 legal moves, SAN strings and resulting FENs. All existing production
  Pascal units and application composition remain byte-for-byte unchanged.

### ZGUI baseline — 2026-10-28

Commits: `b844e0b` (upstream import), `19f767d` (ZGUI branding and adapter plan).

- Import GWDGUI 3.4 from upstream commit
  `61c6cef894e18544d18e7e761143de47ef492226` as an exact, separately committed
  baseline.
- Rename the application, Lazarus project and executable to ZGUI / `zgui`;
  update build scripts, help branding and existing branding checks.
- Document the prepared chess/engine interfaces and remaining adapter boundaries
  in `CHESS_PORT_REVIEW.md`. Preserve existing GUI layout and game behaviour.
- Record the requirement to reuse shared game, tournament and database code;
  any necessary generic code change must be reverted for Claude to review.
- Validation: Linux GTK2 build, full headless regression suite (before and after
  branding), and all five existing GTK GUI suites passed. The inherited
  experimental SynEdit warning remains. Native Windows execution was not tested.

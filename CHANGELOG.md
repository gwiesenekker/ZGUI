# Changelog

ZGUI changes, newest first, starting from the GWDGUI 3.4 baseline.

## Unreleased

### Select standalone chess exploration — 2026-10-28

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

- Inspect the board, legal-move routing and PV view connections. The move
  selection and legal list already use the existing game interfaces, but the
  main/mini board bindings and PV browser still require draughts types.
- Prepare `chatgpt/CHESS_BOARD_INTEGRATION_PROPOSAL.md` for Claude's review before
  changing the shared board presentation or PV browsing. No production code
  or GUI behaviour changed during this review.

### Chess position and rules adapter — 2026-10-28

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

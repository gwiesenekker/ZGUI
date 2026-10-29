# Changelog

ZGUI changes, newest first, starting from the GWDGUI 3.4 baseline.

## Unreleased

### Reviewed chess setup and score-history preferences — 2026-10-29

- Implement the approved position setup adapters in the existing dialog and
  enable chess setup. Keep its outer layout and draughts palette, and fit twelve
  chess pieces into the existing palette region. Reuse board geometry, artwork,
  preferences, FEN validation and standalone acceptance/replacement paths.
- Keep incomplete chess drafts outside the playable-position interface. U14:
  retain castling rights still supported by home-square kings/rooks; never add
  rights through placement. Clear en passant on placement or side changes and
  reset the halfmove counter on placement while retaining the fullmove number.
- U15: keep the setup window, draft and text when replacement is cancelled or
  saving fails. U16: consume typed FEN on explicit Paste FEN/Apply only; prompt
  once, defaulting to Cancel, before board edits discard pending typed text.
  Keep the inherited draughts FEN behavior and database setup callback behavior.
- Add the approved Score history Preferences tab using the existing colour
  chooser, swatches, Save, Close and global Defaults. Persist eight colour roles
  with legacy-compatible defaults; update embedded and popout graphs immediately
  outside the score-signature cache. Score interpretation and data are unchanged.
- Apply the reviewed PV Escape key-preview fix while preserving Auto Play's
  stop-first priority. T4: restore Clear pairing confirmation for chess results
  by passing the profile format to the existing parser.
- Update the manual for setup metadata, cancellation, orientation, FEN edits,
  colour preferences and PV Escape. Detailed chess FEN diagnostic messages (R1)
  remain a separate approval item; the authoritative validator is unchanged.
- Validation: application builds; full headless regression, all eight GTK GUI
  suites and both tournament suites pass (101 chess tournament checks). The 199
  focused setup/preferences checks cover
  incomplete drafts, minimum/scaled palettes, cancellation/failed saves,
  persistence and unchanged-score colour delivery, plus PV Escape through LCL
  application/form key dispatch. Baseline comparisons verify pixel-identical
  draughts setup at default/minimum sizes, default line/bar graphs and chess
  boards (eight bitmap fixtures).

### Score-history colour preferences design review — 2026-10-29

- Prepare the requested Preferences tab for Claude's review: reuse existing
  colour pickers and Save/Cancel/Defaults for score sources, missing-score marks
  and the selected-ply marker. Preserve default colours and deliver changes to
  both score-history views without changing score data or parsing.
- Proposal only; shared preferences/rendering changes await review as required
  by AGENTS.md.

### Score-history colour key — 2026-10-29

- Add the playing-engine and annotator colour key to the manual, including
  missing-score marks, paired bar order and the selected-ply indicator.

### Chess position setup design review — 2026-10-29

- Prepare a proposal against `a410a3d` for Claude: reuse the existing position
  setup form and acceptance path, preserve its outer layout, and fit a chess
  palette into the existing region. Propose dialog-local draft adapters,
  strict FEN validation, explicit metadata/text-editing policies and a narrow
  shared rendering seam for incomplete chess setups.
- Record the reported PV Escape problem separately for review: main-form key
  preview appears to consume Escape before the focused PV memo can unlock
  updates. Propose a focused routing fix and native key-dispatch regression.
- Documentation only; no application behavior or GUI changes in this step.

### Reviewed chess engine tournaments — 2026-10-29

Commit: `433b035`.

- Implement Claude's approved tournament integration using the existing dialog,
  pairings, scheduler, game runner, clocks, reservations, standings and recovery
  paths. Enable the existing tournament action for chess, with UCI participants,
  chess FEN/clock defaults and validated settings; preserve the GUI layout.
- T2: parse results by file format. Chess displays 1/0.5/0 and scaled SB values,
  including quarter points, while preserving internal scoring, pairing and
  tie-break arithmetic and the exact legacy draughts result set.
- D5: force tournament pondering off at runtime through the approved setup flag
  and engine hook, without changing saved options or ordinary games. D8: log
  ponder-miss acknowledgements distinctly from actual early ponder completions.
- Publish PGN through the existing capture and ownership/recovery pipeline.
  Preserve comments, variations, manual-result provenance and attempt history.
  P12: retain Seven Tag Roster order and the game's start date. Store explicit
  chess/PGN metadata in version 3; retain existing JSON keys and reject
  cross-variant loads before changing the dialog. Legacy draughts stays version 2.
- D6: warn about tournament participants sharing an executable/options file.
  Document that limitation, CPU/hash contention, the single opening FEN, inherited
  Swiss BYE/tie-break conventions and unfinished `*` results after engine errors.
  Per-registration options and opening-file support remain separate work.
- Validate numeric/FEN settings before pairing, saving and starting; pause new
  scheduling on an invalid concurrency edit while active games finish. Busy
  participants show a temporary waiting reason in the existing row column.
- Validation: application build, full headless regression, all seven existing
  GTK GUI suites and legacy tournament preservation checks pass. New checks cover
  chess results/pairings/records/storage (42 checks), concurrent games, Swiss advancement,
  Stop/crash handling, manual results, rescheduling, runtime ponder-off and PGN
  preservation, including a Stockfish 19/Arasan 26.1 double round robin (123 GUI
  checks). Independent python-chess checks verify PGN roster/date, result,
  comments, variations and clock annotations.

### Tournament start failure review (T1) — 2026-10-29

Commit: `ce8a78d`.

- Apply Claude review 909d6ce's standalone fix before chess tournament changes.
  Check executable availability and contain throwing or rejected start callbacks
  in the existing scheduler. Persist/log one unfinished row reason and allow
  independent rows to continue; timer ticks do not repeatedly retry failures.
- Validation: application compiles and the existing tournament preservation
  suite passes, including missing executables, throwing/nil callbacks and
  repeated ticks. GUI layout and game/engine infrastructure remain unchanged.

### Chess engine tournament design review — 2026-10-29

- Prepare a proposal against `909d6ce` for Claude's review. Reuse the existing
  tournament dialog, pairings, scheduler, standings, game runner, clocks, engine
  factory, reservations, records and recovery paths while preserving GUI layout.
- Identify proposed shared boundaries for profile defaults/validation, chess
  result display, PGN capture/publication, versioned storage and tournament-only
  runtime ponder-off policy. Include compatibility and failure/recovery tests.
- Documentation only; no application code or GUI behaviour changed.

### Reviewed UCI pondering and annotator information — 2026-10-28

Commit: `481aa77`.

- Implement the approved UCI pondering design and M4/M5/D5 through the existing
  engine adapter, game orchestrator, clocks, snapshots and process worker.
  Enable only a saved true Ponder check option in game sessions; discovery and
  analysis keep it off without overwriting the saved choice. INI editing remains.
- Start background work only after move acceptance. Match full root/history and
  the engine's own clock fields for ponderhit; ignore stale opponent clock fields.
  On a miss, stop/fence the predicted search before searching the actual position.
  Charge reconciliation to the real turn and retain its original total deadline.
- M4: retain a legal early ponder bestmove, return it on a hit without ponderhit,
  and discard it on a miss without waiting for stop. Illegal/duplicate replies
  and background failures retain the existing explicit-error/unfinished-result
  policy. Stop still takes precedence over timeout in both return/error paths.
- Discard speculative info: no predictions, scores or PVs become played moves,
  variations, hints or annotations. Keep existing game and analysis GUI layout.
  Document per-engine opt-in, CPU contention and the future tournament-level
  ponder-off default; tournaments remain disabled.
- At the user's additional request, add the annotator score/depth/time line above
  its PV by supplying a label to the same existing PV browser used by engines.
  No renderer, game-tree or analysis-coordinator changes.
- Validation: application build, full headless regression and all seven GTK GUI
  suites pass. Checked deterministic pondering tests cover hit/miss, early output,
  both colours, periods, history/clock mismatches, >64 KiB idle output, faults,
  Stop during hit/miss, analysis transitions and idle shutdown without leaks.
  Real Stockfish 19, Arasan 26.1, RubiChess 20240817 and Igel 3.8.0 pondering
  games exercise actual hits/misses without protocol failures. The GUI tests
  verify saved opt-in and the annotator header's values, navigation and clearing.
  Final checked runs pass 160 deterministic pondering checks / 165 with Stockfish
  and 86 focused GUI checks. Miss-stop waits are bounded by the real deadline;
  deadline expiry and cancellation during reconciliation are covered explicitly.

### Reviewed pondering infrastructure — 2026-10-28

Commit: `267d14c`.

- Apply the shared seams approved in Claude review b833e78: one default-no-op
  accepted-move notification and a reused side-specific clock-record builder.
  Notify only the mover after accepted nonterminal moves without a stop request.
- Add an optional owner-thread idle callback to the existing process worker.
  Preserve the infinite-wait path for Hub/DXP; add no process reader or worker.
  Leave platform-process reads unchanged, as requested in the review.
- Validation: application build, full headless regression suite and all seven
  GTK GUI suites pass with the integration. Existing Hub worker and clocked
  command streams remain byte-identical to their recorded baselines.

### Local UCI engine installation — 2026-10-28

- Install Stockfish 19, Koivisto 9.0, Arasan 26.1, RubiChess 20240817 and
  Igel 3.8.0 in engine1 through engine5 and register them using the existing
  registry API. Keep executables, networks and machine-specific configuration
  locally ignored. Record official sources, licenses and SHA-256 checksums.
- Use official Linux releases for the first four; build Igel from its release
  source/network. Its benchmark matches the reference 2325568 nodes. Configure
  one thread and 64 MB hash per engine; pondering remains disabled.
- Validation: all five initialize, analyze and play legal clocked moves as both
  colours through the existing UCI adapter/orchestrator. Registry save/reload
  and executable checks pass; the checked harness reports no memory leaks.
  No application source or GUI changes.

### UCI pondering design review — 2026-10-28

- Prepare a proposal against `b833e78` for Claude to review before implementation.
  Reuse the existing engine, game, clock and process infrastructure and preserve
  GUI layout. Explicitly identify the accepted-move notification, idle worker
  servicing and bounded process-read extensions requiring shared-code approval.
- Specify opt-in configuration, legal predictions, hit/miss completion fences,
  clock attribution, speculative-output isolation, failure handling and tests.
  No production code or GUI behaviour changed in this proposal step.

### Reviewed clocked UCI games — 2026-10-28

Commit: `62b20b9`.

- Apply Claude review bc177c4 through the existing New game dialog, game runner,
  orchestrator, clocks, snapshots, actors, engine factory and process worker.
  Preserve GUI layout; no replacement game loop, clock, tree or process manager.
- Add a complete two-sided clock value with a default bridge to the existing
  single-side virtual method. Hub/DXP remain on their existing protocol paths.
  Independently record a clocked Hub go-think trace against bc177c4; old and new
  API paths match its exact bytes, alongside the original worker trace.
- Extend UCI with explicit game/analysis context, both clocks/increments and
  moves-to-go, fresh-clock validation, mode-aware deadlines and AnalyseMode.
  Keep finite analysis, exact primary PV tuples, option persistence and INI editing.
  Remove duplicate first-game ucinewgame (D4). Retain live search-info updates
  when the existing game runner hides raw stdout.
- M1: distinguish real deadline expiry from cancellation/process failure. Guard
  both orchestrator return and exception paths before timeout adjudication.
  Stop retains * and charges elapsed engine time without accepting a move.
  M2: a crash/protocol failure stops with an explicit error and unfinished *;
  it is not awarded as a time loss.
- M3: use one available-time policy for moves, engine deadlines and idle-human
  expiry, retaining the inherited increment/period semantics. Adjudicate terminal
  starting positions with existing rules. Add view-only snapshot clock anchors
  and update existing labels through the existing GUI timer, including quiet
  engines; U12 uses the runner's anchor with no new orchestrator event.
- U13: supply chess 5+3 sudden-death defaults through the GUI profile. Validate
  FEN, numeric fields, player kinds and engine definitions through one shared
  setup path before creating a game; keep invalid dialogs open. Enable only
  gfNewGame; pondering, Auto Play, setup, tournaments and databases stay guarded.
- Validation: application compiles; full headless regression and all seven GTK GUI
  suites pass. New game tests pass 69 deterministic checks / 73 with Stockfish 16;
  expanded UCI GUI tests pass 54 deterministic checks / 80 with Stockfish. Cover
  both colours, period transitions, custom roots, promotion, Stop, idle flags,
  crash policy, quiet clocks, live PVs, reservations, two engines and PGN reload.
  Checked UCI game/GUI runs report no unfreed heap blocks.


### PGN recovery and actor validation cache review — 2026-10-28

Commit: `d7bc078`.

- Fix P11: require a real tag-line prefix for damaged-game recovery; keep column-1
  embedded commands inside comments. Indent bracket/percent comment continuation
  lines on export and cover raw wrapped comments plus ZGUI's own round trip.
- Implement the approved F1(b)/G2 one-position actor cache. Key it by node identity
  and structural generation; annotation-only mutations retain the entry. Fall
  back to existing replay on a miss and invalidate on rebuild/header/topology
  changes. No validation bypass or alternate import/tree model.
- Validation: 123 PGN checks pass with range/overflow/heap checks; full headless
  regression passes. An optimized 137.1 MB listing takes 484 ms; validation plus
  replay of the 200-ply / 676-node fixture takes 608 ms. Append/store/append
  replay-count regression confirms annotations do not defeat the cache.


### Clocked UCI games proposal — 2026-10-28

- Prepare a local proposal for Claude against bc177c4, reusing the existing game
  runner, orchestrator, clocks, engine worker, snapshots and New game dialog.
- Request review of the two-sided clock contract, UCI game/analysis contexts,
  cancellation classification, idle-human expiry, initial outcomes, clock display
  anchors and existing-dialog/profile bindings. Preserve GUI layout and defer
  pondering, Auto Play, tournaments, databases and position setup.
- Documentation only; no production changes or compile/test run in this step.


### Reviewed UCI configuration and analysis — 2026-10-28

Commit: `76ea792`.

- Apply Claude review c0493e3 with D1–D3 through the existing engine factory,
  extracted process worker, analysis runner, coordinator, tree and GUI. No new
  game, clock, tournament, database, navigation or analysis controller.
- Add the UCI protocol adapter: handshake/readiness, advertised options, new-game
  notification, root FEN plus played moves, finite analysis and bestmove/stop
  fences. A missing completion or known protocol violation makes the session
  unusable; cancellation interrupts discovery and shutdown waits.
- D1: publish coherent exact primary PV/score/depth/time tuples only. Keep the
  last exact tuple on bounds/secondary lines; validate legal PV prefixes and
  normalize pawn/mate scores to White. Unchanged-PV score/depth updates reach
  the existing tree, PV views and score history without becoming played moves.
- D2: match saved option names without regard to case and send advertised spelling.
  Retain separate UCI JSON settings, defaults/ranges/choices, custom identities
  and INI editing; preserve Hub/DXP settings and ordinals. Discover options and
  invoke buttons on the existing engine worker, with timer-delivered UI updates
  and Cancel. Buttons are one-shot and never replayed on launch.
- Keep existing widget bounds and layout. Enable the existing chess engine editor
  and annotator; filter the analysis picker by profile. Keep clocked games,
  pondering, Auto Play, Hub MCTS, setup, tournaments and databases disabled.
- D3 extraction was committed and verified independently before UCI implementation.
  The final Hub wire trace still matches the pre-extraction fixture.
- Validation: application compiles; full headless and all seven GTK GUI suites
  pass, including preserved layout/Hub lifecycle checks. UCI range/overflow/heap
  checks pass (59 fake/registry checks, 62 including Stockfish 16). The UCI GUI
  checks pass (29 deterministic checks, 34 including real Stockfish initial and
  custom Black-root analysis). No unfreed heap blocks in the UCI checks.


### Reviewed Hub worker extraction (D3) — 2026-10-28

Commit: `35113f8`.

- Extract Hub's existing process worker, command completion, line framing,
  bounded reply queue, launch preparation and shutdown into a neutral helper
  owned by the existing engine. Preserve Hub inheritance and protocol policy.
- Record the pre-extraction wire stream and retain an exact regression fixture
  for launch, analysis, navigation/stop, MCTS and quit. No UCI code in this commit.
- Validation: recorded wire bytes match; full headless and all six GUI suites
  pass, including Hub fences, analyzer shutdown/position and process isolation.
  Application compiles; range/overflow/heap-checked wire test passes.

### PGN review follow-up — 2026-10-28

Commit: `a0a925b`.

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

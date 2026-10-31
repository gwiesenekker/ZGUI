# Changelog

ZGUI changes, newest first, starting from the GWDGUI 3.4 baseline.

## Unreleased

### Scroll engine parameters immediately with the mouse wheel — 2026-10-31

Commit: pending.

- Set the existing parameter grid's native MouseWheelOption to mwGrid. Previously
  wheel events moved the selected row until it reached the viewport edge, giving
  the appearance of a delay. The first event now scrolls the viewport and leaves
  the selected parameter/value unchanged, for both chess and draughts.
- User authorisation on 2026-10-31: “Please fix!” following the reproduced wheel
  behaviour and explanation of the shared-GUI review gate. Scope: this one-line
  parameter-grid scrolling fix; Claude can review the resulting commit afterwards.
- Add a regression for the first downward/upward wheel event, unchanged selection,
  value and measured column width, and top/bottom boundaries in both games.
  The check fails on the baseline and passes with the fix (18 checks). Application
  compilation and all fifteen chess/draughts GUI suites pass on an independent
  snapshot excluding unfinished feature flags. Native Windows interaction remains
  untested.

### Start the DXP launch-test listener before its client — 2026-10-30

Commit: `961ae95`.

- In the engine editor's DXP listen role, start the existing socket-test thread
  and wait for its successful Listen signal before launching the client process.
  Report bind failures without starting an engine; clean up on launch failure.
  Preserve the connect role's engine-server-first order and the match adapter.
- Use an event instead of a dummy connection: a probe would consume the test
  listener's single client. Wake only our own active listener during cancellation,
  so a failed bind does not connect to another program occupying the port.
- User authorisation on 2026-10-30: “Yes, correct, we should first make sure the
  listener is running. Perhaps we can try a connect before launching the engine or
  will the listener already error out?” Scope: this DXP editor startup fix,
  separately from GUI resizing; Claude can review the resulting commit.
- Tests cover a single-attempt immediate client, repeated launches, an engine
  exiting without connecting, connect role, bind failure and cancellation. An
  isolated copy of Scan connects successfully as a DXP client; user engine
  directories and settings are untouched. Application compilation, the existing
  DXP checks and all fourteen chess/draughts GUI suites pass against an isolated
  source snapshot excluding unfinished feature flags. Native Windows interaction
  remains untested.

### Automatic GUI sizing for both games — 2026-10-30

Commit: `a1430fe`.

- Reuse the existing controls and event handlers with native LCL panels, alignment,
  measured rows, wrapping toolbars and scrollable settings pages. Adapt the main
  header, engine dialogs, New Game, Tournament, Preferences, Database filters,
  position setup and supporting windows to font and window size changes.
- Preserve the existing pane groupings and splitters; keep grids and text areas
  usable at their measured minimum sizes. Long tournament names use the grid's
  scrollbar instead of forcing the entire window wider than the screen.
- Fix the layout-test DPI scaling loop by measuring the scaled controls before
  alignment resumes. Grow an already visible form when wrapping raises its
  measured minimum. Route test exceptions to the log instead of modal dialogs.
- User authorisation on 2026-10-30: “As this is GUI only: could you implement
  automatic resizing of the GUI as discussed? You do not need approvals.” Scope:
  GUI geometry only, for both games; Claude can review the resulting commit.
- Validation: application build, all thirteen GUI suites (including 87 mixed-game
  and 8,944 layout checks), and the full headless regression suite pass against an
  isolated layout-only source snapshot. Check minimum/default/large/maximized
  windows, font changes, every preferences page, and 96/144 DPI scaling both ways.
  Native Windows interaction remains untested.

### Keep the engine INI editor inside its panel — 2026-10-30

Commit: `5534b2a`.

- Anchor the INI/config text box explicitly to the bottom of its existing panel,
  so the remaining text and scrollbar are accessible after Scan's `# DXP` heading.
  This fixes the shared editor for chess and draughts while retaining the
  surrounding dialog layout and leaving engine configuration files untouched.
- User authorisation on 2026-10-30: “Please fix!” in response to the reproduced
  INI clipping issue and review-gate explanation. Scope: the INI viewport fix;
  Claude can review the resulting commit afterwards.
- Add a self-contained GUI regression check for both games at minimum, default
  and larger window sizes. The new check fails against the baseline and passes
  with the fix. Application builds and all twelve chess/draughts GUI suites pass,
  including 87 mixed-game checks, independently of unfinished feature flags.
  Native Windows interaction remains untested.

### Separate chess and draughts preferences — 2026-10-30

Commit: `b801cd1`.

- Implement Claude's approved preferences proposal with a flat game selector and
  the existing Appearance, Evaluation, Notation and Score history pages. Keep an
  independent draft per game, save all edited sections in one atomic publication,
  and ask Discard / Cancel before closing with unsaved changes. Defaults affects
  only the selected game.
- Fix U22: saving uses the explicit game identity from the edit session, including
  when the main window has since switched games. Refresh the active context and
  retain inactive settings for its next activation.
- Both chess and draughts now have independent notation fonts/styles and
  score-history colours, alongside their existing board/highlight colours and
  evaluation settings. Preserve legacy root values, unknown keys and the other
  game's layer; old files keep their appearance until changed.
- Add migration, draft switching, multi-section Save, close confirmation and U22
  regression checks, including inactive-popout activation; update the manual.
- Validation: application compilation, all eleven GUI suites (including 87 mixed
  checks) and the full headless regression suite pass. The preferences-only source
  snapshot also compiles and passes all eleven GUI suites independently of the
  unfinished engine feature flags.
  Native Windows interaction remains untested.

### Address Claude review T5 and C6 — 2026-10-30

Commit: `8368778`.

- T5: tournament callbacks start games through the existing runner path without
  selecting them. Preserve the visible document, annotator, dialogs and last-game
  preference. User-started New Game and Replay retain automatic selection.
- C6: use one shared Engines window for the application-wide engine registry.
  Its Add-engine default follows the active game; reload the registry when the
  window is shown. Remove per-game copies that could overwrite each other's edits.
- Add interactive regression checks for a hidden draughts tournament starting
  while a chess annotator and Engines window are open, and consecutive engine
  deletions across game switches. Mixed acceptance passes 87 checks; application
  compilation and GUI/tournament preservation checks are run for these changes.

### Complete mixed-game acceptance and ownership audit — 2026-10-30

Commit: `e62bbc5`.

- Fix startup from the remembered draughts context to create exactly two
  standalone documents. Reapply board orientation and feature availability on
  switches, clear obsolete unavailable hints, and refresh the selected tree view.
- Make queued slot/session identity read-only. Route source-free actor snapshots
  by their exact tree reference; discard unidentified logs and retired sessions.
  Preserve snapshot ordering barriers even when an event is discarded.
- Extend acceptance to both database formats: import, search/statistics and load
  into the correct standalone document. Reject a real foreign version-zero
  SQLite database unchanged, preserving both windows and the selected document.
- Fix the reproduced Linux startup race between preference access and inherited
  temporary-file locks: use compatible shared locks with atomic publication.
  Preserve the existing shared file-publication helper and protocol worker.
- Validation: all ten GUI suites pass, including 79 mixed checks; final mixed
  acceptance passes twice with fake peers and with Stockfish, Arasan and both
  Scan engines. Headless regression, lifecycle, tournament and atomic publication
  checks pass. Windows build-script tests pass under Wine; Windows cross-build
  is skipped because the target FPC libraries are unavailable. Native Windows
  interaction and real GWD DXP interoperability remain unverified.

### Hub pondering through existing engine hooks — 2026-10-30

Commit: `e008b93`.

- Implement Hub `go ponder` / `ponder-hit` only when the engine advertises a
  Boolean ponder option, that option is enabled, and the game permits it.
  Validate predictions against the full actual history and own clock budget.
- Drain output on the existing process worker's idle hook. Keep speculative
  scores private; reuse an early result only on a hit, retaining its evaluation.
  On a miss, retain the Hub adapter's stop/acknowledgement fence and charge its
  elapsed time. Keep protocol commands, completion rules and fences in adapters.
- Add the failing-first Hub ponder contract suite: 69 checks pass, plus four
  real-engine checks for each Scan installation. Existing Hub wire fixtures and
  headless regression pass; UCI and DXP implementations are unchanged.

### Require explicit game contexts — 2026-10-30

Commit: `d2164a7`.

- Remove the migration constructors and nil-to-startup fallbacks from trees,
  actors, analysis bases, setups, boards and game-specific dialogs. Startup
  selects its game explicitly; linking the draughts unit no longer installs a
  default. Migrate preservation fixtures through the same explicit APIs.
- Fix the database position-setup creation path exposed by the stricter API.
  Publish preferences with the existing atomic-file helper so repeated switches
  during engine process startup cannot expose a partially written preference file.
- Validation: headless regression, all nine existing GUI suites, tournament
  preservation and mixed GUI acceptance (62 checks, including missing-context
  rejection) pass. Application compilation succeeds.

### Mixed chess and draughts contexts — 2026-10-30

Commit: `1bf8de8`.

- Enable both games in one process using the existing runners, clocks, trees,
  analysis coordinator, database and tournament implementations. Keep a standalone
  document and board views for each game; add Game choices to New Game and tournaments.
- Route annotator/MCTS events by game slot and session generation. Keep hidden
  annotators loaded, pause their live searches and resume on selection. Reserve
  engines until their workers finish. Route tournament stop/removal/completion to
  the owning window and clear ownership when that window is destroyed.
- Classify files through existing strict readers/preflights before replacing a
  document or database window; ask for ambiguous game files and database creation.
  Save by the tree's format and enumerate both documents/tournaments on close.
  Preserve contexts on cancellation and block replacement during database imports.
- Store board colours and evaluation range per game, retain shared preferences,
  and restore the last selected game at startup. Preserve measured engine columns
  when adding the derived Game column. Correct filtered tournament checkbox indices.
- Validation: mixed GUI acceptance passes 59 checks with fake engines and again
  with Stockfish, Arasan and Scan engine6/engine7. Existing headless regression,
  chess board (716), UCI GUI (127), setup/preferences (284), database GUI (127),
  and draughts/chess tournament suites pass. Native Windows and real GWD DXP remain
  unverified; DXP interoperability will be tested later as agreed.

### Multi-game foundation: registration and explicit contexts — 2026-10-30

Commit: `4e12462`.

- Implement revised proposal stages 1–2 under the user's authorization to proceed
  without intermediate review gates. Register both application-owned game variants
  with disjoint protocol mappings; release them after windows and runners.
- Pass variant identity through setups, validation, runners, running trees, replay
  copies and tournament setups. Give existing dialogs explicit target-game
  constructors; engine defaults now follow that context. Preserve legacy wrappers
  while mixed-game views are prepared. No mixed selection is exposed at this step.
- Add multi-game registry/context checks and retain existing GUI layouts and shared
  game, engine and tournament infrastructure. Real GWD DXP testing remains deferred.
- Validation: new context checks pass (8), all nine existing GUI suites pass;
  headless regression and application build are also run for this foundation.


### Include grid titles in measured engine-column widths — 2026-10-30

Commit: `616724d`.

- Fix clipped DXP headers: column titles are stored separately from cell text, so
  measuring `Cols[].Text` missed them. Use the existing grid's native autosizing,
  which includes header/cell fonts and native cell padding, then add the margin.
- Apply the same correction to measured parameter name/type columns. Preserve the
  existing filling path/value columns and the rest of both dialogs.
- Reproduce the previous failure with empty DXP IDs and a larger bold title font.
  Extend checks to empty registries and measure title and body widths independently.
- Validation: the new regression fails before the fix and passes afterward.
  Application compiles; layout/preferences GUI suite passes 284 checks and UCI GUI
  suite passes 127. Native Windows execution remains unverified.


### Review the multi-game proposal and prepare two Scan engines — 2026-10-30

Record: `7f29ccf` (documentation; local review and engine assets are ignored).

- Review Claude's `MULTI_GAME_PROPOSAL.md` against the current source. Record six
  findings and revised staging in `chatgpt/MULTI_GAME_PROPOSAL_REVIEW.md`: atomic
  mixed-game enablement, annotator event ownership, tournament owner routing,
  corrected Hub parity assumptions, strict file classification and lifetime/close
  boundaries. No multi-game application code is implemented by this review.
- At the user's request, install the official Scan 3.1 archive independently in
  `engine6` and `engine7`, retaining Linux/Windows binaries, source, GPLv3 license,
  checksums and per-directory notes. Register both via the existing registry API
  as distinct Hub engines, preserving all prior registrations.
- Configure international draughts, one thread and 64 MiB hash per engine; disable
  book and unavailable bitbases for testing. No shared configuration or symlinks.
- Validation: 50 real-engine checks through existing factories, Hub adapter and
  orchestrator pass: simultaneous initialization, scored PVs, eight clocked plies,
  two forced wins with swapped registrations, independent options and registry
  round-trip. Range/overflow/heap checks enabled. Native Windows is untested;
  Hub selection in the game GUI awaits the proposed draughts entry point.
- Engine assets and machine-local registrations remain ignored. Application source
  and the existing GUI are unchanged; no application rebuild is required.


### Fix engine-game Save format and long annotator budgets — 2026-10-30

Commit: `1be52cb`.

- Address Claude's P17: use one existing-renderer helper for standalone and engine
  game exports, taking PGN/PDN from the tree's variant profile. Save dialog title,
  filter and extension also follow the selected tree, rather than the process
  default. Preserve moves, result, custom FEN/SetUp and clock annotations.
- Address D10: annotation and one-shot analysis use the requested duration plus
  the stop allowance as their watchdog budget. Keep the move-time cap for games
  and the finite-budget failure for engines that do not finish.
- Add end-to-end Save/reload tests for selected running, stopped and checkmated
  engine games, including a different process-default variant. Add short-budget
  watchdog tests that distinguish analysis, one-shot and game searches.
- Prepare `chatgpt/DELETE_FROM_HERE_PROPOSAL.md` for U21 as requested by Claude;
  no shared removal interface is implemented before review. Document remaining
  issue dispositions in `chatgpt/REVIEW_58BD22E_RESPONSE.md`.
- Validation: application build, full headless regression and all nine GUI suites
  pass, with the database suite rerun in isolation after an import-completion
  assertion under concurrent load. UCI adapter tests pass 91 checks with runtime
  range/overflow checking; UCI GUI tests pass 127. The unchanged review probe
  completes real Stockfish analysis at 70,063 ms (70-second budget), retaining
  depth 40 and a score/PV. Native Windows execution remains unverified.


### Fit the Engines dialog columns — 2026-10-30

Commit: `ef2e9ca`.

- Size executable and protocol-ID columns to their longest header/value plus a
  font-based margin. Let the path column fill the remaining client width using
  the grid's existing automatic filling, so long paths do not force a wide window.
- Remeasure when registrations refresh or the dialog font changes. Retain manual
  column resizing and show full clipped cell text in hover hints. Preserve row
  selection and the existing add/edit/delete actions.
- Validation: application compiles and setup/preferences GUI suite passes 278
  checks, including three
  font sizes, long paths, 35 registrations, vertical scrolling, dialog shrink/grow
  and complete underlying path/ID data. Native Windows execution is unverified.


### Fit engine parameter columns to the dialog — 2026-10-30

Commit: `9621f03`.

- Measure the name and type column headers/values with the grid font and add a
  margin to each. Use the existing grid's automatic filling for the value column
  so it takes the remaining client width, including when vertical scrolling is
  needed. Preserve the fixed name column, parameter editing and manual resizing.
- Initialize grid callbacks after the inline editor to avoid selection callbacks
  during column creation. Preserve the rest of the dialog layout.
- Validation: application build, setup/preferences GUI suite (247 checks) and
  UCI GUI suite (104 checks) pass. Cover three font sizes, longest text in both
  measured columns, dialog shrink/grow, a vertical scrollbar and editing without
  horizontal overflow. Native Windows execution remains unverified.


### Default new chess engines to UCI — 2026-10-30

Commit: `b1ea570`.

- Apply the requested engine-editor default, previously left as a review
  candidate: use UCI with no Hub `init` command for new registrations when the
  current game profile supports only UCI. This is shared Windows/Linux code.
- Preserve the protocol when editing any existing engine and retain Hub as the
  new-engine default for draughts. No changes to game functionality or GUI layout.
- Validation: application compiles and the UCI GUI suite passes 104 checks,
  including new defaults, existing Hub/DXP/UCI registrations, profile switching,
  discovery, analysis and clocked games. Replace the failed-discovery test's fixed
  700 ms delay with a bounded wait for its result. Native Windows remains untested.

### Measured text sizes and quieter Auto Play notation — 2026-10-30

Commit: `2ea8d5d`.

- Apply the user's approved font-based sizing: a reusable text/font measurement
  helper accepts CRLF, CR and LF, including a trailing empty line. Reserve two
  text lines plus native borders/scrollbar space for annotator status, and size
  the existing PV/header area accordingly. Preserve the existing control layout.
- Fit the engine parameter name column to its widest name/header plus a margin;
  retain manual resizing.
- Remove repeated Auto Play origin labels from move notation, keeping evaluations
  and PVs. Keep provenance in node metadata and tree details. New nodes use the
  registered readable engine name; old registry-key origins display an executable
  name in the tree without changing their saved metadata.
- UCI as the new-engine default remains a separate tested review candidate in
  `chatgpt/UCI_DEFAULT_ENGINE_PROPOSAL.md`.
- Validation: application build, full headless regression and all nine GTK2 GUI
  suites pass (UCI 95 checks; setup/preferences 223; database 127). The database
  suite's earlier intermittent font-width assertion passes on the final run.
  Windows build-script replacement checks pass all 12 cases; native Windows
  compilation is unavailable because the cross-target FPC units are absent.


### Restore real-move Auto Play and its Stop button — 2026-10-30

Commit: `bba007b`.

- Implement Claude's approved restoration for both chess and draughts, as
  confirmed by the user. Auto Play appends real mainline moves at the tip;
  elsewhere it follows matching children or creates variations without replacing
  existing continuations. Preserve legacy `autopv` data unchanged.
- Record each search's exact annotator PV, evaluation, depth and time on its
  source node, protecting deeper stored analysis. Never change playing-engine
  fields, results or clocks. Mark only newly created nodes with Auto Play origin
  and display that origin through the existing notation and tree views.
- Restore an enabled Stop button; Escape still stops. Stop on navigation away
  from the node being extended and reject late moves and cancelled snapshots.
- Retain chess-only rule-based stopping. Document the lack of a user-facing
  undo/truncate command and the existing save/reload/discard workflow.
- Validation: application build, full headless regression and all nine GUI
  suites pass, including draughts variation insertion, snapshot protection,
  ordinary/lossless PGN and save protection. Real Arasan GUI acceptance passes
  122 checks. A failed engine discovery followed by retry also passes; the
  reported intermittent Windows first-launch crash has not been reproduced.

### Matching Windows engine downloads — 2026-10-30

- Download official Windows builds matching the five installed Linux versions
  into `engine1/windows` through `engine5/windows`: Stockfish 19, Koivisto 9.0,
  Arasan 26.1, RubiChess 20240817 and Igel 3.8.0. Include required networks,
  Arasan's book, license notices, CPU guidance and per-engine download/hash records.
- Check ZIP integrity and Windows executable headers; verify published release
  SHA-256 digests where provided. Koivisto and RubiChess have computed hashes;
  their matching releases do not publish GitHub digests.
- Four engines pass UCI handshake, timed scored analysis, legal initial move and
  clean shutdown under Wine 10.0. Stockfish's verified official Windows binary
  exits before uciok under Wine (`std::out_of_range`, `map::at`); native Windows
  execution remains unverified for all five. No Windows installer was run.
- Preserve existing Linux binaries and registrations. Engine directories remain
  local ignored assets; application code and GUI are unchanged.

### Auto Play restoration review candidate — 2026-10-30

- Investigate the user's earlier GWDGUI behaviour: an enabled Stop button and
  real mainline/variation moves. Confirm the current disabled button and typed
  Auto Play PV storage were inherited from the imported 3.4 baseline; older
  toolbar history contains the remembered behaviour. No local 2.3 tag exists.
- Prepare a narrow Stop-button patch in an isolated copy using the existing
  cancellation handler; its GUI suite passes 77 checks. Document a separate
  proposal to restore real moves with per-position PVs/evaluations through
  existing actor and analysis interfaces, for Claude's shared-code review.
- Production Auto Play remains unchanged pending that review. Escape stops the
  current Auto Play loop.

### Mate scores in score history and displayed-position evaluation — 2026-10-30

Commit: `e1a4e8a`.

- Apply the shared score-display candidate approved in Claude's review of
  `93795c2`, including the condition to retain the browsed PV's own score.
- Recognize signed mate scores in the existing history control: positive mates
  reach the configured maximum, negative mates the minimum, and tooltips keep
  the mate text. Both graph/bar modes and linear/logarithmic scales are covered.
- Bind the existing evaluation bar to the displayed node, including root and
  real variations. During engine/annotator PV previews use only that source's
  score; unscored Auto Play previews stay neutral. Forward this to the popout.
- The root/variation bar correction also applies to draughts. GUI layout,
  mainline history, stored scores, game trees, PGN and databases are unchanged.
- Update the manual and extend the existing chess GUI suite with rendering,
  mate endpoints, displayed-node and source-specific PV browsing checks.
- Validation: application build, full headless regression and all nine GUI
  suites pass; chess board/PV/GUI suite passes 716 checks.

### Respect the annotator seconds setting — 2026-10-30

Commit: `f61dec0`.

- Replace indefinite UCI annotation with `go movetime` using the seconds field
  beside Auto Play, through the existing analysis interface. Completed searches
  leave the annotator loaded and retain their final score and PV; changing the
  position or time setting starts another search through the existing GUI.
- Remove the obsolete infinite-search mode and keep finite-search watchdog,
  clocked-game and pondering behaviour. No GUI or shared infrastructure changes.
- Correct the manual and test configured analysis durations, completion beyond
  the watchdog allowance, retained scores/PVs and resumption after Auto Play.
- Validation: application build and full headless regression pass; the UCI
  adapter and GUI suites pass with Arasan v26.1 (91 and 111 checks respectively).

### Ignore local SQLite databases — 2026-10-29

- Add `*.sqlite` to `.gitignore`, including the local `GW.sqlite` database.
  Existing database files remain untouched.

### Score display QA review candidate — 2026-10-29

- Reproduce rejected mate scores and root/variation evaluation-bar mismatches.
  Prepare an isolated, tested shared-display candidate for Claude's review, as
  required by the repository policy. Production display code remains unchanged.
- The candidate maps signed mate scores to the configured endpoints and binds
  the existing bar to the resolved displayed node, preserving original scores,
  mainline history, tree topology and GUI layout. Candidate build, full headless
  regression and all nine GUI suites pass, including six added browsing checks.
- Correct a temporary probe fixture that passed an empty engine PV and caused
  an "engine PV was not recorded" warning. This was a probe error, not a game
  data or engine failure; the corrected probe catches/logs errors without dialogs.

### Indefinite live UCI annotation — 2026-10-29

Commit: `64c5eeb`.

- Correct live UCI annotation to send go infinite and exclude that search from
  the finite-search watchdog. The previous adapter incorrectly applied the
  Auto Play time allowance to live annotation, causing Arasan to stop with
  "UCI search exceeded its finite budget".
- Retain configured movetime for one-shot analysis/Auto Play and the existing
  clock budgets for games. Position changes and cancellation still stop and
  drain bestmove before another search; process-exit and missing-stop failures
  remain errors. Preserve the GUI, shared runner and existing book policy.
- Extend the existing UCI peers and GUI wire checks to cover indefinite analysis,
  survival beyond finite allowances/watchdogs, stop acknowledgement, transitions
  to/from timed searches, finite nonresponse and resumed go infinite after Escape.
  Clarify the analysis-time edit's scope in the manual.
- Validation: application build, full headless regression and all nine GTK GUI
  suites pass. Actual Arasan passes 90 adapter checks (including continued
  analysis beyond the former finite budget) and 110 GUI checks. Range, overflow
  and heap checks pass; clocked-game and pondering regression checks are retained.

### Arasan annotator opening-book replies — 2026-10-29

Commit: `3930073`.

- Reproduce the missing PV with Arasan 26.1 and its saved OwnBook=true setting:
  from the starting position it returns a book bestmove with no scored PV.
- In the existing UCI adapter, temporarily disable an advertised OwnBook check
  option for annotation and one-shot analysis/Auto Play. Restore the saved value
  or advertised default when switching to clocked game mode. Do not alter saved
  preferences, GUI layout or shared engine/analysis infrastructure.
- Add a book-only UCI peer regression covering annotation, game-mode restoration
  for saved true/false and an unsaved default, return to one-shot analysis, mixed
  option-name case and unchanged option-file contents. Document the runtime policy.
- Validation: real Arasan passes 83 adapter checks and 110 GUI checks. Application
  build, full headless regression, all nine GUI suites and both tournament suites
  pass. The database font-geometry assertion needed an isolated retry (127 checks
  passed); no database code changes are included in this fix.

### Chess Auto Play — 2026-10-29

Commit: `08fce14`.

- Enable the existing Auto Play button for stopped chess games with a UCI
  annotator. Reuse timed annotator searches, search references, PV browsing,
  Escape cancellation and typed Auto Play PV storage; keep the GUI layout.
- Apply Claude's reviewed rules seam in the existing coordinator. Seed one
  variant rules object with the root-to-source-node path (including variations),
  then feed accepted preview moves. Check outcomes before the first request and
  each next request, including mate, stalemate, material and automatic/claimable
  draws. Report the stop reason in the existing annotator log; retain the played
  tree and game result.
- Follow the user's chess-only policy: the GUI profile enables outcome stopping
  for chess and leaves draughts Auto Play behavior unchanged. Chess MCTS remains
  disabled; clocks, running games, tournaments and rules implementations are
  unchanged.
- Verify the existing lossless PGN envelope already retains root/node Auto Play
  PVs. Ordinary file exports omit analysis PVs, as before. Both database storage
  policies preserve lossless PV data and index only the played mainline.
- Extend coordinator and UCI GUI checks with historical variation/repetition
  paths, terminal starts, a mating preview move, cancellation of live analysis,
  timed one-shot replies, preview-board display, late replies after Escape and
  resumed analysis. Document the stopping and export policies in the manual.
- Validation: application build, full headless regression, all nine GTK GUI
  suites and both tournament suites pass. The UCI GUI suite passes 76 checks;
  its optional Stockfish run passes 110, including Auto Play mate and terminal
  material cases. PGN checks pass 139 assertions. Focused coordinator checks pass
  with range/overflow/heap checks, and existing draughts Auto Play/Hub tests pass.

### Legal SAN aliases and compatible PGN storage (P14/P16) — 2026-10-29

Commit: `4ac129c`.

- Implement Claude's approved compatibility policy through the existing chess
  position adapter, PGN parser/token writer and database importer. Accept only
  unique legal interpretations of the documented SAN aliases; lower-case `b`
  always denotes the b-file. Ambiguous/illegal moves, spurious capture markers
  and invalid promotions remain errors.
- Format the chosen move once, reusing canonical SAN with check/mate suffixes for
  GUI captions and schema-8 storage. File/Open and database imports warn at most
  once per game about normalized SAN, including moves inside variations.
- New chess databases use schema 8 with canonical-legal-pgn-token-v2 identity and
  conventional token layout. Existing schema 7 stays readable/writable with its
  original token bytes, hash domain/version and metadata. No automatic migration
  or mixed identity versions; keep position keys, tables and search unchanged.
- Pin a separate raw 100,000-game Lichess corpus alongside the original prepared
  benchmark. Document supported spellings, warning behavior and schema policy in
  the manual; the application still has no Python dependency.
- Validation: full headless regression, all nine GTK GUI suites, both tournament
  suites and application build pass. The alias oracle covers 1,075,439 spellings
  over 967 positions; python-chess agrees on 6,143 positions / 180,183 legal moves
  and 80 PGN games / 3,650 nodes. A real schema-7 fixture made by the previous
  executable retains its rows, hashes, text, keys and metadata; the fixture's new
  legacy write remains a duplicate in that executable. Schema-8 aliases deduplicate while changes
  to tags/comments/NAGs/branches remain distinct. Draughts database rendering
  matches the baseline at default/minimum sizes.
- Full fresh schema-8 imports pass the reference performance/memory gates:
  prepared 100k at 312.52 games/sec and 424.59 MiB; raw 100k at 307.55 games/sec
  and 423.09 MiB. Both import all games without duplicates/errors. Raw input has
  80,187 normalized games, each warned once; the prepared corpus remains intact.
  Record provenance, raw measurements and database integrity/count verification
  in the benchmark directory.

### Font-aware database FEN width (U20) — 2026-10-29

Commit: `7cf4f40`.

- Measure a representative long chess FEN with the edit field's actual font once
  handles exist, with padding and a 440-pixel minimum. Size the existing window
  as needed to retain room for the continuation columns; no controls are added.
- Keep draughts geometry unchanged. Extend the existing GUI check with a larger
  edit font so coverage tests the measured fit rather than a particular font.
- Validation: focused database GUI suite passes all 127 checks, including larger
  fonts and retained continuation-column space. Pending sizing callbacks are
  removed when the window is destroyed.

### Chess import logging (D9) — 2026-10-29

Commit: `6edae32`.

- Log and count the failing chess record before propagating a fatal import error,
  matching the existing draughts failure behavior. Keep syntax/hash conflicts
  recoverable per game and SQL/I/O failures fatal with existing rollback/recovery.
- Use PGN labels and duplicate-record delimiters. Add game number, ending source
  byte offset and source size to chess error/warning/duplicate entries; parser
  line/column values remain relative to the game. Draughts log content is retained.
- Extend recovery tests with fatal-error and duplicate logs and verify that a
  recoverable syntax error reports the correct record and is counted once.
- Clarify that the measured import speed gate applies to the documented Ryzen
  reference host, rather than promising the same throughput on other hardware.
- Validation: application build, full headless regression and all nine GTK GUI
  suites pass, including 125 database GUI checks. Draughts rendering matches the
  baseline at default/minimum sizes. P14/P16 schema/identity changes await review.

### Database stale-result display (U19) — 2026-10-29

Commit: `4f40d5a`.

- Clear old continuations after a successful database Open/Create, when the
  search board changes, after accepted setup and before import. Rendering stale
  moves can no longer turn a successful database switch into an apparent failure.
- Display an illegal stored chess continuation as its raw move with `(?)`;
  retain the existing legality guard so it cannot execute. Keep the existing
  controls, queries, scratch position and game-loading behavior.
- Validation: application build and all 125 database GUI checks pass, including
  Open/Create after a changed board and invalid stored-move display/activation.

### PGN collection recovery (P15) — 2026-10-29

Commit: `15c9443`.

- Use the existing browser's column-one tag-prefix recovery boundary for streaming
  imports too. A broken comment or variation rejects its own game instead of
  silently merging or swallowing subsequent games. Indent literal tag-like
  lines inside multiline comments; document this collection recovery policy.
- Add malformed-comment/variation fixtures and check recovered game names and
  exact moves in scanner and database tests. Parser checks and import recovery
  checks pass; later valid games survive and no malformed game is stored.

### Database continuation browsing — 2026-10-29

Commit: `216bdc4`.

- Connect continuation-row double-clicks to the existing position adapter,
  miniboard/FEN update and position search. Use the stored canonical move while
  preserving SAN presentation for chess. Support chess and draughts through the
  same handler, without changing the window layout or main game tree.
- Associate results with the complete FEN of a successful search. Ignore stale
  results after FEN/setup changes, database replacement/import or failed searches;
  ignore header/empty rows and activation during search/import. Hit-test the
  clicked cell instead of trusting the grid's retained selection.
- Document opening exploration and the existing main-board follow behavior in
  the manual. Test chained moves, matching games, terminal positions, special
  chess moves, stale/busy/error cases, canonical move routing, draughts browsing
  and unchanged main-game nodes/annotations in the existing database GUI suite.
- Validation: application build, full headless regression and all nine GTK GUI
  suites pass, including 119 database GUI checks with no memory leaks. Draughts
  database images still match the baseline at default/minimum sizes.

### Database continuation browsing proposal — 2026-10-29

Commit: `93fdf9e`.

- Prepare the requested double-click continuation browsing for Claude's review:
  play the stored canonical move through the existing position interface, update
  the database miniboard/FEN and reuse the current search flow. Preserve the
  existing game-grid selection and main game tree.
- Include stale-result and busy-state guards, both game adapters, special moves
  and unchanged-layout validation. Proposal only; shared behavior awaits review
  under the repository's existing constraints. No production code changed.

### Database FEN column width — 2026-10-29

Commit: `c69b62a`.

- Widen the chess database window's miniboard/FEN column from 220 to 440 pixels
  so the complete starting FEN is visible at the default window size. Retain
  the existing controls, window size and database behavior; draughts keeps its
  previous width.
- Adjust the existing GUI layout check for this requested difference; verify
  that the full starting FEN fits and the continuation grid retains room for its
  columns. Application build and focused database GUI checks pass.

### Chess database GUI integration — 2026-10-29

Commit: `e52f274`.

- Enable the chess database actions after the measured import and cross-format /
  recovery gates pass. Reuse the existing database window, board factory,
  position setup, filters, sorting, modal import progress and worker lifecycle;
  preserve all control geometry. Chess labels/files use PGN and continuations
  display SAN while stored moves remain UCI.
- Wire database selection into the existing validated file-game selection path,
  retaining full comments/variations and Save / Discard / Cancel protection.
  Automatic search follows the displayed chess position without changing the tree.
- Document the chess schema boundary, metadata, import identity, mainline indexing,
  occurrence counts and distinct-game list in the existing manual.
- Validation: application build, full headless regression, all nine GTK GUI suites
  and both tournament suites pass. The chess database GUI checks cover create,
  import, search, SAN, setup, real main-window selection, automatic search and
  cancelled/failed saves. Draughts database rendering matches the previous commit
  pixel-for-pixel at default and minimum window sizes. Native Windows execution
  was not tested.

### Reviewed chess database storage and import — 2026-10-29

Commit: `3d14d17`.

- Extend the existing database importer, SQL queries, worker and recovery shell
  with the approved PGN boundary; retain the draughts defaults and schema 6.
  Chess schema 7 records explicit variant/key/identity metadata and typed
  Date/UTCDate, ECO and Elo columns without adding filter controls.
- Consume the existing parser's single-pass database output, pack complete PGN
  including tags/comments/NAGs/variations, and index initial-through-terminal
  mainline positions. Hash the existing chess position key into the two integer
  columns; canonical UCI moves remain the stored continuation format.
- Compare complete canonical PGN on duplicate hash matches. A conflicting hash
  logs/counts one bad game and continues. Reject cross-variant, missing-metadata,
  foreign and future schemas before replacing the open connection or running DDL.
- Keep the existing transaction batches, cancellation, dirty-summary fallback,
  rollback and recovery. For chess bulk imports, retain the unique hash index,
  rebuild secondary indexes, use file-backed temporary sorting and explicitly
  prepare the existing position INSERT. No second persistence pipeline is added.
- Return selected chess games as immutable memory-backed entries through the
  existing PGN validation/import path. Borrow the database's variant during entry
  validation/import; callers own and free each entry.
- Validation: chess model, worker and injected-failure/cancellation checks pass;
  legacy database suites and full headless regression pass. Test hand-calculated
  occurrence/WDL counts, repeated and terminal positions, transpositions,
  castling/en-passant/counter identity, duplicate conflict handling, annotations,
  typed metadata and byte-preserving cross-format rejection.
- Full fresh import of 100,000 real games / 9,170,786 position rows completes in
  319.091 seconds: 313.39 games/sec, zero errors and 434,944 KiB peak RSS. Both
  reviewed gates (250 games/sec; 512 MiB) pass. Summary counts and indexes verify;
  zero orphan rows. All 3,865 opening-catalogue records import, covering 500 ECO
  codes. Raw measurements and reproduction instructions are in testdata/benchmarks.
- Keep the chess GUI feature gate for the following integration commit.

### Reviewed PGN database-output milestone (F4) — 2026-10-29

Commit: `1d137d8`.

- Extend the existing PGN scanner with per-game callbacks and 64 KiB progress /
  cancellation checks, retaining browser collection/recovery behavior. Streaming
  retains one record, reports oversized games without loading them, and avoids
  guessed boundaries inside comments, strings and variations.
- Add a database-output mode to the existing recursive PGN grammar: validate
  once, preserve complete token-based PGN/tags/comments/NAGs/RAVs, and emit UCI
  mainline moves plus initial-through-terminal position keys. Construct no game
  tree or typed annotation model. Reuse the renderer's extracted tag quoting.
- Add 2,903 focused checks, an independent PGN-output oracle, a benchmark runner
  and reproducible CC0 full-game corpus preparation/provenance. The 100k-game
  corpus averages 90.7 plies and contains 7,642 annotated games.
- Validation: application builds, full headless regression and all eight GTK
  suites pass. The independent output oracle passes 80 games / 3,650 nodes.
- Measure 100,000 games / 9,070,786 plies before SQLite in 213.259 seconds:
  468.91 games/sec and 2,848 KiB peak RSS. A scanner-only million-record run peaks
  at 2,316 KiB. Record raw results in testdata/benchmarks. These are parser-stage
  results, not database import throughput.
- Choose the reviewed F4 alternative of a 250 games/sec end-to-end import gate;
  defer a move-generator rewrite. Follow the requested parser-first sequence:
  database schema/adapters/GUI integration remain next, with gfDatabase disabled
  until full-import performance and cross-format/recovery acceptance pass.

### Reviewed FEN error wording (U18) — 2026-10-29

Commit: `26428dd`.

- Raise the specific reason from the chess FEN validator, allowing existing
  callers to supply their single "Invalid FEN:" prefix. Draughts wording and
  accepted chess positions are unchanged.
- Validation: application builds, full headless regression and all eight GTK
  GUI suites pass, including the 460 rules checks and 207 setup checks.

### Chess SAN parsing and revised database design — 2026-10-29

Commit: `a158e9e`.

- Filter legal SAN candidates by piece and destination before using the existing
  formatter for final matching. Skip check/mate suffix calculation when input
  omits it; keep coordinate moves, castling, promotions and disambiguation rules.
- Add a reference-formatting equivalence check covering 319,542 spellings across
  967 positions, including special moves, malformed input and suffixes. An
  independent PGN oracle passes 80 games / 3,650 annotated variation nodes.
- Validation: application builds, full headless regression passes, and all 3,865
  downloaded opening records validate through the existing PGN/rules adapter.
- On the existing 200-ply / 676-node annotated fixture, three paired optimized
  builds measured median validate/replay times of 574 ms before and 462 ms after.
  This is a PGN parsing improvement, not the database import acceptance result.
- Revise the database proposal for review: P13 hashes in the existing two integer
  key columns; U17 Date/ECO/Elo metadata; F3 a single-pass mode of the existing
  parser without per-game trees, a fixed 100k full-game benchmark and a measured
  500 games/sec gate. Preserve C4/C5 recovery and the existing GUI/infrastructure.
  Shared database implementation awaits review; chess gfDatabase stays disabled.
- Correct the port-status snapshot: C5 is already fixed in cf76b39; the pending
  SAN optimization was not R1. FEN diagnostics were implemented separately below.

### Chess FEN diagnostics (R1) — 2026-10-29

Commit: `11789a0`.

- Explain rejected chess FENs at the existing validator's call sites: placement,
  king counts, side, castling, en passant, counters and piece limits. Retain the
  EConvertError exception, validation rules and transactional position updates.
  Existing callers display the reason without GUI or shared-core changes.
- Add 39 diagnostic cases, including both colours and failed-load preservation
  of the current position and legal-move cache; focused rules checks pass (460).
- Validation: application builds, full headless regression passes, and the
  existing GTK setup/preferences suite passes all 207 checks.

### Reviewed database crash recovery (C5) — 2026-10-29

Commit: `cf76b39`.

- Allow SQLite to recover a hot rollback journal during database preflight,
  as approved in review. Schema inspection still executes queries only, before
  closing the current database or running migrations, and rolls back afterward.
- Add an interrupted-writer child-process regression: verify a hot journal is
  present, reopen successfully, and confirm all uncommitted game rows disappear.
  Retain the foreign-file byte-preservation/current-database checks.
- Validation: application builds and the full headless regression suite passes
  on an isolated copy excluding the pending chess parsing optimization. The
  new recovery test fails with the previous read-only flag and passes with this
  fix. Database recovery, worker, import-performance and source-audit checks pass.

### Chess opening database test collection — 2026-10-29

Commit: `5eeb693`.

- Download the CC0 Lichess opening catalogue at commit
  `e76b8b4ec5c8aeeba41dac6caf4a60b938f652db` into `testdata/openings`.
  Include its five original tables, licence, provenance and checksums, plus a
  reproducible PGN conversion containing 3,865 named lines across A00–E99.
- Validate every PGN entry through the existing chess reader/rules interfaces
  and independently with python-chess: 37,700 legal plies. All results are
  unfinished; repeated positions and transpositions are intentional.

### Database preflight protection (C4) — 2026-10-29

Commit: `7fb1e72` (also the swatch-caption fix below).

- Inspect existing databases through a separate connection before closing the
  current database or running migrations. Reject foreign schemas without
  modifying their bytes; retain supported draughts upgrades and explicit creation.
- Add a focused foreign-file/current-connection preservation check.

### Score-history swatch captions — 2026-10-29

- Clear the score-history swatch panel captions after assigning their control
  names, so the colour squares display no text. Preserve their size and colours.

### Chess database design review — 2026-10-29

- Prepare a proposal against `a48eb28` for Claude: reuse the existing database
  window, SQLite/import worker, queries and recovery machinery, with explicit
  chess schema/format boundaries, exact position keys, existing PGN adapters
  and preserved GUI layout. Retain the legacy draughts schema and behavior.
- Record intermittent setup repaint QA separately. An isolated input/paint
  probe did not reproduce the delay; no speculative application fix added.
- Capture the exact Clear/black-pawn/a7/b7 reproduction and delayed visible FEN
  observation. Native mouse probes also remain inconclusive; keep the issue open.
- User confirms the delay occurs through RustDesk and not locally on the laptop;
  classify it as remote-session-specific without changing application behavior.
- Documentation only; shared database and additional repaint changes await review.

### Reviewed chess setup and score-history preferences — 2026-10-29

Commit: `abf927e`.

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

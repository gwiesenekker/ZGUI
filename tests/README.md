# Regression Checks

Run the quick regression sweep from the project root:

```sh
tests/run_regression_checks.sh
```

The script compiles each standalone Pascal check into
`${TMPDIR:-/tmp}/gwdgui-regression-checks` and then runs it. This keeps new
compiled test binaries and units out of the source tree.

Current checks:

- `board_regression_check.pas`
- `analyzer_runner_shutdown_check.pas`
- `analyzer_position_check.pas` (self-contained fake Hub engine; analysis,
  MCTS, terminal positions and one-shot searches while changing positions)
- `hub_search_fence_check.pas` (slow/missing stop acknowledgements and safe
  rejection of engine reuse after synchronization fails)
- `pdn_regression_check.pas`
- `game_tree_pdn_filter_check.pas`
- `game_tree_actor_check.pas`
- `game_preservation_check.pas` (variation storage and game-content preservation)
- `source_audit_check.sh`

The sweep also compiles `running_game_lifecycle_check.pas` directly with FPC.
It exercises the extracted running-game/message units and real runners without
Lazarus/LCL or a display. Run it separately with
`bash tests/run_lifecycle_checks.sh`. This is also a dependency check: importing
these units must not pull in the main form or setup dialog. The source audit
needs ripgrep.

Run `bash tests/run_gui_checks.sh` with Lazarus's GTK2 widgetset and an X display
to exercise the actual main form without showing its window. It verifies that
PDN comments/variations and FEN-only boards survive starting, selecting, stopping
and removing human games. Build output and preference files stay in `/tmp`.

`game_tree_topology_check` verifies parent chains, variation attachment, legal
board replay, failed-replay isolation, trimming and Black-start numbering.
The topology check also covers shared nested nodes, identity and analysis across
refreshes, and trimming one path without deleting another path's subtree. The
preservation check verifies nested PDN structure over three save/load cycles.
The GTK check also clicks nested moves and branch-opening parentheses, follows
the selected branch with Left/Right, compares the displayed board with legal
replay, and asserts that navigation does not mutate the exported tree.
The topology check also verifies that replacing, trimming or clearing moves
cannot transfer their analysis or clocks to another node, while unchanged and
shared nodes retain their metadata through refreshes and path-index changes.
The GTK check also verifies read-only standalone and running-game exports,
including event-name overrides and preservation of model content and revision.
The lifecycle check also sends illegal and stale duplicate human commands to a
real runner, verifies rejection without game failure, and continues legal play
without resetting the human clock.
`socket_disconnect_check` tests broken Unix sockets in isolated subprocesses,
verifying per-socket SIGPIPE protection without changing the application's
global signal disposition. It reports a skip on Windows.

Run `bash tests/run_dxp_checks.sh` with local TCP access to exercise the real DXP
adapter and orchestrator against a self-contained fake peer. It verifies that
win/draw claims cannot award results while resignations retain their meaning
for both colours. Output and executables stay in `/tmp/gwdgui-dxp-checks`.
The DXP check also disconnects the peer immediately after GAMEACC, verifying
prompt error detection, unchanged game state and safe shutdown.

`engine_clock_check` uses a self-contained fake Hub engine to check clock-derived
deadlines, both colours' time losses, increment timing, stopping/fencing and reuse
after a timed-out search. After the regular sweep, run
`/tmp/gwdgui-regression-checks/engine_clock_check --long-check` to verify that a
real 61-second search succeeds with a two-minute clock. The DXP integration
check also tests a silent peer's clock deadline and loss on time.

Run `bash tests/run_tournament_checks.sh` with GTK2 and an X display for the
hidden tournament-form regressions. They cover stale completion callbacks,
manual overrides, rescheduling and pairing actions during pending shutdown.
All generated binaries, preference files and fixtures stay outside the repo.
The tournament checks also cover failed-load isolation, autosave recovery in a
fresh form, stable PDN paths, unnamed recovery files and failure/retry behavior.
`atomic_file_check` verifies replacement and cleanup after a failed atomic save.

`main_form_boundaries_check` runs as part of `run_gui_checks.sh`. Before the
main-form extraction it characterizes actual source/target capture clicks,
all-square board flipping via the keyboard, cancel/decline replacement prompts,
and preservation when switching from a standalone board to a running game.
Its self-contained fake Hub engine exercises Auto Play on a stopped historical
node, late replies after Stop, and MCTS open/close/reopen with queued shutdown.
Test-only seams expose queue delivery and current runner/search identities; the
capture chooser test operates its actual list and buttons. The existing GTK
suites remain intact.
The lifecycle check also counts queued snapshot destruction and verifies that
running games own independent setup definitions, reservations and snapshots.

`move_interaction_check.pas` covers legal source/target selection, capture ordering,
explicit same-target capture choices, selection clearing, routing between
mainline, variation and live runner moves,
and last-move/PV highlight data.

`displayed_position_check.pas` covers selected nested paths, temporary preview
replay and atomic failure, inactive-game projection, cursor fallback and
revision-scoped replay caching through nested display refreshes.

`notation_presentation_check.pas` checks presenter text/ranges against the PDN
renderer for every filter combination, capture captions and label invalidation.
It also covers nested branch/PV hit targets, selection endpoints, preview click
restrictions and automatic/focused highlight ranges. Its export fingerprint
remains pinned independently of display-layout changes.

`notation_analysis_order_check.pas` covers analysis after the played continuation,
empty/tip fallbacks, White/Black starts, all PV source filter combinations and exact
preview base/ranges. The GTK boundary check clicks relocated engine/annotator PVs
in both full-line and first-move-only modes and compares their boards with replay.

The GTK standalone preservation check also exercises memo caret/selection edges
and confirms that hiding/restoring annotations rebuilds ranges, preserves the
selected board and leaves the exported tree unchanged.

`analysis_coordinator_check.pas` covers analysis search identities, active/stale
snapshots, cancellation and queued release, snapshot coalescing keys, independent
analyzer/MCTS restart signatures and historical/terminal analysis policy. It also
checks Auto Play historical-node attachment, command preparation/acceptance,
preview accumulation, rejected targets and stop/restart identity fences. PV-state
checks cover copied bases, nested identities/fallbacks, latest-PV selection and
complete display-cache keys. Request/snapshot checks cover cross-game cancellation,
unchanged-position suppression, terminal and transient search eligibility,
snapshot publication targets, stale rejection and transient display isolation.

GTK notation-tree checks cover each model node exactly once in both layouts,
variation headers, selection/expansion retention, game isolation, popup switching
and standard capture captions. Caption traversal is also bounded by node count.

`game_tree_index_check.pas` checks live/stale IDs through repeated structural edits.
`pdn_batch_import_check.pas` compares batch import with the previous validated
per-node path, including nested/invalid variations, metadata, capture aliases,
payload ownership and a 200-ply line with one validation per visited move.

`gui_delivery_check` runs in the GTK suite. It feeds the real GUI consumer full
and live snapshots produced by a human runner, interleaves games and analysis
searches, checks flush-before-completion ordering and the 100-event timer budget,
counts payload destruction, and exercises cancelled searches, removal and form
shutdown. The main-form boundary check injects old analyzer/MCTS completion
notifications while a current runner remains active.

For reproducible opt-in headless performance measurements, run
`bash tests/run_performance_checks.sh`. See [PERFORMANCE.md](PERFORMANCE.md) for
the fixture, timings, output fingerprints, compiler settings and comparison
procedure. These timings are not pass/fail limits in the regression suite.

`help_menu_check` exercises File/Database/Help shortcuts, Quit save/cancel
behavior, opening/reopening the embedded manual, case-insensitive search,
next/previous wraparound, Unicode selection offsets, keyboard controls and
About's embedded commit. It runs in the GTK suite. `build_info_check.py` compiles
generated build data with FPC and checks clean/modified Git identities, source
archives, Unicode/apostrophes and exact manual text, plus the direct IDE fallback.
The headless sweep runs it automatically. Isolated Lazarus builds regenerate
embedded data and rebuild project units so commit/manual changes cannot reuse
stale unit files.

`windows_build_info_check.py` compiles and executes the native Pascal generator
used by the Windows Lazarus pre-build hook. Real clean/dirty repositories,
Unicode source paths/manuals, CRLF conversion, missing Git, nested archives,
stale includes and missing-input failures are checked against the Linux
generator and compiled About/manual output. The headless sweep runs it on the
host; the batch wrapper and Windows IDE still need native Windows validation.

`runner_early_stop_check` repeatedly stops runners before their first execution
and immediately after Start. It verifies actual termination, worker-thread
completion exactly once, and no duplicate on disposal for games and analyzers.
The GUI suite retains real form destruction/stop and annotator reservation checks.

PDN identity checks include nested sibling-board restoration and conflicting
metadata warnings, including the database import log. Board checks cover direct
copy construction, legal capture paths and independent history. The performance
harness also measures parsing and canonical PDN storage (`pdn_storage`).

`performance_archive_check.py` runs the actual benchmark from a Git-less copy,
asserting unknown metadata and successful operations without Git error output.
The Help check accepts the explicit archive identity; build-info tests also guard
against borrowing the identity of an unrelated enclosing repository.

The index regression additionally removes 20,000 synthetic internal nodes and
checks one lazy rebuild per batch, stale/surviving IDs, new nodes added before
rebuilding, and bulk takebacks. It uses work counts, not timing thresholds.

The standalone [notation-control comparison](NOTATION_CONTROLS.md) measures TMemo,
SynEdit and pinned RichMemo with the real presenter/cursor. It is optional and
does not add RichMemo to the production application or the normal GUI suite.

`notation_preferences_check` checks the separate Notation tab, independent bold/
italic controls, Save/Defaults, JSON round trips, legacy/malformed style defaults,
actual highlighter attributes and unchanged UTF-8 selection/tree exports. The GTK
suite runs it. Native Windows remains untested.

`notation_analysis_source_check` verifies explicit source metadata and styles for
identical engine/annotator/Auto Play PVs, empty/White/Black-start games, score and
annotation hiding, and every PV filter combination. The preferences GUI check
also covers separate source colours, legacy migration, font accept/cancel/Save/
Defaults, font JSON validation and native clicks before/after font changes.

## Chess adapter checks

`position_contract_check.pas` also runs the existing abstract contract checks on
`TChessVariant`: transactional FEN loading, cloning, legal/SAN round trips,
trusted replay, square mapping, deterministic random lines and perft. Six
standard perft positions cover castling, en passant, pins and promotions; the
fixture positions also appear in [Stockfish's own perft tests](https://github.com/official-stockfish/Stockfish/blob/master/tests/perft.sh).
Initial-position depth 4 is 197281; the remaining fixtures run through depth
3, with the rook/pawn ending also checked at depth 4.

`chess_position_check.pas` is part of the normal regression sweep. It tests chess
FEN validation, repetition identity, SAN ambiguity (including `B1c3` versus
`b1c3`), all special moves, terminal results and draw claims. It injects chess
into the existing tree/actor and orchestrator, checking replay, checkmate and
both timeout outcomes without changing those units. Chess remains unregistered,
so these tests also verify that draughts stays the application's default.

For range/overflow and heap checks, build the standalone suite with:

```sh
mkdir -p /tmp/zgui-chess-tests
fpc -B -Cr -Co -gl -gh -Fu. -FU/tmp/zgui-chess-tests -FE/tmp/zgui-chess-tests tests/chess_position_check.pas
/tmp/zgui-chess-tests/chess_position_check
```

The optional independent check uses [python-chess](https://github.com/niklasf/python-chess)
(tested reference version: `chess` 1.11.2). Install it in an isolated test
environment, then compile the probe and run:

```sh
fpc -B -Cr -Co -gl -Fu. -FU/tmp/zgui-chess-tests -FE/tmp/zgui-chess-tests tests/chess_oracle_probe.pas
python3 tests/chess_differential_check.py /tmp/zgui-chess-tests/chess_oracle_probe
```

It compares legal move sets, SAN, every child FEN, check status, position keys
and per-side insufficient-material classification on fixed fixtures and 40
seeded random games. It is optional; ZGUI has no python-chess dependency.

Rules reference: [FIDE Laws of Chess](https://handbook.fide.com/chapter/e012023).
The adapter follows the existing automatic-claim contract, including available
claims based on intended moves. Material detection proves standard dead-material
cases conservatively; it does not solve arbitrary dead positions such as locked
pawn fortresses. FEN accepts six fields for orthodox chess, checks local validity
and coherent castling/en-passant state, but does not prove historical reachability.
Chess960 and other variants are outside this adapter.


## PGN syntax foundation

`chess_pgn_lexer_check.pas` runs in the standard headless sweep. Its 1,193
checks cover tag-string escapes, UTF-8/BOM, CR/LF/CRLF source locations,
comments, move numbers, nested variation delimiters, result tokens, numerical
and traditional NAGs, token limits, malformed input and deterministic random
input progress. Run it with the same range/overflow/heap flags shown above,
substituting `chess_pgn_lexer_check.pas` and its executable name.

The scanner supplies tokens only. `chess_pgn_check.pas` exercises the file
adapter through the existing actor/tree: repeated-variation merging, typed
literal comments, NAGs, custom tags/FEN, special moves, results, standard
embedded commands, optional lossless metadata, CP1252 conversion, deferred
multi-game indexing, failed-import identity preservation and metadata ownership.
It also reports a two-pass 200-ply timing. Both suites run in the normal sweep
and can be compiled with `-Cr -Co -gl -gh` for range/overflow/heap checks.

`chess_board_check` tests PGN in the original browser and main form, including
Open/Save filter selection, warnings, saving before replacement, cancelled/failed
Save, append saving and close. It retains the U10 discard-default tests using
a GUI composition with file saving disabled. No new GUI layout is introduced.

The optional `chess_pgn_differential_check.py` compares exported trees and SAN
with python-chess, using `chess_pgn_oracle_probe` as the file adapter probe.
The application has no python-chess dependency.

## Shared board and chess GUI checks

`run_gui_checks.sh` now also runs `chess_board_check` after the five existing
suites. It explicitly injects chess into the existing main form, while those
five suites continue to use the draughts default. The chess suite checks all
64 squares, flip/resize/margins, owned snapshots, board/list moves, all promotion
choices and stale/cancelled choices, mainline/branch navigation, FEN clipboard
paths, capability guards, SAN PVs (including invalid prefixes, pending updates
and Black move 37), and unchanged score-history behaviour. It also compares
all control bounds between draughts and chess compositions.

Compare actual saved draughts rendering with the pre-extraction control using:

```sh
python3 tests/board_render_compare.py /tmp/zgui-board-render
```

This builds the original control from commit `42e0d54` in an isolated directory,
then compares eight nonblank saved bitmaps, including both orientations, side
markers, kings and every highlight source. Native paint must invalidate the
bitmap raw-image cache before saving; the fixture explicitly does that.
The comparison needs GTK2 and a display. It can also be run under Xvfb where
installed; validation here used the available GTK desktop display. New neutral
board/PV units are included in the existing source dependency audit.


## UCI configuration and analysis

`run_regression_checks.sh` includes `uci_engine_check`: deterministic UCI peers,
legacy registry identities, options with spaces/case changes, bounds/secondary
lines, mate/Black-root scores, history, terminal positions, overlong output,
stop failures, cancellation, duplicate completion and independent processes.
It needs no installed chess engine. `run_gui_checks.sh` adds `uci_gui_check`,
using the existing engine editor/INI fields and annotator, navigation and shutdown.
The prior layout, Hub and draughts suites remain enabled.

Both new binaries optionally take a Stockfish executable path as their first
argument. This runs additional real-engine checks, including the initial position
and a custom Black-to-move root. Build `uci_gui_check.lpi` with the existing
`build_lazarus_check.py` helper and run with a GTK display. Range, overflow and
heap checks are enabled in that project. Stockfish is only a test dependency;
no engine binary is committed or installed by these scripts.


`uci_game_check` adds clocked UCI wire/period tests, Stop-versus-timeout checks for
UCI and Hub, crash classification, idle-human expiry, terminal roots and the
existing runner. Pass a Stockfish executable to add real two-engine period,
custom Black-root and promotion-root games. The GUI UCI suite also exercises
New game validation/defaults, both player colours, board input, quiet clocks,
live PVs with stdout hidden, two registrations, reservations, Stop and PGN reload.
The clocked Hub fixture is recorded against bc177c4 independently of the new
clock-record bridge; both old and new API paths must match its exact bytes.

## Mixed chess and draughts

`multi_game_gui_check` is part of the GUI sweep. It registers both games and runs
concurrent UCI and Hub games through the existing main window and runners, then
saves both formats. It checks separate standalone documents, preferences, strict
file classification, loaded annotator slots, stale session rejection, cancelled
close, simultaneous tournaments and independent publication/save ownership.
Fake peers are built into the test executable. Build/run it alone:

```sh
python3 tests/build_lazarus_check.py gtk2 /tmp/zgui-multi tests/multi_game_gui_check.lpi
DISPLAY=:1 /tmp/zgui-multi/multi_game_gui_check
```

For the same acceptance with real engines, pass four absolute executable paths:
Stockfish, Arasan (or another UCI engine), Scan engine6, Scan engine7. The test
writes registrations and preferences beside its executable, so build it in a
temporary directory, never in the source root. Both Scan copies must retain their
own configuration/parameter files. Real GWD DXP interoperability is deferred;
`run_dxp_checks.sh` retains the fake protocol peers.

The optional local `chatgpt/SCAN_ENGINE_ACCEPTANCE.pas` is an additional reference
engine check, not a required suite dependency. Compile it with FPC using `-Fu.`
and `-FU/tmp/zgui-scan-units -FE/tmp`, then run its executable with the project
root as its working directory. It expects the locally installed engine6/engine7
packages and exercises initialization, scored PVs, clocked moves and forced wins.

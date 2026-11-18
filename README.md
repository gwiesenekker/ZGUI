# ZGUI 1.1

ZGUI is a desktop GUI for **chess and international draughts**, with both games
available side by side. It builds on GWDGUI 3.4 and preserves its shared game,
analysis, tournament and database infrastructure.

## Features

- Chess on an 8×8 board and international draughts on a 10×10 board, with legal
  moves, FEN position setup, board flipping and configurable appearance.
- PGN for chess and PDN for draughts, including comments and nested variations.
- UCI chess engines and Hub/DXP draughts engines, configurable through the
  existing engine editor. Engine INI-file editing remains available.
- Human and engine games with clocks, increments, engine analysis, PV browsing,
  hints, evaluation bars, score history and Auto Play.
- UCI and Hub pondering, with per-engine compatibility flags. Optional
  `dxp-pv` collects Hub-format analysis from a local DXP engine's stdout during
  matches; DXP remains a game protocol, not an annotator protocol.
- Tabbed round-robin and Swiss tournaments, concurrent games, shared engine
  reservations and oldest-waiting-first allocation across tournaments.
- Opening ballot files for either game: every engine pair plays each FEN twice
  with colours reversed, optional opening-pair shuffling, and saved scheduled order.
- Live paired GSPRT comparisons, optional time-forfeit adjudication, and an
  interactive `--cli` in the normal GUI for creating, querying and stopping matches.
- SQLite game databases, import and duplicate detection, player/event filters,
  position searches and move-based navigation.
- Separate chess/draughts preferences where appropriate, a global engine-use
  status bar and an offline searchable manual under **Help → Manual**.

See the [manual](MANUAL.md) for supported rules, protocol settings, file locations,
result/reason handling and operational limits. See [CHANGELOG.md](CHANGELOG.md)
for implementation history and commit IDs.

## Download and run

Download a portable archive from [ZGUI releases](https://github.com/gwiesenekker/ZGUI/releases).
Extract it into a writable directory. On Windows, run `zgui.exe`; on Linux:

```sh
chmod +x zgui
./zgui
```

The Linux x86_64 build requires GTK2 and SQLite3 available as `libsqlite3.so`.
The Windows portable package includes 64-bit `sqlite3.dll` for database features;
keep it beside `zgui.exe`. A source build does not copy that DLL automatically.
No external
piece font is required: both boards draw their pieces directly. Engines and
engine data files are not bundled; install engines separately. Human-versus-human
play and game browsing do not require an engine.

The release includes **SHA1SUMS** and **SHA256SUMS** for the executables and
portable archives. Compare the downloaded files with these before use. For example,
on Linux run `sha1sum -c SHA1SUMS` for the files you downloaded, or on Windows:

```bat
certutil -hashfile zgui.exe SHA1
```

## First steps

1. Use **Engines...** to register an executable. Choose **UCI** for chess or
   **Hub/DXP** for draughts, launch to test/discover settings, and save.
2. Choose **New game...**, select players and a time control, then play by clicking
   a piece and destination or selecting a legal move.
3. Use **Game History** to switch between games and boards. Both games can remain
   open, with tournaments running concurrently when engine instances are available.
4. Right-click the analysis area to open an annotator. Use **Tournament...** for
   competitions and the **Database** menu for collections and position searches.
5. Press **F1** for the manual. **Ctrl+O** opens games, **Ctrl+S** saves the displayed
   game, and **Ctrl+,** opens preferences.

## Settings and portability

Keep the application directory writable: `engines.json` and `prefs.json` are
stored beside the executable. Per-engine `.params.json` files are stored beside
the engine. Save games, databases and named tournaments wherever you prefer.
Unsaved tournament recovery files use the operating system's per-user
configuration directory.

Engine paths are machine-specific. Re-register or edit engine entries when
moving between Linux and Windows. Give simultaneous DXP connections separate
ports. Never overwrite your settings or engine installations when upgrading.

## Build from source

Use **Lazarus/LCL 3.0 or later**, its bundled **SynEdit** package and
**Free Pascal 3.2.2 or later**. The release's Linux build uses GTK2.

On Linux, install the Lazarus/GTK2 development environment and Python 3, then run:

```sh
bash build.sh
./zgui
```

On Windows, install Lazarus and Git for Windows, make `git` available on PATH,
and run:

```bat
build.bat
```

You can supply a Lazarus location with `build.bat "C:\lazarus\lazbuild.exe"`.
Alternatively, open `zgui.lpi`, select the **Windows** build mode, and build.
The Windows build mode embeds help and Git identity without Python. The Linux
script embeds them too. The Lazarus **Default** mode instead reads `MANUAL.md`
beside the executable and reports build identity as unavailable.

Build scripts replace the installed executable only after successful compilation.
Modified tracked files are identified in About when build identity is embedded.
The repository ignores generated binaries, local settings, engines, databases
and temporary output; source files and test fixtures remain versioned.

## Checks

```sh
bash tests/run_regression_checks.sh
bash tests/run_dxp_checks.sh
bash tests/run_gui_checks.sh
bash tests/run_tournament_checks.sh
```

GUI checks need Lazarus/GTK2 and a display. To keep them off the main desktop,
use `python3 tests/run_hidden_gui.py bash tests/run_gui_checks.sh` (requires
Xephyr and an existing parent X display). See [tests/README.md](tests/README.md)
for individual checks and Windows validation.

## Origins and license

ZGUI is maintained by Gijsbert Wiesenekker and developed with assistance from
Claude and Codex. It derives from [GWDGUI](https://github.com/gwiesenekker/GWDGUI)
3.4, upstream commit `61c6cef894e18544d18e7e761143de47ef492226`.
Both games use the shared GWDGUI infrastructure through game-specific adapters.
Chess pieces are original scalable Canvas artwork in `uChessBoardControl.pas`.

ZGUI is distributed under the **GNU General Public License, version 3**;
see [LICENSE](LICENSE). Separately installed engines have their own licenses.

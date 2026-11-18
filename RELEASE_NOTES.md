# ZGUI 1.1 — 18 November 2026

ZGUI runs chess and international draughts side by side, reusing GWDGUI's game,
analysis, tournament and database infrastructure.

## Changes since 1.0

- Interactive `--cli` in the normal GUI: list engines, start two-engine matches,
  query results and opening pairs, and stop tournaments. Started tournaments are
  visible live in their normal tabs. Terminal input and pipes use the same commands.
- Opening ballots for both games, with two colour-reversed games per position,
  optional opening-pair shuffling and a saved order for reproducible replay.
- A live paired GSPRT pane with independent candidate/baseline selection, graph
  tooltips and the same calculation available through `query_tournament sprt=true`.
  Automatic stopping is left to the user or an external runner.
- Optional time-forfeit adjudication by a compatible Hub/UCI engine, with explicit
  evaluation comparisons in the Reason column. The default remains rules-based.
- Private saved UCI options per registration, even when sharing an executable.
- Confirmed **Delete from here...** in the Game Tree for stopped documents,
  retaining earlier data and sibling variations.
- Clearer tournament controls and reasons, saved-game history selection,
  conditional following of new games, and numerous layout and engine fixes.
- Finished games release engine workers promptly; long matches no longer retain
  hundreds of polling threads or make shutdown wait for them one at a time.
- Refreshed offline manual covering the GUI, CLI, storage and runtime libraries.

## Downloads and dependencies

Choose the Linux or Windows x86_64 portable archive. Archives include the manual,
license, changelog and build information. The Windows archive also includes
64-bit `sqlite3.dll` for database operations. Keep it beside `zgui.exe`; source
builds do not copy it automatically. The standalone Windows executable needs
that DLL separately for database features.

Linux requires GTK2 and SQLite3 loadable as `libsqlite3.so`. Engines, networks,
books and tablebases are installed separately. No external piece font is needed.

**SHA1SUMS** and **SHA256SUMS** cover the standalone executables and archives;
**BUILD-INFO.txt** records provenance and the bundled SQLite version.

## Validation and known limits

The current application source passed the full chess/draughts regression suite and
all 29 GUI suites, including concurrent game contexts, tournaments, CLI, engine
lifecycle and layout checks. The refreshed manual passed rendering and built-in
Help checks. Native Windows testing is limited; comprehensive interactive
console/pipe verification remains outstanding.

Existing UCI registrations without private options keep reading their legacy
parameter file until saved in the engine editor. Older ZGUI versions ignore the
private options, so update both platform builds together. Engines that write
logs or learning files beside their executable may still need separate folders.
Saved tournament identities do not freeze UCI option values: keep the tested
engine configuration when resuming or replaying a comparison.

SPRT settings should be fixed before inspecting results if interpreting their
nominal error rates. No finite set of tests proves support for all chess dead
positions; the manual describes the implemented material checks. A historical
commit range still awaits Claude's full review; this is a tested release, not a
claim that every commit has completed independent review.

Based on GWDGUI 3.4; distributed under GPLv3. SQLite is public-domain software;
see the SQLite notice in the Windows portable archive.

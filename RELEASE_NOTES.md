# ZGUI 1.2 — 18 November 2026

ZGUI runs chess and international draughts side by side, reusing GWDGUI's game,
analysis, tournament and database infrastructure.

## Changes since 1.1

- Fix the main-window resize path that could close ZGUI without saving after
  shrinking and enlarging the window.
- Improve laptop-height layouts for both games while retaining readable PV and
  annotator text, at least three notation lines, and all eight MCTS statistics
  rows. Font changes preserve the annotator status box's minimum height.
- Allow one bounded tournament backfill behind an older request blocked by a busy
  engine, while keeping oldest-ready precedence and preventing unlimited bypass.
- Reject new opening ballots containing positions that are already over, with
  file/line/reason reporting and no partial replacement. Draughts FEN rejects
  unpromoted men on their own promotion rank. Valid terminal starting positions
  in existing tournament archives remain readable.
- Accept four-field chess EPD opening ballots, with or without trailing operations.
  Missing counters become 0/1; operations are ignored. Ordinary FEN entry remains
  strict. The GUI picker and CLI use the same ballot loader.
- Expand native resize, laptop, queue and ballot regression checks; update the
  manual and stop shipping the obsolete GWDGUI PDF in the source tree.

## Downloads and dependencies

Choose the Linux or Windows x86_64 portable archive. Archives include the manual,
license, changelog and build information. The Windows archive includes 64-bit
`sqlite3.dll` for database operations; keep it beside `zgui.exe`. The standalone
Windows executable needs that DLL separately for database features.

Linux requires GTK2 and SQLite3 loadable as `libsqlite3.so`. Engines, networks,
books and tablebases are installed separately. No external piece font is needed.

**SHA1SUMS** and **SHA256SUMS** cover the standalone executables and archives.
**BUILD-INFO.txt** records the source revision, binary provenance and bundled
SQLite runtime.

## Validation and known limits

The application source passed the full chess/draughts regression suite and all
30 GUI suites, including 11,258 font/window/DPI checks. The actual Linux executable
passed repeated native resizing and clean-close checks for both games on a hidden
1366x768 display, accepting 1083x600, 1300x690 and 1366x700. Tournament, DXP and
lifecycle checks also passed.

The Windows executable was rebuilt and supplied by the maintainer. Its current
embedded manual was verified. It reports a source-archive build without an
embedded Git commit; comprehensive native Windows CLI console/pipe verification
remains outstanding. The original resize report should also be rechecked in the
reviewer's Lazarus environment. These follow-up fixes await independent review.

SPRT settings should be fixed before inspecting results if interpreting their
nominal error rates. No finite set of tests proves support for all chess dead
positions; the manual describes the implemented material checks. Keep tested
engine options unchanged when resuming or replaying comparisons: saved tournament
identities do not freeze those values.

Based on GWDGUI 3.4; distributed under GPLv3. SQLite is public-domain software;
see the SQLite notice in the Windows portable archive.

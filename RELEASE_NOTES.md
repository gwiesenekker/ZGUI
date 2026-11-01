# ZGUI 1.0 — 1 November 2026

The first ZGUI release brings chess and international draughts together in the
existing GWDGUI interface and shared game, analysis, tournament and database
infrastructure.

- UCI chess engines and Hub/DXP draughts engines, clocked games, analysis,
  PV browsing, hints, score history and Auto Play.
- PGN/PDN collections with comments and variations, FEN position setup,
  configurable appearance and SQLite game databases.
- Tabbed round-robin and Swiss tournaments, concurrent games of both types,
  shared engine reservations and oldest-waiting-first allocation.
- Per-engine compatibility flags: `no-pondering`, `no-ponder-hit` and `dxp-pv`.
- An offline Help manual and a status-bar count of engine sessions in use.

## Downloads

Use the Linux or Windows **x86_64 portable archive**, or download the executable
separately. Archives include the manual, license, changelog and build information.
No engines, engine data, local settings or external piece font are bundled.
Linux requires GTK2 and SQLite3 runtime libraries.

**SHA1SUMS** and **SHA256SUMS** cover the standalone executables and archives.
Build provenance is included in **BUILD-INFO.txt**. The Windows executable was
built and tested by the maintainer; it contains embedded Help but no verifiable Git
commit ID. The portable archive also includes the refreshed `MANUAL.md`.

## Validation

The application passed chess and draughts regression checks, DXP protocol checks,
all 20 GUI suites and both tournament suites. The Linux status-bar correction
passed 10,426 layout checks and was visually confirmed by the maintainer. Native
Windows build and visual testing were supplied by the maintainer. Release checks
also cover manual rendering, build identity generation and Windows build-script
replacement/recovery under Wine. Cross-compilation is skipped when the host lacks
FPC's Win64 units.

ZGUI is based on GWDGUI 3.4 and distributed under GPLv3. See the README, manual
and CHANGELOG for installation, protocol configuration, supported rules and
known operational limits.

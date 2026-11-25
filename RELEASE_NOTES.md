# ZGUI 1.3 — 25 November 2026

Chess and international draughts in one application, built on GWDGUI's shared
GUI, game, analysis, tournament and database infrastructure.

## Changes since 1.2

- Configure engine-specific environment variables through `gui-environment`,
  using the Variables/JSON editor. Overrides apply privately to locally launched
  UCI, Hub and DXP processes; the parent environment is unchanged.
- Add `configure_engine` to the existing interactive `--cli` and pipe interface.
  Inspect an existing registration, merge advertised engine options, replace
  environment overrides or feature flags, load a JSON settings file, and preview
  changes with `dry_run=true`. The command reuses GUI validation and storage and
  refuses writes while the engine is in use or its settings window is open.
- Require one registration per installed engine directory and executable,
  regardless of options or environment overrides. **Existing conflicting entries
  are retained but cannot launch.** Use separate actual installations to compare
  engines/configurations, or remove conflicting duplicate registrations.
- Fix resizing the tournament cross-table divider after **Engine**, and retain
  chosen column widths when results or selected participants refresh.
- Embed the Markdown manual as a resource, retaining the existing searchable
  Help window and parser. Update the manual with the new configuration commands.
- Report versions as `1.3-<short Git commit>` in About and `--version` on both
  platforms. The version command exits without opening the GUI. Build identity
  can be recovered from checkout metadata without Git, and from Git source archives.
- Give `build.bat` an SCU-style PowerShell entry point while retaining the existing
  build-candidate, backup and interrupted/failed-build recovery safeguards.

## Downloads

Use the Linux or Windows x86_64 portable archive. Both include the manual,
changelog, license and build information. The Windows archive includes 64-bit
`sqlite3.dll`; keep it beside `zgui.exe` for database operations. The standalone
Windows executable requires that DLL separately. Linux requires GTK2 and SQLite3
available as `libsqlite3.so`.

Engines, networks, books, tablebases, local settings and game databases are not
bundled. No external piece font is required. Back up your own settings and games
before upgrading; engine paths remain machine-specific.

**SHA1SUMS** and **SHA256SUMS** cover the executables, DLL and portable archives.
See **BUILD-INFO.txt** for source identity and binary provenance.

## Validation and notes

Source and both reported executable versions identify commit
`12a407644c0f776258b7ee15b857ca5c49eac608` (`1.3-12a4076`). The Linux application
passed the shared regression checks and all 33 GUI suites, including 11,258 layout
checks and 473 tournament-tab checks. The final release-number update passed the
version/build-info checks and all 33 GUI suites. The Windows executable was built
by the maintainer; its version and complete embedded manual were verified.
Comprehensive native Windows console/pipe testing remains outstanding.

In Windows cmd, the prompt can appear before the `--version` output. ZGUI has
already exited; pressing Enter redraws the prompt. To wait explicitly, use:

```bat
start "" /b /wait zgui.exe --version
```

Based on GWDGUI 3.4; distributed under GPLv3. The bundled SQLite runtime is public
domain; see SQLITE-NOTICE.txt in the Windows archive.

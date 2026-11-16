# Existing-executable CLI — implementation notes

Date: 2026-11-16. Baseline: 0074a62.

Authorisation: “Please proceed with the approved CLI changes and your refinements,
reusing the existing tournament execution. Please update CHANGELOG.md, compile,
test, and commit.” Scope: Claude's conditional approval in
`claude/review-0074a62-cli.md`, plus the refinements accepted in this conversation.

- S1: replace the proposed controller extraction with public `StartTournament`.
  GUI Play and startup both call this method. The grid, timer, scheduler, shared
  engine queue, runners, snapshots, clocks and result/capture paths remain intact.
- T12: per-dialog leases on canonical JSON and publication paths, acquired before
  authoritative load/writes. Unix flock plus close-on-exec; Windows write handles
  disallow other writers. Same-process leases are reference-counted; the existing
  tab host still enforces duplicate identity/path ownership. Sidecars are retained
  to avoid unlink/recreate races. PID/host text is diagnostic only, never authority.
  Save As holds original leases until successful writing; unsuccessful operations
  preserve source ownership. Reset/close releases leases. Existing file formats
  are unchanged. Locks protect cooperating new ZGUI versions, not external editors
  or older versions. Network filesystems must support the OS locking primitives.
- C8: allow documented GTK/LCL options without modifying argv; standalone unknown
  option-led launches keep normal GUI startup, while misspelled command names and
  unknown arguments to a command are errors. `--` makes subsequent filenames literal.
- C9: `ParamStrUTF8`, preserving argument boundaries and Unicode paths.
- SCU subset: command value, binder and minimal string-parameter adapter from
  44eba85, with noninteractive required/default finalization. Both repositories
  have GPLv3 licences. No tokenizer, JSON catalog, terminal, executor or audit layer.
- Startup request is queued once on MainForm and removed by existing destruction
  cleanup. It reuses the normal tournament host's OpenFile, shows the tab and
  selects its game once, then invokes shared Play. No periodic auto-selection and
  no separate executable/IPC. Normal last-game preference handling is retained.
- Existing stopped/failed rows are not silently replayed. Already-running tabs
  are selected; already-open stopped tabs receive the same Play eligibility checks.

Validation and implementation commit IDs are recorded in CHANGELOG.md.
Native Windows execution remains a separate QA requirement; Linux checks cannot
establish Windows sharing/Unicode GUI behavior by themselves.

Validation completed: application build; full regression script; both tournament
suites; all 22 GUI suites on hidden displays; expanded startup CLI check with 52
assertions; parser check with 54 assertions. The layout sweep passed 10,618 checks,
and tabbed tournament checks passed 392. Win64 compiler probe cannot find the
target RTL; no Windows executable was produced or claimed tested. The existing
Windows executable and local engine directories were left untouched.

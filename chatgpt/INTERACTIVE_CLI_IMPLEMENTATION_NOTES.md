# Interactive CLI implementation — reviewed stages

Date: 2026-11-16. Baseline: cd4b00c. Implementation: `0d80b72`. Review:
`claude/review-cd4b00c-interactive-cli.md`.

User authorisation: “Could you review Claude's review of the interactive --cli
proposal and proceed with the approved changes? Please update CHANGELOG.md,
compile, test, and commit.”

The approved GUI seams and terminal startup connection are implemented. On
2026-11-16 the user explicitly waived the native-Windows prerequisite:
“Waive prerequisite; finish integration with Windows QA outstanding”. Scope:
connect the prepared transport to the existing executable and shared GUI actions;
leave native Windows execution unverified. The waiver does not cover unrelated
shared functionality. Ordinary startup and the one-shot saved-file CLI remain
intact.

## Scope and review decisions

- Reuse the existing tab, grid/records, pair generator, automatic saves, engine
  queue, thread runners, clocks and completion/capture paths. No controller rewrite.
- ConfigureNewTournament fills the existing controls in a guarded batch and calls
  ReadSettings/MaxConcurrentGames and LoadBallotFromFile. Only explicit typed values
  replace profile defaults; decimal conversion uses the local GUI format.
- CreatePairing is extracted from the button handler. GUI prompts stay the same;
  command mode returns errors instead. StartTournament adds command mode plus the
  single allow_shared_executable acceptance; no global Yes flag.
- MatchSnapshot copies current records without calling IsRowStartable or saving.
  It validates two reversed-colour rows per opening entry, retains repeated FENs
  as distinct entries and uses effective results from the bound engine1 perspective.
  Referee results and current replay attempts are counted; historical attempts and
  unknown results are not completed games. Storage/capture errors expose a reason.
- Session handles bind tab ID + tournament UUID + engine keys. Closed, replaced or
  structurally changed matches return distinct errors. Engine IDs are never reused
  for different identity keys; names must be unambiguous; explicit keys are accepted.
- T15: reject commands while Application.ModalLevel > 0, the host is busy, or another
  command is executing. Tests issue actual commands inside a modal dialog and get
  BUSY without changing the tournament. The transport never touches controls.
- D11: Unix engine launches use the existing TProcess OnForkEvent hook to call
  setpgid(0,0) before exec. FPC 3.2.2 does not implement poNewProcessGroup on Unix.
  The child hook uses only OS calls; failure exits before starting an unprotected
  engine. This also applies to ordinary GUI launches. SIGINT handling is confined
  to the opt-in terminal transport. Background terminal input is not read until
  the process group is foreground; SIGTTIN/SIGTTOU/SIGPIPE are explicitly handled.
- C11: the prepared Windows backend allocates a dedicated console for interactive
  input, preserves redirected handles, and uses Unicode console I/O or UTF-8 pipes.
  It does not compete with the launching shell's input. The console close menu is
  disabled because application shutdown belongs to the GUI. Pipe input can attach
  to a parent console solely for output, while still reading only the input pipe.
  Native Windows validation is not claimed.
- C12: adapt the SCU 44eba85 full-line tokenizer: unquoted backslashes are literal.
  Inside double quotes only quote/backslash escapes remain. Single quotes preserve
  all backslashes, including UNC prefixes. Startup argv is never retokenized.
- One terminal worker owns sequential input/output; ref-counted requests cross the
  GUI boundary with one outstanding request. Reads/writes/waits are cancellable,
  oversized lines are drained, UTF-8 and NUL are checked, EOF detaches input, and
  broken output does not kill the GUI. Windows uses cancellable synchronous I/O;
  Unix uses poll and nonblocking output, reopening terminal/pipe output descriptors
  to avoid changing the launching shell's terminal flags. Ordinary files retain
  inherited seek/append semantics. No line editor or SCU executor is imported.
- Shutdown diagnostics are routed to stderr, not protocol stdout, and tolerate
  unavailable diagnostic streams. The host remembers the game of a newly created
  tab so its existing New tournament toolbar still works after all tabs close.

## Protocol and errors

Every accepted nonblank command has one `OK ` or `ERROR ` JSON response line. There
is no pipe prompt or unsolicited progress output. Terminal prompts go to stderr.
The normal executable now accepts `--cli`, queued after GUI initialization. Its
existing GUI event timer consumes one owned request, dispatches it on the GUI
thread and replies. Destruction cancels I/O before retiring command/session state.
EOF leaves the GUI alive; help and invalid combinations use existing GUI dialogs.
The command syntax and limitations are documented in the built-in manual.

Codes: BAD_ARGUMENT (syntax/binding/numbers), UNKNOWN_ENGINE and AMBIGUOUS_ENGINE
(selector resolution), GAME_MISMATCH (protocol membership), BUSY (modal/host/
reentrancy), CONFIGURE (shared setup validation/ballot load), PAIRING (shared pair
creation), STORAGE (automatic-save failure), CONFIRMATION_REQUIRED (the shared
executable warning), START (shared start rejection), UNKNOWN_TOURNAMENT (closed/
unknown handle), TOURNAMENT_REPLACED (UUID changed), MATCH_CHANGED (participants or
pairing shape changed), TRANSPORT (unexpected transport failure), SHUTDOWN and
INTERNAL (application shutdown/unexpected dispatcher failure). Retained-event
errors include tournament ID and file path; unpublished invalid setups are discarded
without the destructor accidentally creating a recovery event.

## Validation

The 23 GUI suites, both tournament suites and full regression suite pass; GUI
execution uses hidden displays. Lifecycle and local DXP suites also pass. Targeted command-text/UTF-8 checks: 42; transport checks: 20, including
Ctrl+C with two actual TPlatformProcess peers and a background terminal job.
Engine process tests verify a separate group before exec. The GUI command check
covers both games, 25 resolved games / 12 complete pairs, referee overrides,
rescheduling, error reasons, read-only queries, modal BUSY and identity changes.
Extended GUI handler check: 85 assertions. Commit IDs go in CHANGELOG.md.

Native Windows helper: `tests/cli_terminal_check.lpi` (same GUI subsystem as ZGUI),
`tests/CLI_WINDOWS_TRANSPORT_CHECK.md`, and `tests/cli_terminal_transport_check.py`.
The Linux host lacks a Win64 RTL; Linux tests do not verify Windows console or
cancellation behavior. Local engine directories and user files are untouched.

## Integrated startup completion

The native-Windows prerequisite was explicitly waived as quoted above. No native
Windows test is claimed. Additional tests drive both games through real pipes,
verify live board selection and normal GUI Stop, request commands while a modal
dialog is open, check EOF keeps the GUI alive, and close the GUI with idle input
or blocked stdout. A separate smoke test runs the actual application binary from
a private temporary directory and uses its normal close/save confirmations.

Final integrated validation: application build, full regression suite and both
tournament suites pass; the complete GUI script passes all 24 checks on isolated
displays. Startup argument checks: 64; shared command GUI check: 91; actual-binary
and live pipe sessions: 39. Relative ballot resolution is anchored to MainForm's
launch directory, including a cwd change before the first command. Explicit empty
ballot values are rejected. No native Windows test is claimed.

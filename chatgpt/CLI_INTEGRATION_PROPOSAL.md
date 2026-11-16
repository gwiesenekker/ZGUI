# Startup CLI in the existing ZGUI executable — proposal for Claude

Date: 2026-11-16. ZGUI baseline: `0074a62`; SCU parser reviewed at `44eba85`.
Status: reviewed with conditions in `claude/review-0074a62-cli.md`.
Part A below is superseded by S1: expose the existing dialog start action; do not
extract a new controller. See `chatgpt/CLI_IMPLEMENTATION_NOTES.md` for the approved
implementation scope, file protection and parser refinements. The original draft
is retained below as review context.

## Requested outcome

Use the existing `zgui` / `zgui.exe` executable to open and start a saved
tournament, with its normal tournament tab visible and games watchable live:

```text
zgui run_tournament file="GWD-Kingsrow.json"
zgui.exe run_tournament --file "C:\Tournaments\GWD versus Kingsrow.json"
```

The user explicitly rejected a separate console executable. Normal startup with
no arguments stays unchanged. Both chess and draughts use this feature. The GUI
still allows selecting games, browsing positions, stopping tournaments and
performing referee actions.

The GUI does not generate command strings, and there is no SCU-style audited
command execution pipeline. GUI actions and parsed startup requests call the
same typed tournament actions directly.

## Findings in the existing projects

| Area | Current implementation | Consequence |
|---|---|---|
| Application startup | `zgui.lpr` registers both games, initializes LCL, creates `TMainForm` and runs the event loop. | Add a small startup request adapter to this executable. |
| Tournament tabs and files | `TTournamentHostForm.OpenFile` detects the saved game's variant, checks file/identity ownership, selects an existing matching tab or loads a new one. | Reuse this host path; do not independently load JSON into CLI-owned state. |
| Tournament execution | `TTournamentDialog.StartStopClick`, `StartPendingGames`, `TimerTick` and `StopRunningGames` contain start, scheduling, completion and stopping policy. Grid cells still hold significant authoritative state. | There is not yet an independent tournament controller. Extract the existing execution path before adding another caller. |
| Game execution | `TMainForm.TournamentStartGame` delegates to `StartGameFromSetup`, which creates the existing `TRunningGame` and `TGameRunnerThread`. | Keep this path and its game-history/snapshot integration. |
| Reservations and fairness | MainForm collects busy engines across games/annotators; `TTournamentEngineQueue` arbitrates oldest-waiting-first across tournament tabs. | Use the same application-session pool, not a CLI-specific queue. |
| Tournament data helpers | Existing pairing, model, game-record, storage and ballot units cover different parts of tournament behavior; `uTournamentModel` is not a runner. | Reuse them; do not create a parallel scheduler or storage format. |
| SCU parsing | `scubinder`, `scucommand`, generic portions of `scucommands` and the non-interactive finalization in `scucli` already provide the needed command binding. | Adopt this subset with small, documented adaptations. |

Source paths in this document are relative to their respective repository roots:
ZGUI `/tmp2/gwies/ZGUI`, SCU `/tmp2/gwies/SCU`. SCU is reference material only;
this work must not modify it or `/tmp2/gwies/GWDGUI`.

## A. Establish shared tournament execution first

Introduce a narrowly scoped `TTournamentController` (suggested new unit
`uTournamentController.pas`) by moving the existing dialog execution methods,
not by writing a second implementation. GUI Play must use it before CLI startup
is connected. The controller is independent of control handles and grid indices;
rows have stable identities, backed by the existing game records.

The shared controller owns execution state and the existing decisions about:

- start eligibility, active games, launch staggering and concurrency;
- row selection, Swiss-round eligibility and fair reservation requests;
- completion, capture, results/reasons, referee stops and rescheduling;
- when to request the existing automatic-save/publication operations, and how
  storage or capture failures prevent further starts.

Extract only the state these paths need. Populate it through the existing load
and pairing adapters. Make the grid a projection of that state; edits and referee
actions update the same records through shared actions. Do not retain independent
grid and controller versions of a row's result, reason, FEN or lifecycle.

Keep UI-specific work in the dialog/host: controls, measurement, confirmations,
file selection, selected-row viewport, crosstable display and tab ownership.
Existing storage serialization and PGN/PDN capture/export remain one path, exposed
to the controller through narrow callbacks/services as needed. No snapshot schema
change is required solely to add the CLI.

Proposed controller/application seams (names illustrative):

| Action/service | Responsibility |
|---|---|
| `StartTournament` | The common validated start action used by GUI Play and startup. Return started / already running / nothing eligible / cancelled / failed, with a useful explanation. |
| `Tick` | Consume existing running-game state and schedule eligible rows. The current GUI timer drives it; no second polling loop. |
| `StopTournament` | Existing referee-stop semantics; drain and capture games through the existing lifecycle. |
| Game-host adapter | Start via MainForm, look up current `TRunningGame` objects, stop through existing methods, and use the existing queue/busy-engine collection. |
| View/persistence adapter | Present changes and invoke the existing capture/save/publication path. Report failures back to the same controller. |

The common start action retains `ReadSettings` validation, pairing-required and
pending-edit guards, shared-executable confirmation, save-before-play and storage
failure checks. The CLI must not bypass these by calling the scheduling method
directly. GUI prompts remain interactive because this is a visible GUI program.

Do not move engine management, clocks, protocol handling or game orchestration
out of `TGameRunnerThread` / `TGameOrchestrator`. Worker callbacks continue posting
the existing GUI events; the controller is driven on the GUI thread. Do not access
controls from runner threads or add blocking waits to the event loop.

## B. Reuse the SCU parser subset

Recommended: copy/adapt the small reusable parser modules into ZGUI with
SCU source revision and attribution recorded. Check source licensing before
copying. Avoid a dependency on SCU's executable, library data or release layout.

Include:

- The bound command/value representation from `scucommand`.
- Execution binding from `scubinder`: positional and named arguments, duplicate
  and unknown-argument errors, aliases, canonical values and explicit/default
  provenance.
- Generic command/parameter definitions and validation from `scucommands`;
  remove SCU library/deck/version/revision fields and completion dependencies.
- The **non-interactive finalization** from `TScuCLI.ParseCommand`: finish pending
  values, apply defaults, skip absent optional parameters and reject missing
  required parameters. The binder alone does not perform all these steps.
- Generic help rendering and catalog/handler consistency validation, sized to the
  two initial commands. Embed the small catalog so help/startup does not depend
  on a mutable external file beside the executable.

Adapt generic error, JSON and file-reading helpers to existing ZGUI equivalents;
do not import SCU's broad library/file subsystem to satisfy small dependencies.
Preserve parser behavior with focused tests instead of replacing it with a newly
written ad-hoc parser. Metadata about mutually exclusive options is not itself
execution validation: any future conflicts must be checked by the typed request.

Do **not** copy SCU's executor, audit transactions, revision/locking system,
terminal I/O, line editor, POSIX signals, REPL, history or completion machinery.
There is no need to add command files in the first delivery.

### Argument boundaries and Windows paths

As SCU already does in `TScuCLI.Run`, bind the individual process arguments
directly. Do not join `ParamStr` values into a string and tokenize them again.
Use the established Lazarus Unicode argument facilities where needed on Windows.

SCU's `scutokenizer` is for command text, not already-split process arguments.
Its unquoted backslash escapes would turn textual `C:\matches\ballot.json` into
`C:matchesballot.json`; quoted command text preserves the path. This was verified
with an isolated tokenizer probe. Defer the tokenizer until a command-text input
is actually introduced, and then reuse its tested quote/escape behavior.

## C. Initial command contract

Support one startup command per invocation:

```text
zgui run_tournament file="tournament.json"
zgui run_tournament --file "tournament.json"
zgui run_tournament "tournament.json"
zgui --help
zgui help run_tournament
```

`file` is one required, non-empty saved-tournament JSON path. Relative command-line
paths resolve against the invocation's working directory. Paths within the saved
tournament retain the existing loader's resolution rules. Command/option spellings
follow the adapted SCU catalog; filenames are never lowercased or otherwise
canonicalized as command names. Reject extra values, duplicate options, unknown
commands and missing option values before opening a tournament or launching engines.

Load clocks, concurrency, engine identities, game variant, pairings and embedded
ballot/per-row positions from the existing saved document. No initial CLI flags
for engines, clocks, FEN, pairing or replay: those would introduce competing
configuration and override policies.

`run_tournament` means the same action as opening that file and pressing Play:
continue rows eligible under existing rules, preserve completed results and
referee decisions, and do not silently reschedule stopped/failed rows or replay a
completed tournament. Report when nothing can be started. A matching already
running tab is selected without starting a duplicate tournament.

No automatic application exit after completion. Leave the live GUI and results
open. This initial command is interactive startup automation, not a headless batch
job with a shell exit code representing tournament results.

## D. Startup integration and errors

1. Bind/validate arguments into an owned typed startup request without launching
   engines or writing tournament files. Keep parser units LCL-independent.
2. Initialize the normal application, game registrations and MainForm.
3. Queue the request once after the GUI is ready. Use the existing application
   event mechanism, not command execution from form construction/layout.
4. Obtain the same tournament host used by the menu; call `OpenFile`, select its
   returned tab, show the tournament window, and invoke the shared start action.
5. Continue the normal event loop: existing snapshots update boards/history and
   the same timer/controller updates tournament rows.

Help and command errors must be visible on Windows even without an attached
console. Present generated help or a concise actionable error in the GUI; console
output may supplement this but cannot be the only feedback. Help/invalid requests
must not start a tournament. On load/start failure leave the normal GUI usable;
leave a successfully loaded tab visible when start is cancelled or fails.

Queue ownership and shutdown must be explicit: consume the request at most once,
remove queued callbacks on destruction, and do not retain a raw dialog pointer
across asynchronous close/switch operations. If the host is busy, report a defined
failure rather than repeatedly replaying a potentially partially executed start.

Launching another ZGUI command starts another ordinary application process. This
proposal does not add single-instance forwarding, IPC or cross-process engine
reservations. Within the process, CLI-started and manually started tournaments
share the existing engine queue and annotator reservations.

## Implementation sequence and validation

1. Extract shared tournament execution and redirect GUI actions/timer to it.
   Establish parity for both games before adding startup command execution.
2. Adapt the SCU binding subset and add LCL-independent parser tests.
3. Add the typed startup action, visible host integration and generated help.
4. Update the built-in manual and changelog, recording implementation commit IDs.

Required checks:

- Parser: all advertised forms, required/default handling, empty/missing values,
  duplicate/unknown arguments, extra positional values, `--`, help, spaces,
  Windows drive/UNC paths and non-ASCII filenames. Prove argv is not retokenized.
- Shared execution: GUI and startup requests reach the same controller and game
  host. Verify no-pairing, invalid settings, cancellation, storage/capture failures,
  result/reason preservation, stop/drain, resume and completed-file behavior.
- Live GUI: correct variant/tab shown, board/game selection and snapshots work,
  Stop remains responsive, duplicate-file/identity ownership is preserved, closing
  retains Save/Discard/Cancel and normal startup is unchanged.
- Scheduling: coexistence with another tournament and annotator, engine exclusion,
  oldest-waiting-first fairness, concurrency and launch staggering remain intact.
- Ballots: load existing embedded positions without the source file, preserve
  per-row FENs and reversed colours; cover chess and draughts saved formats.
- Compile the application, run both-game tournament/core checks and the complete
  `tests/run_gui_checks.sh` suite on isolated displays. Perform native Windows QA
  for quoted/Unicode paths, help/error visibility, live start/stop and layout.

No application compilation or GUI execution is needed for this documentation-only
proposal. Implementation should be committed in reviewable stages, with no engine
directory changes and no separate CLI runner or executable.

## Requested Claude review

Please review the extraction boundary and state ownership first: does moving the
existing scheduling/completion policy into this controller preserve all current
GUI behavior without turning the dialog into a hidden runner? Then review the
SCU subset, startup lifecycle and command/error contract. Approval should cover
the named shared changes above; additional shared behavior changes need separate
review or an explicit user waiver.

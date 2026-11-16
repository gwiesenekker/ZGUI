# Interactive and piped CLI in ZGUI — proposal for Claude

Date: 2026-11-16. Baseline: `66654d7` (startup CLI implementation `8a06c4d`).
Status: approved with conditions in `claude/review-cd4b00c-interactive-cli.md`.
See `INTERACTIVE_CLI_IMPLEMENTATION_NOTES.md` for the reviewed decisions, completed
GUI seams, transport tests and the pending native-Windows integration gate.
The original design below is retained as review context; its Windows console and
backslash rules are superseded by C11/C12 in those notes.

User request: “Could you prepare a proposal for Claude in chatgpt for the
interactive --cli mode, with list_engines, run_tournament and query_tournament,
supporting pipes and reusing the existing tournament GUI and execution?”

## Goal and boundaries

`zgui --cli` opens the normal GUI and accepts commands on standard input. Started
tournaments appear in ordinary live tabs. Commands entered at a terminal and
commands supplied through pipes use identical parsing, handlers and responses.
Normal GUI startup and the existing one-shot saved-file command remain supported:

```text
zgui
zgui run_tournament file="saved-tournament.json"
zgui --cli
```

The initial interactive interface creates two-engine matches, with or without an
opening ballot, and queries them. Both chess/UCI and draughts/Hub/DXP work through
the same existing interfaces. GUI tournaments with more participants remain
unchanged; general interactive tournament editing is outside this first delivery.

No separate executable, headless runner, GUI-generated command strings, audit
pipeline, IPC, automatic tournament replay or SPRT implementation. The current
one-shot `file=` form retains its existing scope, including larger tournaments;
this proposal does not add saved-file commands to the interactive vocabulary yet.
Reject `--cli` combined with a startup command instead of executing two requests.

## Proposed command contract

Example terminal session (the response format below is proposed):

```text
$ ./zgui --cli
zgui> list_engines
OK {"command":"list_engines","engines":[{"id":1,"name":"GWD 8.1279","game":"draughts","protocol":"hub"},{"id":2,"name":"GWD multi-cut","game":"draughts","protocol":"hub"}]}
zgui> run_tournament engine1="GWD multi-cut" engine2="GWD 8.1279" ballot="ballot2.fen" time=600 moves=75
OK {"command":"run_tournament","tournament":1,"engine1":2,"engine2":1,"state":"running","games_total":158,"pairs_total":79}
zgui> query_tournament id=1
OK {"command":"query_tournament","tournament":1,"state":"running","games_total":158,"games_completed":25,"games_active":1,"pairs_total":79,"pairs_completed":12,"wins":1,"draws":23,"losses":1,"unresolved_games":0}
```

Each response is one physical UTF-8 line: `OK ` or `ERROR ` followed by a JSON
object. JSON escapes quotes, newlines and backslashes. All commands, including
`list_engines`, return a single response rather than one line per item. Flush each
response. Include `command` and stable error `code`; textual `message` is for people.
Commands are processed sequentially, so an initial request-ID protocol is unnecessary.

`run_tournament` acknowledges configuration, pairing and acceptance by the shared
start action, not completion of games. It does not wait for engine initialization,
finished games or available reserved engines. Synchronous file validation and
pairing creation can still take time; do not promise a constant-time response.
An engine failure after acknowledgement is visible in the GUI and later queries.

### `list_engines`

No arguments. Read registered engines through the existing registry APIs; do not
launch them or rewrite configuration. Return `id`, `name`, existing identity `key`,
`game`, `protocol` and availability/error information. Omit executable arguments and
INI contents. The example omits some fields for readability.

Assign monotonically increasing session-local numeric selectors to registration
identity keys. Refresh resolution on each command; detect removed/changed engines
rather than reusing an old number for a different registration. Duplicate names
are allowed in the registry but name selection must reject ambiguity.

Use names as shown above, or explicit selectors `engine1_id=2 engine2_id=1`.
Accept exactly one selector for each side; do not interpret a numeric engine name
as an ID. Responses identify the resolved registrations. Do not persist CLI IDs
in `engines.json` or use a changing registry array index as a durable identity.

### `run_tournament`

Required: selectors for two distinct existing registrations. Infer the game from
their protocols and reject a chess/draughts mismatch. Hub against DXP remains valid.

Optional parameters:

| Parameter | Meaning/default |
|---|---|
| `name` | Normal generated tournament name if omitted. |
| `ballot` | Existing FEN ballot loader; two colour-reversed games for every entry. |
| `time` | Positive finite seconds per period; omitted means the selected GUI profile's clock default. |
| `moves` | Nonnegative integer; omitted means the profile default. Zero retains the existing sudden-death meaning. |
| `increment` | Nonnegative finite seconds, including fractions; omitted means the profile default. |
| `concurrent` | Positive integer; default is the normal dialog default. |
| `allow_shared_executable` | Explicit acceptance of the existing shared-executable warning; default false. |

Use the existing profile's increment mode; defer an increment-mode flag. Without
a ballot, create an ordinary double round-robin match from the profile's starting
position. With a ballot, let `LoadBallotFromFile` enforce double round-robin and
preserve FENs, duplicate entries and file order. Do not add a separate FEN or ballot
parser. Relative CLI paths use the session's launch directory.

Parse numbers with invariant decimal-point syntax; convert typed values to the
GUI's local numeric formatting before `ReadSettings` reads them. Do not copy raw
CLI decimal strings into locale-sensitive edit fields. Domain validation remains
in the existing methods. Missing values use actual GUI/profile defaults, not a
second table of CLI defaults. No engine options or feature flags are modified.

`engine1` defines query perspective, not a promise that it occupies White in the
first row: preserve existing pairing ordering and inspect each row's engine keys.
The normal automatic-save path supplies the recoverable snapshot; include the
tournament UUID and actual snapshot path in the full successful response.

### `query_tournament id=N`

Return a copied snapshot of the referenced event on the GUI thread. Querying must
not select a board, advance play, create files, clear transient reasons, change
results or call the side-effecting `IsRowStartable` predicate.

- `wins`, `draws`, `losses`: current effective results from engine1's perspective,
  accounting for its actual colour in each row. Reuse `EffectiveResult` and
  `ParseTournamentResult` with the correct PGN/PDN format. A draughts `2-0` is one
  win, not two wins. Include referee overrides, and report their count separately.
- `games_completed`: rows with a known effective result. It equals wins + draws +
  losses for this two-engine scope. Active, pending and terminal `*` rows do not
  count. Current attempts count once; archived replay attempts do not add games.
- `unresolved_games`: finished/stopped/failed rows with `*` awaiting referee action;
  distinguish these from pending and active rows. Expose storage/capture errors
  and a concise status/reason rather than interpreting unknown results as draws.
- `pairs_completed`: ballot entries whose two colour-reversed rows both have
  known results. Verify entry/round identity, reversed engine keys and matching
  starting FENs using existing pairing/record facts. Repeated FENs remain separate
  entries. For ordinary double round-robin, the two games form one pair.
- Effective results and pair counts may decrease after a GUI reschedule or referee
  correction. Return current state, not independent monotonic CLI counters.

State precedence must be explicit: storage/capture error (`error`), stop draining
(`stopping`), all planned games resolved (`completed`), active orchestration
(`running`, optionally `waiting` when only reservations block it), unresolved
terminal rows (`attention`), otherwise idle/stopped (`stopped`). Derive this from
existing facts, not a second scheduler. The response includes total, active,
pending and unresolved game counts so its meaning is inspectable. It may lag a
worker result until the existing GUI timer consumes that result; do not create a
second completion-consumption path to make querying fresher.

SPRT, pentanomial buckets and likelihood ratios are deferred. These counts alone
must not be advertised as an SPRT sample or decision.

## Small shared GUI seams, not a controller extraction

Current evidence at the baseline:

- `TTournamentDialog.ReadSettings` reads controls and calls `ValidateGameSetup`.
- `LoadBallotFromFile` already validates and installs a complete opening ballot.
- `CreatePairingClick` already uses `BuildBallotPairingRound` or the shared pairing
  builder, applies ordinary rows, stores their FENs and automatically saves.
- Public `StartTournament` is already shared with startup CLI execution.
- `TTournamentHostForm.NewTournament` creates the real tab. Its private monotonic
  `TTournamentTab.Id` and existing `TournamentIdentity` provide the necessary identity.

Proposed additions:

1. `ConfigureNewTournament(Settings)`: typed settings with presence information,
   restricted to a fresh, unpaired dialog. Resolve all selectors before applying
   anything; batch control updates/change notifications using existing loading
   guards and layout batching. Set engine selections by identity, not control text.
   Apply only explicit clock overrides to profile defaults; validate through
   `ReadSettings`, `MaxConcurrentGames` and the existing ballot loader. No separate
   CLI-owned configuration model or duplicate game/clock policy.
2. `CreatePairing(...)`: move the existing click-handler body into a result-returning
   method. The button remains a thin wrapper. Preserve the existing pair builder,
   row records, automatic saving, recovery and storage-error behavior.
3. A narrow action/confirmation context, defaulting to today's GUI behavior.
   CLI calls return typed errors instead of opening modal dialogs. The existing
   shared-executable check remains authoritative; the named flag permits only
   that warning. Pairing and Start use the same context. No global auto-Yes flag,
   suppression of validation, or changes to unrelated GUI save/close prompts.
4. Read-only host lookup by session tab ID, plus a typed match snapshot method
   in the dialog. These expose existing row/record facts; the CLI neither walks
   arbitrary controls by caption nor maintains a parallel tournament table.

The creation handler runs on the GUI thread: create normal tab → configure →
create pairing → existing `StartTournament`. The same tab, grid, timer, fair engine
queue, game runners, snapshots, clocks, reasons, PGN/PDN and leases remain in use.
No `Button.Click` automation or hidden form acting as an alternative backend.

On failure, return one `ERROR` with the failing phase. If validation failed before
pairing/storage, discard the fresh empty tab through a narrowly scoped host cleanup
that cannot close a running or data-bearing tab. Account explicitly for the dialog
destructor's automatic-save path: rejecting an unpublished fresh setup must not
accidentally publish an empty event during cleanup. If pairing/save/start has already
produced state, retain its visible tab and recovery files; include its ID/path in
the error. Never erase a partially published event, silently retry a start or
report an error after starting games without identifying the retained tournament.

## Tournament identity and changes from the GUI

Keep a small session handle binding: numeric ID → host tab ID + tournament UUID +
the two registration identity keys. This is identity/perspective metadata only;
all live results, settings and scheduling still belong to the existing dialog.

Do not reuse handles after close. A queued query resolves the binding on the GUI
thread each time. Closed tabs return `UNKNOWN_TOURNAMENT`; in-place game switching
or replacement with another UUID returns `TOURNAMENT_REPLACED`, not another event's
results under an old ID. If GUI edits remove the original participants or invalidate
the expected two-game pairing structure, return `MATCH_CHANGED` rather than invent
pair counts. Ordinary rename, Save As and clock edits do not change perspective.
IDs are local to one ZGUI session and are not restored across application restarts.

## Terminal and pipe lifecycle

Reuse the adapted SCU binder/command representation, adding only the necessary
parameter definitions. For command *text*, now adopt SCU's full-line tokenizer
from revision `44eba85`, with attribution and tests. Do not import its terminal
editor, completion, history, library, executor or audit machinery. Keep argv binding
separate: never retokenize startup arguments. Document quoting of Windows paths
(`ballot="C:\\Matches\\ballot2.fen"`); unquoted backslashes have SCU escape semantics.

- Use UTF-8 input, LF or CRLF, and accept a final nonempty line at EOF. Reject NUL,
  invalid UTF-8, overlong lines and malformed quoting with one error for that line;
  drain an overlong line before accepting the next. Blank lines are ignored.
  Proposed maximum line size: 64 KiB. No multiline commands or shell execution.
- Show `zgui> ` only when input and output are terminals. Put prompts on stderr;
  stdout contains response lines exclusively. No prompts, banners or asynchronous
  progress messages for pipes. Diagnostics/logs go to the existing GUI logs or
  stderr; audit direct stdout writes (including MainForm's shutdown warning).
- A terminal I/O worker submits one owned request at a time to the GUI dispatcher,
  waits off the GUI thread for its owned result, and writes it before submitting
  another request. It never reads controls or retains a dialog pointer. This bounds
  the application queue and avoids a second game execution thread.
- Reads, response writes and waits must be cancellable. Idle stdin and a client
  that stops reading stdout must never freeze the GUI or hang application close.
  Unix can use nonblocking descriptors/poll plus a cancellation descriptor;
  Windows needs explicit console/pipe handling and cancellable I/O, not `ReadLn`
  followed by an uninterruptible `WaitFor` on the GUI thread. Require a focused
  platform transport test before connecting tournament actions.
- EOF stops CLI input after processing already accepted lines. It does not close
  ZGUI, stop tournaments or bypass GUI saving. Closing the GUI cancels the terminal
  worker, removes pending callbacks and drains existing games through normal
  shutdown. Accepted commands get a response while the transport remains writable;
  a disconnected/broken output endpoint cannot be promised delivery and detaches
  the CLI without undoing already accepted tournament starts. Avoid SIGPIPE exit.
- Initially retain the terminal's ordinary line editing. Ctrl+C at a terminal
  prompt cancels the current input line, not the tournament. Establish and test
  that narrowly scoped console/signal behavior when `--cli` is active; no signal
  handler touches LCL. Ctrl+D/EOF detaches input. Close the application through
  its GUI; no `quit` command or new remote referee/stop command in this scope.

Windows must keep the existing GUI executable subsystem. Preserve inherited
redirected handles for pipes; attach to the launching console when needed and
rebind streams correctly without replacing redirected stdout. Use Unicode console
I/O with UTF-8 protocol conversion, and raw UTF-8 for pipes. Do not allocate a new
console silently; if no usable input/output is available, show a useful GUI error
and keep the normal GUI usable. Native Windows checks are required; the current
Linux host has no Win64 RTL and cannot substitute for them.

## Reviewable implementation stages and checks

1. Shared typed configure/pair/query methods and named confirmation handling;
   GUI behavior parity first. Keep existing state ownership and file formats.
2. Tokenizer and command binding/formatting tests, with no LCL dependency.
3. Cancellable terminal/pipe transport and shutdown tests, including Windows.
4. Connect `--cli` dispatch to the real host; update help, built-in manual,
   work notes and changelog with implementation commit IDs.

Required acceptance coverage:

- Both games: GUI/CLI setup yields equivalent clocks, selected registration keys,
  pairing rows and per-row FENs (ignore generated names/UUIDs/paths). Actual supplied
  79-position ballot yields 158 games; test repeated FEN entries as distinct pairs.
- Parser: unknown/duplicate/conflicting options, required values, fractional
  increments, invalid/overflow/NaN numbers, locale differences, duplicate engine
  names, explicit IDs, removal/reconfiguration, mismatched games, Unicode and
  quoted Windows paths; line recovery after an error.
- Protocol: one response per command, JSON escaping, no stdout contamination,
  no pipe prompts, EOF/final line, invalid/oversized lines, broken output and
  partial reads/writes. Test with a client that keeps both pipes open and queries
  repeatedly while games run, not only a prewritten batch followed by EOF.
- Live behavior: immediate acceptance without waiting for games, visible tabs,
  row selection/PVs, GUI Stop, two concurrent commands creating two tournaments,
  shared annotator/engine reservations and oldest-waiting-first allocation.
- Queries: engine1 playing either colour; both result formats; 25 resolved games
  but 12 complete pairs; unknown/failed results, referee overrides, replay attempts,
  capture/storage errors and waiting versus stopped/completed states. Queries
  change no persistent or transient tournament state.
- Identity/lifecycle: pending query versus tab close, in-place game switch, Save As,
  rename, application shutdown while input/output is blocked, repeated CLI sessions,
  and cross-process file protection from the previous implementation.
- Compile, full chess/draughts regression and tournament suites, and
  `tests/run_gui_checks.sh` on hidden displays. Native Windows console and pipe
  testing is an explicit transport/integration gate, not an inferred Linux pass.

No build or runtime tests are claimed for this proposal-only change. Do not modify
engine directories, user game files, SCU or `/tmp2/gwies/GWDGUI`.

## Requested Claude review

Please review the small GUI seams and confirmation/error boundary first, then the
identity/counting contract and cancellable cross-platform I/O. In particular,
confirm that no grid/model/controller rewrite is necessary, queries remain
read-only, and every command-driven start uses the existing tournament execution.
Review approval should cover only the named shared changes in this proposal;
SPRT, general tournament editing and additional commands require separate work.

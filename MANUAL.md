# ZGUI User Manual

Updated 18 November 2026.

ZGUI plays, analyses and stores orthodox chess and international 10×10 draughts.
Chess uses UCI engines and PGN files; draughts uses Hub/DXP engines and PDN files.
The shared windows provide game clocks, analysis, tournaments and databases.
Choose the game through Game History or the Game choice in the game dialogs.

## Chess and draughts in one window

Use the Chess board and International draughts board entries in Game History
to select the independent standalone documents. New Game also has a Game choice.
Running games retain their own rules, clocks and engines while another game is
shown. UCI registrations belong to chess; Hub and DXP registrations belong to
draughts. The engine list shows this derived Game value.

Each game has one annotator slot. Switching games pauses the hidden slot's live
search without closing its engine; returning resumes analysis of the selected
position. Auto Play stops on navigation. Loaded hidden annotators still reserve
their engines. DXP is for playing games and cannot be an annotator.

For Hub engines that advertise a `ponder` Boolean option, enable that option in
the existing engine parameters dialog to allow pondering. ZGUI uses `go ponder`
and `ponder-hit` through the existing game engine hooks. A prediction is never
played as a move. A miss stops and drains the old search; Hub may also finish
early, in which case its result is held until the actual position matches.
Speculative evaluations do not enter game history. Engines that do not advertise
the option continue with ordinary clocked searches. UCI retains its existing
Ponder option and protocol-specific handling.

The Tournaments window holds named tabs, each with its own settings, pairings
and standings. Several chess and draughts tournaments can run at once. The Game
choice beside the tournament name changes the current tab after protecting its
existing data. Set concurrency and engine thread counts with available CPU and memory
in mind: games, annotators and tournaments can all be active together.

Open accepts PGN and PDN. When a file's game is ambiguous, choose it explicitly.
Database and tournament files are checked before changing contexts. New databases
ask for their game. Each document saves in its own format. Closing ZGUI offers to
save both standalone documents and tournament records; Cancel leaves them open.
Finish or stop a database import before replacing its window or closing ZGUI.
Board colours, notation fonts/styles, evaluation ranges and score-history colours
are independent for chess and draughts. ZGUI restores the last selected game on startup.

## Command-line interface

### Starting a saved tournament

Use the normal ZGUI executable; the tournament opens live in the Tournaments
window, using the same Play action, clocks, engine reservations and scheduler as
manual play. Both chess and draughts saved tournament JSON files are supported.

```text
zgui run_tournament file="GWD-Kingsrow.json"
zgui.exe run_tournament --file "C:\Tournaments\GWD versus Kingsrow.json"
zgui run_tournament "tournament.json"
zgui --help
zgui help run_tournament
```

Relative filenames use the directory from which you launch ZGUI. The saved file
supplies the engines, time control, concurrency, pairing and any embedded opening
ballot; the original ballot file is not needed. Configure these in the GUI and
save the tournament before launching it this way.

This continues eligible unplayed games. Completed results and referee decisions
are preserved; stopped or failed games require the existing Reschedule action.
An already-running tournament in the same window is selected without starting it
twice. The main board selects the tournament's game once. Later background games
follow the Game History rule: automatically switch only when the previously
selected game was last in the list, fully finished and in live-follow mode.
Browsing an earlier game or a clicked move preserves the current view. Select a
game row to watch its board and moves.

Help and startup errors are shown in the GUI, including on Windows. The GUI stays
open after completion, and its Stop and Save/Discard/Cancel controls keep their
normal behavior. Launching another command starts another ZGUI process; engine
reservations coordinate tournaments and annotators within one process.

A tournament snapshot and its publication file are protected against simultaneous
writing by another ZGUI process. A second process reports that exclusive access
failed. Small `.lock` sidecar files remain after closing; their presence alone does
not block opening, and operating-system locks release automatically after a crash.
Playing and saving require writable directories. An archive in a read-only folder
opens for viewing with “read-only” in its tab and caption; Play, Save, pairing,
settings edits and referee changes are disabled. Closing that view does not save
or prompt to save. A file locked by another ZGUI is still refused. Older ZGUI
versions do not participate in this protection.

### Interactive terminal and pipe commands

Run `zgui --cli` to open the normal GUI with a `zgui>` terminal prompt. On Windows,
interactive input gets its own console window so it does not compete with cmd or
PowerShell. When input is redirected, ZGUI preserves the pipe/file handles and
prints no prompt. Close ZGUI through its GUI; the dedicated console's close menu
is disabled to preserve the normal save and stop handling.

The initial commands are:

```text
list_engines
run_tournament engine1="GWD multi-cut" engine2="GWD 8.1279" ballot="ballot2.fen" time=600 moves=75
query_tournament id=1
```

`list_engines` reports registered names, session-local numeric IDs, identity keys,
game/protocol and executable availability. It does not launch engines. Names must
be unambiguous. Instead of `engine1`/`engine2`, you can use `engine1_id`/`engine2_id`
or `engine1_key`/`engine2_key`; supply exactly one selector per participant. IDs are
not reused for a new identity; refresh the list after changing an engine's path,
protocol ID, arguments or INI configuration. Identity keys can be stored in
scripts, but those changes can invalidate them too. Saved UCI option values do
not change the key or its session ID; a key is not a snapshot of engine settings.

`run_tournament` creates a two-engine match in a normal visible tournament tab and
returns its tournament ID when the existing start action accepts it. It does not
wait for games to finish or engines to become free. Both engines must belong to
the same game: UCI is chess; Hub and DXP are draughts. Without a ballot it creates
an ordinary double round-robin; a ballot creates two colour-reversed game rows per
position, preserving the position's side to move and duplicate entries.

Optional settings: `name`, `ballot`, `shuffle_opening_pairs`, `time` (seconds per period), `moves` (zero for
sudden death), `increment` (fractional seconds allowed) and `concurrent`. Omitted
clock settings use the selected game's existing GUI defaults. Use a decimal point
in commands even if GUI edits use a decimal comma. Relative paths use the launch
directory. To explicitly accept the legacy UCI shared-options-file warning, add
`allow_shared_executable=true`; no other warning is automatically accepted.
This check runs before pairing: a refusal leaves no tournament tab or files.

This interactive `run_tournament` form creates a match. The separate one-shot
startup form `zgui run_tournament file="saved.json"` opens a saved event. Do not
combine that startup command with `--cli`.

`query_tournament` reads the current event without changing its board or saved
files. Wins, draws and losses are from **engine1's perspective**, regardless of its
colour. `games_completed` counts known effective results; `*` is unresolved or
pending, never a draw. `pairs_completed` counts openings with both colour-reversed
results known. Thus 25 completed games can mean only 12 complete opening pairs.
Referee overrides count; archived replay attempts do not. Rescheduling or correcting
results can reduce these counts. IDs are valid for the current session; closed,
replaced or structurally changed events are reported explicitly.

Add `pairs=true` to request the complete pair snapshot:

```text
query_tournament id=1 pairs=true
```

Omitting pairs, or setting `pairs=false`, keeps the existing aggregate-only
response. The option accepts true or false. The extra `pairs` array contains
**every scheduled opening occurrence**, including incomplete pairs, ordered by
its saved opening number. For example, the added field can contain:

```json
{"pairs":[{"pair":1,"fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","games":[1,2],"results":[1,0.5]},{"pair":2,"fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","games":[3,4],"results":[null,0]}]}
```

This is an excerpt; the full response also contains the usual aggregate fields.
FENs use the stored starting-position spelling; ballot positions are normalized
when loaded. Each entry has:

| Pair field | Meaning |
| --- | --- |
| `pair` | One-based scheduled opening number. Duplicate FEN entries retain distinct pair numbers. |
| `fen` | Stored starting FEN shared by both games. |
| `games` | Two game numbers, in their stored scheduled row order. |
| `results` | Two corresponding scores from engine1's perspective: 1 for win, 0.5 for draw, 0 for loss, null for unfinished or unresolved. The scale is the same for chess and draughts. |

The current two-engine ballot generator schedules games 1/2, 3/4 and so on,
but pair membership is read from the saved opening number and validated against
the FEN and reversed engine colours. Completion order does not change it. Equal
FENs remain separate scheduled occurrences; no grouping or sorting by FEN is used.
Without a ballot, the two colour-reversed games form one pair.

Scores reflect the current effective results, including referee overrides;
rescheduling clears the affected score to null. Archived replay attempts are not
included. Each query rebuilds the snapshot from the existing tournament state,
and reloading the same saved event reconstructs its pair results. Session IDs
retain their existing lifetime; automatic reconnect or binding a saved event
after a ZGUI restart is separate functionality.

An external paired-SPRT runner should consume the **contiguous completed prefix**:
process pairs in pair-number order and wait when either result is null, even if
later pairs are complete. Keep the statistical hypotheses, pair-count categories,
likelihood calculation and stopping decision in that runner, or request the shared
calculation with `sprt=true` (see below). At its first boundary
crossing, record the deciding pair and call `stop_tournament`; any later finished
games remain in ZGUI's match record outside that decision sample. ZGUI does not
automatically stop at an external decision boundary.

Add `sprt=true` to include the live pane's calculation:

```text
query_tournament id=1 pairs=true sprt=true
```

The optional `sprt` object uses the candidate/baseline and hypotheses currently
selected in that tournament tab. Its perspective can differ from the ordinary
engine1 aggregate and `pairs` array. Omitted or false leaves the response unchanged.
`sprt` accepts true or false. Available reports contain:

| Field | Meaning |
| --- | --- |
| `available`, `model` | Availability and `paired-logistic-v1` (paired logistic-Elo GSPRT). An unavailable report contains `reason`. |
| `candidate_key`, `baseline_key` | Exact engine registration identities selected in the pane. |
| `elo0`, `elo1`, `alpha`, `beta`, `mode` | Current design and provenance, described in section 7.7. |
| `counts` | Five counts in pair-score order: 0, 0.5, 1, 1.5, 2. Only the decision sample counts. |
| `pairs_total`, `pairs_complete`, `pairs_included`, `prefix_complete` | Scheduled, complete, included and contiguous-complete-prefix pair counts. |
| `waiting_at_pair` | First unfinished pair number, or 0 if none. |
| `later_complete` | Complete pairs outside the included sample. |
| `llr`, `lower_bound`, `upper_bound` | Current generalized log-likelihood ratio and decision boundaries. |
| `decision`, `decision_pair` | `continue`, `h0` or `h1`; first crossing's opening number (0 before crossing). |
| `automatic_stop` | Always false. The external runner may call `stop_tournament`. |

Querying does not edit saved files. The current interactive IDs still refer only
to CLI-created two-engine matches. The GUI pane also supports selecting a
head-to-head comparison inside a multi-engine tournament. Changing a CLI match's
schedule retains the existing `MATCH_CHANGED` protection.

Query states are `error`, `stopping`, `completed`, `running`, `waiting`, `attention`
or `stopped`, with that precedence. The response includes total/completed/active/
pending/unresolved games, complete pairs, wins/draws/losses, referee-result count and
a reason. `attention` means an unresolved stopped/failed row needs referee action.
GUI Stop and normal referee controls remain available. A GUI modal dialog causes
commands to return `BUSY`; retry after it closes. In `--cli` sessions, engine-failure
notices appear in the existing analysis log without a blocking popup. Ordinary
GUI sessions keep their engine-problem dialogs. New background games use the
same conditional automatic-follow rule as Game History.

`stop_tournament id=N` requests the same asynchronous Stop action as the GUI
button for that CLI-created tournament. The `OK` JSON acknowledgement contains
`command` and `tournament`; it does not wait for engines to finish. Poll
`query_tournament id=N` until `games_active` reaches zero and the state is no
longer `stopping`. Stopped active games use **Referee stopped tournament** and
remain unresolved for referee action; completed results and unplayed rows are
preserved. The tab stays open. Stopping a queued tournament removes its waiting
request without launching its games. Repeated stops are harmless. Other
tournaments continue. Unknown, closed or replaced tournament IDs are refused,
and an open modal dialog returns `BUSY`, just as for other commands.

Each nonblank command receives one physical UTF-8 line: `OK ` or `ERROR ` followed
by JSON. Lists are JSON arrays in that one response. Prompts go to stderr only
when input and output are terminals. Ordinary RTL/Lazarus stdout is redirected
to stderr before GUI initialization; only protocol responses use the original
stdout. Keep stderr separate from stdout in scripts (do not merge them with
`2>&1`). Engine processes retain their own protocol pipes.
For automation, keep stdin/stdout pipes open, send commands, read one response per
command and poll `query_tournament`. Input EOF detaches command input and leaves
ZGUI and its tournaments open; do not wait for application exit as a completion
signal. On Unix, Ctrl+C at the prompt cancels the input line while engines continue;
background terminal input waits until the job is foreground. Ctrl+D ends Unix
input; on Windows use Ctrl+Z then Enter. Closing the GUI cancels blocked terminal
I/O and follows the existing save/stop dialogs.

Command text accepts single and double quotes. Unquoted backslashes are literal,
so `ballot=C:\Matches\ballot2.fen` works. Inside double quotes only `\"` and `\\`
are escapes; other backslashes remain literal. Single quotes preserve all
backslashes, useful for UNC paths: `ballot='\\server\share\my ballot.fen'`.
Commands are single-line, at most 64 KiB, with LF or CRLF endings. Invalid UTF-8,
NUL bytes, malformed quoting and oversized lines are rejected; processing resumes
at the next line. There is no shell execution, completion/history, CLI quit
command or automatic SPRT stopping in this version.

Stable error codes: `BAD_ARGUMENT`, `UNKNOWN_ENGINE`, `AMBIGUOUS_ENGINE`,
`GAME_MISMATCH`, `BUSY`, `CONFIGURE`, `PAIRING`, `STORAGE`,
`CONFIRMATION_REQUIRED`, `START`, `UNKNOWN_TOURNAMENT`, `TOURNAMENT_REPLACED`,
`MATCH_CHANGED`, `TRANSPORT`, `SHUTDOWN` and `INTERNAL`. Messages give details.
If a failure leaves an already-published event, its error response identifies the
retained tournament and file. Invalid unpublished setups are discarded.

Native Windows console/pipe validation remains outstanding for this release.

#### Interactive CLI command and parameter reference

Start the normal GUI and its interactive command input with `zgui.exe --cli`
on Windows or `./zgui --cli` on Linux. The same commands work through pipes.

| Command | Parameters | Purpose |
| --- | --- | --- |
| `list_engines` | None | List registered engines, their session IDs, keys, names, protocols, game and executable availability. Does not launch engines. |
| `run_tournament` | Two engine selectors; optional settings below | Create and start a two-engine match in a normal tournament tab. Returns immediately with a tournament ID. |
| `query_tournament` | Required `id=N`; optional `pairs=true`, `sprt=true` (both default false) | Read the current state of the CLI-created tournament with that returned ID. Repeat to monitor progress. |
| `stop_tournament` | Required `id=N` | Request the GUI Stop action for that tournament; return immediately and keep its tab/results. Query to monitor shutdown. |

Parameters for `run_tournament` use `name=value` syntax. Quote values containing
spaces. Supply exactly one selector for each engine:

| Parameter | Value and meaning |
| --- | --- |
| `engine1="Name"` | First engine's unambiguous registered name. |
| `engine1_id=1` | Alternatively, first engine's session ID from list_engines. |
| `engine1_key="..."` | Alternatively, first engine's identity key from list_engines. |
| `engine2="Name"` | Second engine's unambiguous registered name. |
| `engine2_id=2` | Alternatively, second engine's session ID. |
| `engine2_key="..."` | Alternatively, second engine's identity key. |
| `name="Test match"` | Optional tournament name; generated automatically when omitted. |
| `ballot="C:\Matches\ballot2.fen"` | Optional opening-position file (`.fen` for either game; `.epd` also accepted for chess). Omit for a double round-robin from the game's default starting position. Relative paths use the launch directory; an explicitly empty filename is rejected. |
| `shuffle_opening_pairs=true` | Shuffle ballot entries before creating pairings, keeping both colour-reversed games together. Accepts true or false; default: false. True requires a ballot. The actual order is saved and reused on load, resume and SPRT replay. |
| `time=300` | Positive finite number of seconds per time-control period, not minutes. Omitted: selected game's GUI default. |
| `moves=75` | Nonnegative integer moves per period; 0 means sudden death. Omitted: selected game's GUI default. |
| `increment=3` | Nonnegative finite increment in seconds; decimal values such as 0.5 are accepted. Omitted: selected game's GUI default. |
| `concurrent=1` | Positive integer maximum simultaneous games. Default: 1. Engine reservations can limit actual concurrency. |
| `allow_shared_executable=true` | Accept legacy UCI registrations that still inherit one executable-side options file. Accepts true or false; default: false. Registrations saved with private options do not need this confirmation. |
| `time_forfeit=loss` | Default rules-based timeout policy, including chess timeout draws. Alternatively, use a unique compatible Hub/UCI engine name for symmetric evaluation adjudication. |
| `time_forfeit_id=3` | Select the adjudicator by session ID instead of its name; supply only one time-forfeit selector. |
| `time_forfeit_key="..."` | Select the adjudicator by identity key instead of its name or ID. |
| `adjudication_time=1.0` | Positive finite analysis time in seconds, at most 3600; default 1.0 when an adjudicator is selected. Requires an engine policy. |
| `adjudication_threshold=200` | Positive finite evaluation threshold in cp, at most 1000000000; default 200 when an adjudicator is selected. Requires an engine policy. |

Both registrations must be distinct and belong to the same game: UCI means chess;
Hub and DXP mean draughts. A ballot creates two colour-reversed games per position.
Without a ballot, the match has two colour-reversed games. Use decimal points in
commands, regardless of the GUI's local decimal separator.

```text
list_engines
run_tournament engine1_id=1 engine2_id=2 name="Test match" time=300 moves=0 increment=3 concurrent=1
query_tournament id=1
```

Replace the engine IDs and use the tournament ID returned by run_tournament.
Query response fields are:

| Field | Meaning |
| --- | --- |
| `command`, `tournament` | Command name and tournament's session ID. |
| `state`, `reason` | Current state and its explanation. |
| `games_total`, `games_completed`, `games_active`, `games_pending`, `unresolved_games` | Counts of all games, known effective results, active games, pending games and unresolved stopped/failed games. |
| `pairs_total`, `pairs_completed` | Total opening pairs and pairs with both results known. |
| `wins`, `draws`, `losses` | Results from engine1's perspective, regardless of colour. |
| `referee_results` | Number of games with an effective referee result override. |
| `sprt` | Present only with sprt=true: the live pane's current GSPRT design and evidence report (section 7.7). |
| `pairs` | Present only with pairs=true: all scheduled pairs with opening number/FEN, game numbers and normalized engine1 scores. |

Each response is one `OK ` or `ERROR ` line followed by JSON. Engine and tournament
IDs belong to the current ZGUI session; a new process starts a new session.

Separate startup forms, entered at the operating-system shell rather than at
the interactive prompt, are:

| Startup command | Purpose |
| --- | --- |
| `zgui.exe --cli` | Open the GUI and interactive terminal/pipe input. |
| `zgui.exe run_tournament file="C:\Matches\tournament.json"` | Open and start a saved tournament. Also accepts `--file "path"` or a positional filename. |
| `zgui.exe --help` | Show command-line help in the GUI. |
| `zgui.exe help run_tournament` | Show help for saved-tournament startup. |

Use `./zgui` instead of `zgui.exe` on Linux. Do not combine startup modes. The
interactive run_tournament command creates a match; its startup namesake takes
only a saved file. There are no interactive quit, engine-registration or SPRT commands. Use
stop_tournament or the GUI to stop tournaments; close ZGUI through its GUI.

Interactive `run_tournament` also accepts `time_forfeit=loss` (default) or a unique
Hub/UCI engine name, `adjudication_time=1.0` (seconds), and
`adjudication_threshold=200` (cp). The last two require a selected adjudicator.
Use `time_forfeit_id` or `time_forfeit_key` instead of its name if ambiguous.
See **Time forfeit adjudication** in section 7 for the outcome and reason rules.

#### Testing the interactive CLI on Windows

These steps are a native Windows QA checklist; they do not imply that Windows
validation has already been completed. Rebuild the latest ZGUI with `build.bat`
before testing. Register two available engines for the same game through
**Engines...** first.

1. Open PowerShell in the ZGUI directory and start:

   ```powershell
   .\zgui.exe --cli
   ```

   Expect the normal GUI and a separate console with a `zgui>` prompt. Enter the
   following commands in that new console, not at the PowerShell prompt.

2. List the registered engines:

   ```text
   list_engines
   ```

   Expect `OK` followed by JSON. Choose two available engines of the same game
   and use their returned IDs in place of `1` and `2` below.

3. Start a short tournament:

   ```text
   run_tournament engine1_id=1 engine2_id=2 name="Windows CLI test" time=30 moves=0 increment=0 concurrent=1
   ```

   This creates two colour-reversed games, each with 30 seconds per player and
   no increment. Expect a normal tournament tab and an immediate `OK` response
   containing `"tournament":N`; the command does not wait for completion.
   If legacy UCI registrations share one options file, retry with
   `allow_shared_executable=true` appended to explicitly accept that configuration.
   The refused attempt should leave no extra tab or pairing files.

4. Query the returned tournament ID (replace `1` if necessary):

   ```text
   query_tournament id=1
   ```

   Repeat while it runs. Check `state`, `games_completed`, `pairs_completed`,
   `wins`, `draws` and `losses`. Results are from engine1's perspective. After
   both games finish with known results, expect two completed games and one
   completed pair. Unresolved `*` results do not count as completed.

5. To test an opening ballot, use an existing file and suitable engine IDs:

   ```text
   run_tournament engine1_id=1 engine2_id=2 name="Ballot test" ballot="C:\Matches\ballot2.fen" time=600 moves=75 increment=0 concurrent=1
   ```

   Each position produces two games with colours reversed. This works with
   either chess or draughts ballots and two engines for that game. Add the
   shared-executable option when applicable, then query the new returned ID.

6. Check interaction with the live GUI:

   - Click a tournament game row to watch its board, moves and PV.
   - Enter `stop_tournament id=N`, substituting the returned ID, then query again.
     Active games should drain to zero; the tab and results remain available.
     Repeat the stop to check that it is harmless. Test the GUI **Stop** button
     with another match as well.
   - Open Preferences and issue a command. Expect `ERROR` with code `BUSY`;
     close Preferences and retry successfully.
   - Press **Ctrl+Z**, then Enter in the CLI console. Input should end while
     the GUI and its tournaments remain open.
   - Close ZGUI through its GUI and check the normal save/discard/cancel handling.

7. Test pipes from **cmd.exe**, in the ZGUI directory:

   ```bat
   echo list_engines | zgui.exe --cli > replies.txt 2> diagnostics.txt
   ```

   `replies.txt` should contain one complete `OK` JSON response, without a prompt,
   banner or Lazarus messages. Diagnostics belong in `diagnostics.txt`; do not
   merge stderr into stdout with `2>&1`. Input EOF should leave the GUI open.
   Close it normally before the next test.

   For a multi-command test, create a UTF-8 text file without a BOM named
   `commands.txt`, with the following lines, substituting the two engine IDs. In this fresh process,
   the first successfully created CLI tournament has ID 1:

   ```text
   list_engines
   run_tournament engine1_id=1 engine2_id=2 name="Pipe test" time=30 moves=0 increment=0 concurrent=1
   query_tournament id=1
   ```

   Append `allow_shared_executable=true` to the tournament command if required.
   Then run from cmd:

   ```bat
   type commands.txt | zgui.exe --cli > replies.txt 2> diagnostics.txt
   ```

   Expect exactly three complete response lines. The query is an immediate
   snapshot, not a wait for completion. For repeated polling, a client must keep
   stdin/stdout pipes open and send further queries in the same ZGUI process.
   Launching a new process does not retain the previous session's IDs.

For the stdout-isolation regression check, create and query at least five
successful tournaments in one pipe session. Every stdout line, including through
normal GUI shutdown, must be a complete `OK ` or `ERROR ` JSON response, with no
partial diagnostic text. Also check GUI close with idle input or a client that
stops reading responses. The transport helper and further Windows checks are
described in `tests/CLI_WINDOWS_TRANSPORT_CHECK.md`.

## 1. Getting started

When ZGUI starts, the main window shows:

- the selected chess or draughts board and clocks;
- **Game History** and the legal moves for the displayed position;
- player names, result, FEN, and the game notation;
- the engine and annotator analysis areas;
- a score-history graph and evaluation bar;
- buttons for **Engines...**, **New game...**, **Tournament...**, analysis time,
  and **Auto Play**.

The bottom status bar shows **Engines in use**, split into games and annotators,
across both games and every tournament tab. Each engine player counts once,
including idle opponents and pondering; humans and queued pairings add nothing.
Annotators include hidden game slots and the MCTS annotator. Auto Play reuses its
annotator and adds no separate engine. Starting and stopping sessions count until
their owners finish releasing them. Remote DXP opponents are included; temporary
engine-configuration probes are excluded. This is a session count to help judge
oversubscription, not a thread count or a measurement of CPU usage. Hover over the
readout for its counting rules.

The splitters let you resize the notation and analysis areas. Ten notation lines
are preferred when space permits; smaller windows can reduce the notation to
three lines. The initial main-window height is limited to the screen's work area.

Chess uses an 8×8 board and SAN game notation; its legal-moves list uses UCI
coordinates. Draughts uses a 10×10 board and numbered-square notation. Click a
piece and destination to play, or choose a legal move. Chess promotion opens the
existing move chooser. Press **F** to flip the board. Both games draw their
pieces directly; no external piece font is required.

Before playing against an engine or running a tournament, register the engine
through **Engines...**. Human-versus-human games can be started immediately.

The standard international-draughts starting position is:

```text
W:W31-50:B1-20
```

## 2. Configuring engines

Open **Engines...** from the toolbar. The engine list shows each executable and
its Hub, UCI or DXP identity. The executable and ID columns fit
their titles and values using their respective fonts, plus a margin; the path column fills the remaining width. Resize the
window or columns as needed. Hover over a data cell to see its complete value,
including the engine path even when it fits in the column.

Right-click the list to:

- **Add engine**;
- **Delete engine**.

Double-click an existing entry to edit it. Engine identities must be unique
within the same protocol. DXP engines must not be configured to use the same
local port at the same time.

Engine executables may live outside the ZGUI directory. ZGUI launches the
registered path, with the engine's own directory as its working directory.
UCI registrations saved by the current editor have independent option values,
even when they use the same executable. Hub/DXP settings and unmigrated UCI
registrations still use the executable-side parameter file; see section 2.6.

### 2.1 UCI engines (chess)

Register a chess engine through the existing editor:

1. Open **Engines...**, add an engine, choose **UCI**, and select its executable.
2. Enter any required launch arguments. Use the INI/configuration editor if the
   engine needs a configuration file; ordinary UCI engines need no startup script.
3. Click **Launch engine**. Discovery runs in the background; **Cancel** interrupts
   an unresponsive handshake. The parameter grid retains saved values and shows
   advertised check, spin, combo, string and button options. Double-click a button
   option's value cell to invoke it once. Buttons are never replayed on startup.
4. Click **Launched correctly** to save, then right-click the analysis area and
   select the engine under **Open Annotator**. The existing seconds field controls
   each finite analysis search. Browsing a different position stops the old search
   before starting another. Use **Close Annotator** to release the engine.

The line above the annotator PV shows its score, depth and time using the same
information format as the engine PV. It follows the displayed PV and clears
when the annotator closes.

Scores are from White's point of view: pawn units for ordinary evaluations and
`#N` for mate. The score history maps positive/negative mate scores to its configured
maximum/minimum while preserving their mate distance in tooltips. Only exact primary-line scores with a legal PV are stored; bounded and
secondary lines remain in the engine log. A score/depth update still appears when
its PV is unchanged. PVs and hints use existing navigation and never become
played moves or variations. Ponder is forced off for discovery and analysis;
UCI_Chess960 stays off, MultiPV is 1, and UCI_AnalyseMode is on for analysis and
off for games when advertised. Other saved options match
names without case sensitivity, while commands use the engine's spelling.
Unknown saved options are retained but not sent. Initialization accepts only
empty lines, `debug on`, `debug off` or `register later`; use the grid for options.
Saved UCI options belong to their engine registration. Hub/DXP options and
legacy UCI files retain their separate JSON protocol sections (section 2.6).

Pondering in ordinary games is described in section 5.7. Tournament policy is
covered in section 7.

### 2.2 Hub engines (draughts)

In the engine editor:

1. Select the engine executable with **Browse**.
2. Set **Type** to `hub`.
3. Enter the Hub ID and any required launch arguments.
4. Click **Launch engine**.
5. Review the startup log and parameters reported by the engine.
6. Click **Launched correctly** to save the registration and parameter values.

ZGUI starts the executable in the executable's own directory, initiates the
Hub protocol, applies the configured non-GUI parameters, and initializes the
engine. Hub initialization is automatic: ZGUI sends `hub`, applies the engine parameters,
then sends the mandatory `init` command and waits for `ready`. The retired
`gui-hub-init` setting is no longer shown or used; old values are ignored.
Closing the editor stops an engine that was launched for this test.

Hub engines can be used as players and annotators. A Hub engine can also be
offered as an MCTS annotator when `gui-engine-supports-mcts` is enabled.

### 2.3 DXP engines (draughts)

For a DXP engine:

1. Select the executable.
2. Set **Type** to `DXP`.
3. Enter a DXP ID.
4. Set the host, normally `127.0.0.1` for a local engine.
5. Set the port, commonly `27531` unless the engine requires another port.
6. Choose the role:
   - `listen`: ZGUI waits for the DXP peer to connect;
   - `connect`: ZGUI connects to the configured host and port.
7. Enter any required launch arguments.
8. Click **Launch engine** and inspect the connection log.
9. Click **Launched correctly** after the test succeeds.

Use a separate port for each simultaneously active DXP connection. Enable
`gui-dxp-supports-fischer` only when the engine really supports Fischer
increment through DXP.

DXP host fields accept dotted IPv4 addresses and `localhost` (mapped to
`127.0.0.1`); DNS names and IPv6 are not supported. A listener bound to loopback
accepts only local peers. `gui-dxp-peer-ip` can further restrict the peer of a
live game listener and the registration connection test.

For a client engine such as Scan, choose ZGUI's **listen** role: ZGUI opens its
listener before starting the executable. Configure Scan to connect as a client;
Scan's `dxp-server = true` mode is not supported by Scan. In ZGUI's **connect**
role, the peer must provide the listening socket. Consult the engine's own
configuration for its DXP command-line arguments or startup mode.

DXP is for playing games and cannot be selected as an annotator. DXP game
messages do not themselves carry analysis PVs.

A received DXP game-end reason means: `0` unspecified, `1` resignation,
`2` draw claim, `3` win claim. Stop code `0` permits another game; `1` requests
that the session end. Only resignation directly concedes a result. Other claims
are checked by the shared game rules; a log entry with `result=*` means no final
result was assigned by the DXP adapter. The tournament Reason column preserves the
engine's name and colour, interpreted termination reason and raw code, for example
**GWD (Black) claimed draw (DXP reason 2)** or
**GWD (White) ended game (DXP reason 0)**. Unknown codes retain their number. A draw or win claim
may therefore have result `*` and a known reason; the reason is not acceptance
of the claim. Actual game errors take precedence. The raw code and source also remain in the log.

### 2.4 Launch arguments and configuration files

An engine may have an associated INI or configuration file. The editor can
open and edit its contents. The following placeholders are expanded in launch
arguments and supported configuration text:

- `{ip}` or `{host}`: the configured host;
- `{port}`: the configured port.

This is useful for engines that need their socket settings in a command-line
argument or generated configuration file.

### 2.5 Engine parameters

Hub and UCI options appear in the parameter grid after a successful launch.
Values are applied through the selected engine protocol. Names beginning with
`gui-` belong to ZGUI and are never sent as engine options. Current UCI options
are saved per registration; Hub/DXP and legacy UCI parameter files keep separate
protocol sections, as described in section 2.6.

Important GUI parameters include:

| Parameter | Meaning |
| --- | --- |
| `gui-feature-flags` | GUI compatibility flags as a JSON string; click its name or value to edit checkboxes |
| `gui-engine-type` | Engine protocol: `hub`, `dxp` or `uci` |
| `gui-uci-id` | UCI identity used by ZGUI |
| `gui-uci-launch-arguments` | UCI command-line arguments |
| `gui-hub-id` | Hub identity used by ZGUI |
| `gui-hub-launch-argument` | Hub command-line arguments |
| `gui-dxp-id` | DXP identity used by ZGUI |
| `gui-dxp-ip` | DXP dotted IPv4 host, or `localhost` |
| `gui-dxp-peer-ip` | Optional allowed peer IPv4 for game listeners and the registration connection test |
| `gui-startup-timeout-ms` | Engine startup timeout; 0 means 60,000 ms; effective range 1,000–300,000 ms |
| `gui-dxp-socket` | DXP port |
| `gui-dxp-role` | `listen` or `connect` |
| `gui-dxp-launch-arguments` | DXP command-line arguments |
| `gui-dxp-supports-fischer` | Whether the DXP engine supports increment |
| `gui-ini-file` | Optional engine configuration file |
| `gui-send-starting-position` | Whether the starting position is sent explicitly |
| `gui-engine-supports-mcts` | Makes a Hub engine available as an MCTS annotator |
| `gui-score-perspective` | Perspective of scores reported by a Hub engine |

`gui-score-perspective` tells ZGUI how to convert an engine score to White's
perspective:

- `side-to-move`: a score is good for the side to move; scores are negated when
  Black is to move;
- `white`: the reported score is already from White's perspective;
- `black`: the reported score is from Black's perspective and is negated.

Choose this setting to match the engine's protocol output. An incorrect choice
causes the evaluation graph to change sign on the wrong moves.

Hub parameter values cannot contain a double quote (`"`); the protocol has no
escape for it. ZGUI rejects double quotes and line breaks in Hub parameters
before saving the engine settings and names the parameter to correct. Command-line
arguments are separate settings and may contain quotes. Hub initialization is
automatic; there is no configurable Hub initialization field.

Older parameter files may contain `gui-single-captures-include-captured-square`;
it does not control current capture notation. Capture paths are determined from
the legal position. The retained `gui-evaluation-bar-depth-min` and
`gui-evaluation-bar-score-max` entries do not control the current graph.

The current score graph takes its display maximum and scale from **File >
Preferences**. The seeded per-engine `gui-evaluation-bar-*` values are retained
in parameter files for compatibility but are not the current graph controls.

The `gui-feature-flags` value is a JSON array of names, for example
`["no-ponder-hit", "dxp-pv"]`. Its checkbox editor preserves additional unknown
flags; Cancel leaves the original value unchanged. These flags are GUI settings,
not advertised engine options:

- **no-pondering**: disable speculative searches for this Hub or UCI engine,
  even when its saved Ponder option is enabled. This takes precedence over
  **no-ponder-hit**.
- **no-ponder-hit**: allow pondering, but stop and restart from the actual position
  even when the predicted reply matches. Do not send `ponderhit` (UCI) or
  `ponder-hit` (Hub).
- **dxp-pv**: during a DXP match, read Hub-format `info` lines from the local
  engine's stdout for PV, evaluation, depth and time. This works with GWD's
  Hub-format stdout; it does not parse arbitrary other engine formats. Moves and
  game-end claims still come exclusively from the DXP socket. This does not make
  a DXP engine an annotator. Scores use `gui-score-perspective`, as for Hub.

The earlier development spelling `gui-gwd-dxp-pv` remains readable and is saved
as `dxp-pv` when accepted in the checkbox editor. All flags default to off.


### 2.6 Where engine settings are stored

ZGUI stores the engine registry in `engines.json` beside the ZGUI executable.

- **UCI:** after accepting the engine editor, option values are saved in that
  registration's `uci_options` array in `engines.json`. Two registrations of one
  executable can use different Hash, Threads or strength settings. Identity,
  launch arguments and INI text remain in the registration's existing fields.
- **Existing UCI registrations:** if `uci_options` is absent, ZGUI reads the old
  executable-side `.params.json` file's `uci` section. Saving that registration
  in the editor migrates only its values; the legacy file is left unchanged.
  An explicitly empty private array uses defaults rather than inheriting the file.
- **Hub and DXP:** parameters remain beside the engine executable, using its
  name with extension `.params.json` and separate `hub` and `dxp` sections.
  Registrations sharing that file also share those saved settings.

Back up `engines.json`, any legacy/Hub/DXP parameter files and external INI files
when moving an installation. Older ZGUI builds ignore private UCI options, so
update the Windows and Linux executables together. Private options do not isolate
files an engine writes beside its executable; use separate directories if that
engine's logs or learning files cannot safely be shared.
Engine paths in `engines.json` belong to one operating system; a copy from
another system has to be re-registered (see section 11).

## 3. Starting and playing a game

Click **New game...**. Configure:

- the starting FEN;
- White and Black as **Human** or a registered engine;
- moves per period (`0` means sudden death);
- minutes per period;
- increment in seconds;
- increment mode, **From start** or **After move limit**.

Defaults depend on the game: chess starts at **0 moves / 5 minutes / 3 seconds
increment**; draughts starts at **75 moves / 5 minutes / 0 seconds increment**.
“0 moves in 5 minutes” gives five minutes for the whole game, plus the configured
increment after each completed move. A positive move count uses repeating periods.
The Starting FEN field selects the initial position; leave the game's default
FEN for the normal start. Only compatible engines are offered.

The same engine instance cannot play both sides, and an engine that is already
busy is not available. Click the dialog's start button to create the game.

Engine startup and initialization happen before the game clock is charged. The
playing clock starts when the game itself starts, so engine load time is also
excluded in tournament games.

The fullmove number in a custom chess FEN does not count as moves already
played in the new clock session. Unreadable or invalid time fields are reported;
they are not silently replaced by defaults. Busy engine registrations stay out
of the player lists, including an engine already used as an annotator.

The existing board, legal-moves list, promotion chooser, game list, clocks,
**Stop**, replay and PGN save paths are reused. Engine PVs can update during a
search with raw stdout hidden; they remain analysis rather than played moves.
Both human and engine clocks count down, including for an engine that emits no
output. Viewing clocks never changes game-tree data or adjudicates a flag.

The inherited clock policy adds the increment due on a completed move before
checking expiry; the idle-human allowance uses that same policy. **After move
limit** starts increment credit at the threshold move and keeps it thereafter.
A new period is earned only by an on-time completed move. Human flags are checked
on the existing polling cadence. Stopping a search retains an unfinished `*`
result and accounts for elapsed engine time without accepting a move. An engine
crash or invalid protocol response stops the game with an error and `*`, with
the reason in the game log; it is not awarded as a time loss. Ordinary flag
results use the existing chess timeout/material rules.

Initial terminal positions finish without waiting for a move. The existing chess
rules automatically accept threefold/50-move draw claims as soon as available,
including a legal intended move; there is no new claim dialog. The dead-position limits are explained below.

### 3.1 Making a human move

Click the source square and then the destination square. ZGUI accepts only a
legal move for the displayed position. You can also click a move in the
**Legal moves** list.

When several captures share a source and destination, board clicks open a chooser
showing their distinct PDN paths. Select a path and choose **Play move**, or
**Cancel** to leave the position unchanged. The legal-move list also lets you
select the exact move.

Press `F` to flip the board.

### 3.2 Managing games

The **Game History** list can hold multiple live, stopped, and finished games.
Right-click a game to use the available actions:

- **New game...**;
- **Replay game**;
- **Show stdout**;
- **Stop game**;
- **Remove game**.

Replay starts another game with the same players and setup when the required
engines are available. Stopping a game makes it available for browsing and
analysis features such as Auto Play.

Selecting a running game follows its current position. Selecting a stopped or
finished game lets you inspect its game tree and move history.

When a new background game is posted, ZGUI automatically selects it only if all
three conditions held before its row was added:

- the selected game was the last entry in Game History;
- that game had fully finished, including runner shutdown; and
- its view was in live-follow mode, without move/variation/PV browsing.

Clicking in the move list pauses automatic switching, **even when the clicked
move is the last move**. Return to live-follow mode with Escape in the main move
view to allow following again. Selecting an earlier game, an earlier position,
a variation or a PV preserves that view when another game arrives. An ongoing or
still-stopping game also remains selected. After newer games have arrived during
browsing, select the latest list entry and resume live following to follow
subsequent arrivals. This rule applies across tournament
tabs and across chess and draughts, using the existing game and board selection.
An explicit **New game...** or replay action still selects its new game normally.

### 3.3 How games end

ZGUI uses the selected game's legal position and clocks. The game log records
why play ended. Stopping a game leaves it unfinished unless a final result was
already established; engine/protocol errors are reported rather than silently
awarded as time losses.

In **chess**, checkmate wins and stalemate draws. Fivefold repetition and the
75-move rule are automatic draws. ZGUI also accepts available threefold and
50-move claims immediately, including claims through an intended legal move;
there is no separate claim button. Checkmate takes precedence on the last move.
A timeout is a draw if the opponent cannot mate under the implemented material
checks. Insufficient-material checks cover the supported simple dead positions;
arbitrary locked-pawn fortresses and all possible dead positions are not solved.

In **draughts**, having no legal move loses. The implemented draw rules are:

- the same position, including the side to move, occurring three times;
- 25 moves by each side consisting only of non-capturing king moves; a capture
  or a man move resets this counter;
- a 16-move limit per side once three pieces, including at least one king,
  face a lone king;
- a five-move limit per side once one or two pieces, including a king,
  face a lone king.

The endgame limits start when the material condition is first reached; captures
do not restart an already active 16-move count. A win by leaving the opponent
without a legal move takes precedence on the final allowed move.

A DXP resignation concedes the game. A peer's other win/draw claims do not award
an official result; if communication ends without an independently established
result, the game can remain `*`. Stopping a game also leaves it unfinished;
Stop does not replace an already completed result.

## 4. Browsing games and variations

Click a move in the notation to display the position after that move. Place the
caret before the first move to display the starting position. A click to the right
of a line's end places the caret at the end of that line.

While the move list has focus:

- `Left Arrow` moves to the previous game position;
- `Right Arrow` moves to the next game position;
- `Escape` returns to the live or final game position.

Engine PVs, annotator PVs, and imported PGN/PDN variations are displayed between
parentheses with move numbers. Clicking a move in a variation enters variation
browsing. The arrow keys then cycle through all variation positions, including
the position before its first move. Press `Escape` to leave variation browsing.

Analysis may continue for the position being browsed, but browsing an engine or
annotator PV does not add its moves to the structural game tree.

Board moves at the end of an unfinished standalone or stopped game extend its
mainline. Moves from an earlier position create or follow a variation. After a
completed result, further board moves are saved as continuation variations;
the official mainline and result remain unchanged.

### 4.1 Move-list display options

Right-click the move notation to show or hide:

- comments and annotations;
- engine scores;
- annotator scores;
- the engine PV move or full PV;
- the annotator PV move or full PV;
- clock information;
- the Game Tree window.

If both full PV options are enabled, the two variations can appear next to each
other. They remain separate analysis lines.

Analysis lines, including first-move-only displays, appear **after the actual move
played** from their source position. If no continuation has been played yet, the
analysis remains at the end of the notation (or at the initial position for an
empty game). Clicking a displayed PV still replays from its original source
position; moving its text does not change the game or saved game data.

### 4.2 The Game Tree window

The Game Tree window shows each line as a column of moves. Variations are marked
and nest under the move they replace, so indentation follows variation depth
rather than move count. The context menu can switch to the original layout,
"Show each move under the previous move"; this choice lasts for the current
session. Selection and expanded branches are retained when the view refreshes.

Nodes can show engine scores and PVs, annotator scores and PVs, Auto Play PVs,
and clock information.

Click a node to show its position on the main board and select its move in the
notation. The tree window, notation and board share the same selection. Use
Left/Right to follow parents and continuations; stepping back and forward retains
the chosen branch. Press `Escape` to resume following the current game. If a
selected branch is removed, selection returns to its nearest surviving ancestor.
The tree window's context menu can copy the tree in its PGN or PDN format.

### 4.3 Delete from here

Open **Show game tree**, select a real move and use **Delete from here...** in
its popup menu. Confirm to delete that move and every continuation beneath it,
including nested variations. The parent becomes selected. Other siblings and
all earlier moves, comments, clocks, evaluations and the header result remain.
The result is not automatically changed after this edit. Save the edited game
through the existing PGN/PDN save action when wanted.

The root cannot be deleted. The action is available for standalone games and
fully finished game runners, never while playing or stopping or viewing a
virtual PV. Auto Play and active analysis are stopped before confirmation;
annotation resumes for the retained position. Cancel leaves the moves intact.
There is no undo for a confirmed deletion. Old runner snapshots cannot restore
removed moves when switching away and back in Game History. Editing the history
tree does not rewrite an already archived tournament game automatically.

## 5. Analysis

### 5.1 Loading an annotator

Right-click the annotator analysis area and choose a registered engine from
the **Open Annotator** submenu (UCI for chess, Hub for draughts). Use
**Close Annotator** to stop it.

The annotator analyzes the position currently displayed on the main board,
including a position selected while browsing. Its score and PV are stored as
analysis attached to the relevant game-tree node.

Only engines compatible with the selected game are offered. An annotator engine
is reserved while loaded and therefore cannot simultaneously be selected for an unrelated
game that requires the same engine instance.

### 5.2 Analysis time

The edit box between **Tournament...** and **Auto Play** contains the analysis
time in seconds. Its default is `1`. This value controls UCI annotator analysis
and one-move requests such as Auto Play searches (`go movetime`). A missing,
invalid, or non-positive value is treated as one second. When analysis finishes,
the annotator stays loaded and its final score and PV remain visible. Changing
the position or editing this time starts a new analysis search.
Long analysis budgets are not capped by the game engine's move timeout: the
annotator watchdog allows the requested duration plus its stop allowance. Clocked
games retain their own move deadline.

During UCI annotation and Auto Play, an engine's advertised `OwnBook` check
option is temporarily disabled so it searches and reports a scored PV. Some
engines, such as Arasan, otherwise return an opening-book move without analysis.
Clocked games restore the saved book setting (or the engine's advertised default);
the saved option values are unchanged.

### 5.3 Engine and annotator PVs

The engine PV belongs to the engine playing the game. The annotator PV belongs
to the separately loaded annotator. Both are attached to their source nodes and
can be displayed as browsable notation variations.

Right-click the main board and choose **Show hints from main PV**, **Show hints
from annotator PV**, or **Do not show hints**. These three options are mutually
exclusive; main PV is the default. Hints appear only when the selected PV belongs
to the displayed position. **Do not show hints** clears the PV hints while keeping
the last-move marker and normal move-selection highlights.

Each hinted move outlines both its source and destination squares. The first PV
move uses the configured **PV move** color; the opponent's reply uses the configured
**Hint move** color. The two squares of a move share its color, for both main and
annotator PVs.

Click a move in a PV or use Left/Right to inspect its position. The line stays
frozen while you browse; press Escape in the PV to resume updates. If a PV
contains an illegal move, the memo identifies that move and the board and
selection stop at the last legal position.

### 5.4 MCTS annotator

MCTS annotation is available for draughts, not chess. Right-click the MCTS
analysis area to open or close an MCTS annotator. The
selection lists Hub engines whose `gui-engine-supports-mcts` parameter is true.
Statistics reported by that engine are displayed in the MCTS panel.

The annotator status and PV areas reserve space using the active font. Engine
parameter name and type columns fit their longest text plus a margin. The value
column fills the remaining grid width as the dialog resizes; manual column
resizing remains available.

### 5.5 Auto Play

**Auto Play** is enabled only when:

- the selected game is stopped; and
- an annotator engine is loaded.

Auto Play starts from the currently selected real position and asks the annotator
for one move at a time, using the configured analysis seconds. For both chess and
draughts it adds real moves at the mainline tip. Elsewhere it follows an existing
matching child, or adds a variation, preserving the existing continuations.
Created nodes retain **Auto Play** origin metadata with the annotator name,
visible in the tree details. Move notation shows the analysis without repeating
that origin label. Existing nodes retain their origin.

Each searched source position receives the final annotator PV, score, depth and
time, unless it already has annotator analysis of greater depth. Unknown incoming
depth does not replace a known depth; equal-depth analysis may replace it. Playing
engine analysis is unchanged. These real moves and position evaluations use the
normal game tree, score history, PGN and database paths.

While active, the same toolbar button reads **Stop** and remains enabled. Click
**Stop** or press `Escape` to stop. Accepted moves remain in the tree, and late
replies cannot add further moves. Navigating away from the node being extended
also stops Auto Play. Leave virtual PV browsing with Escape before starting;
starting from a real variation is supported.

Auto Play changes the game, so the existing save/discard prompts apply. To remove
an unwanted continuation after stopping Auto Play, open **Show game tree**, select
its first unwanted move and choose **Delete from here...** (section 4.3). This
removes that move and its descendants after confirmation; there is no undo.
Save a copy first if you need the original. Reloading a previously saved game
and declining to save the changed copy is another way to discard changes.
Auto Play never changes the game result or creates clock records.

For chess, Auto Play checks the existing rules before the first search and after
each accepted move, with the real root-to-start history (including variations).
It stops on checkmate, stalemate, insufficient mating material, repetition and
the 50/75-move rules. As in engine games, available threefold/50-move claims are
accepted immediately, including claims by an intended legal move. The annotator
log shows **Auto Play stopped; reason=…**. Annotation resumes when Auto Play stops.
Draughts retains its previous stop policy: no legal moves or a user stop, without
rule-based draw stopping.

Older saved **Auto Play PVs** remain readable, browsable and preserved by lossless
PGN export. New Auto Play runs do not change or extend those metadata lines.
Real mainline moves are indexed by the database; real variations follow its
existing mainline-only indexing policy. No separate Auto Play storage mode exists.

### 5.6 Larger analysis boards

Right-click the engine mini-board and choose **Pop out mini-board**, or right-click
the annotator mini-board and choose **Pop out annotator mini-board**. Double-clicking
one of these boards opens the same larger view. The pop-out follows that browser's
selected analysis position and offers copying its FEN from the context menu.

### 5.7 Pondering in chess games

To enable pondering for a game engine, save **Ponder = true** in its existing
parameter grid. Without a saved true value, pondering is off even when the
engine advertises a true default. An engine must advertise the Ponder check
option. This choice is per engine; discovery and analysis never ponder and do
not replace the saved choice with their runtime false value.

Pondering searches a predicted opponent reply in the background. A matching
actual reply reuses that search through `ponderhit`; a different reply stops the
old search before starting from the actual position. A valid early ponder result
is retained for a hit and discarded for a miss. Predictions and speculative
scores/PVs never become played moves or annotations. Ponder time is not charged
to the engine's clock; actual-turn time, including stopping a missed search, is.

Pondering is most useful against a human or engines on separate machines. Two
engines pondering on one computer compete for CPU resources; leave it off for
ordinary engine comparisons unless resources are deliberately separated.
At very fast time controls, the engine's advertised **Move Overhead** option
can leave a margin for communication and scheduling.

## 6. Scores, score history, and evaluation bar

All scores displayed by the score history and evaluation bar are normalized to
White's perspective:

- a positive score favors White;
- a negative score favors Black;
- zero is approximately equal.

The graph can contain both the playing engine's score and the annotator score.
For each played ply, the annotator score attached to that node is used; when it
is absent, the preceding node's annotator score can supply that point.

The default score-history colours identify the source and sign of each score:

| Colour | Meaning |
|---|---|
| Dark green | Playing-engine score of zero or above |
| Dark red | Negative playing-engine score |
| Light green | Annotator score of zero or above |
| Light red/pink | Negative annotator score |
| Dark blue | Missing playing-engine score in bar mode |
| Light blue | Missing annotator score in bar mode |

In bar mode, the playing-engine bar is on the left and the annotator bar on the
right for each ply. In line-graph mode, a blue-grey mark indicates that neither
score is available. Missing-score marks do not mean an evaluation of zero.
The grey vertical line marks the currently selected ply.

Mate scores reach the configured score limit: `#5` reaches the positive maximum
and `#-4` the negative minimum. The tooltip retains the mate distance rather than
replacing it with a pawn score. This applies in both graph and bar modes.

Choose **File > Preferences > Score history** to change the eight colours,
including missing-score marks and the selected-move line. These settings apply
to both the main graph and its popout, and can help distinguish scores when the
default red/green colours are difficult to tell apart. **Save** applies and saves
the choices for every edited game section. **Close** asks before discarding unsaved
changes. **Chess defaults** or **Draughts defaults** restores all preferences for
the selected game, not just this tab; use Save to keep them.

The evaluation bar uses the displayed game position's score, including the root
and real variations, preferring its annotator score and then its playing-engine
score. It does not substitute a different position's score when none is available.
When browsing an engine or annotator PV, it uses that PV's source score throughout
the line. Legacy Auto Play PV lines have no separate stored score, so their previews show
a neutral bar. White occupies the lower part of the bar and Black the upper
part. A large positive score makes White fill upward from below; a large
negative score makes Black fill downward from above.

Hover over the score history to inspect the score at a ply. Right-click it to
open the larger score-history window.

The graph's maximum score and **Linear** or **Logarithmic** scale are configured
under **File > Preferences**. These are display settings; they do not change the
score received from an engine.

When a PV text view is focused, **Escape** exits its browsing mode and resumes
live PV updates. If Auto Play is active, the first Escape stops Auto Play;
a subsequent Escape exits PV browsing. Separate popout board windows retain
their existing key handling.

## 7. Running a tournament

Click **Tournament...** to open the shared Tournaments window. It selects the
last-used tab for the main board's game, or creates one if needed. **New tournament**
creates another named tab (Tournament1, Tournament2, and so on). Edit its tournament
name to rename the tab. Each tab has independent pairings, standings and files.
Chess offers UCI engines; draughts offers Hub/DXP engines.

The Game choice changes the settings in the current tab. Save / Discard / Cancel
protects existing data and running games before replacing incompatible settings.
Other tabs and the main board's selected game remain unchanged.

An engine label such as **Name (Engine 11 dxp engine)** uses its one-based
position in the complete engine registry, followed by its protocol. It is not
an engine-directory number or a participant count. Filtering by game can leave
gaps, and adding/removing registrations can change these display numbers.
Tournament records identify engines using their saved configuration identity.

Tournament settings use six rows:

1. Chess/Draughts selector and tournament name.
2. Starting FEN, ballot file/path, Clear ballot and position count.
3. Time controls.
4. Time forfeit and adjudication inputs.
5. Pairing options, with Create pairing above Clear pairing beside the radio group.
6. Play, concurrent games, Stop, Save and Load.

Labels, inputs and buttons are vertically aligned using their measured sizes.
The FEN minimum width follows its text and font; the FEN and ballot-path fields
share additional space as the window grows.

### 7.1 Tournament settings

Enter:

- a tournament name;
- a starting FEN;
- moves per period;
- time, with a **minutes / seconds** selector (minutes is the default);
- increment in seconds;
- increment mode;
- maximum concurrent games;
- pairing type;
- at least two engines from the checklist.

Short numeric fields have font-measured widths: three digits for move and
concurrent-game counts, with additional room for decimals where appropriate.
These widths do not change which values the controls accept. New Game,
Database limits, evaluation preferences and annotator time use the same sizing.

The time-control row reads **Time control: X moves in Y minutes/seconds with Z
second increment** followed by the increment mode. A zero move count means the
whole game; the existing from-start / after-move-limit increment policies still
apply. Files store duration in minutes plus the display-unit choice. Older files
open in minutes without changing their actual duration.

Available pairing types are:

- **Single round-robin**: each pair meets once;
- **Double round-robin**: each pair meets twice with reversed colors;
- **Swiss**: one round is generated at a time from the current standings.

Click **Create pairing**. Single and double round-robin creation builds the
complete schedule. For Swiss tournaments, all results in the current round must
be known before the next round can be created. ZGUI warns when avoiding a
repeat pairing is impossible.

Changing accepted tournament settings after creating pairings invalidates the
schedule. Choose **Apply change** to clear the existing pairings and results, or
**Revert** to restore the accepted settings.

### Opening ballots (chess and draughts)

To play the same set of opening positions with both engine colours:

1. Select the engines in the tournament window.
2. Click **Ballot file...** and select a text `.fen` file with one complete FEN
   per line, using the selected game's notation. Chess also accepts `.epd`
   opening files, described below. Blank lines and lines
   beginning with `#`, `;` or `//` are ignored. A UTF-8 BOM is accepted. Invalid
   positions report the source line; no partial ballot is installed. New ballots
   reject positions that the existing game rules would end immediately, including
   checkmate, stalemate and supported dead-position/move-counter draws. Draughts
   men on their own promotion row are invalid; use kings there. Valid terminal
   starting positions in existing saved tournament archives remain readable.
3. Optionally check **Shuffle opening pairs** in the pairing row before creating
   the pairing. It defaults to off and is available only with a loaded ballot.
4. Click **Create pairing**. Ballots select **Double round-robin** automatically.
   Every pair of selected engines plays each position twice, in consecutive rows,
   with White and Black reversed. The position itself, including side to move and
   chess move counters, stays the same. Round is the entry number in the scheduled
   order.
5. Set time controls/concurrency and click **Play** as usual.

**Chess EPD input:** EPD uses the first four FEN fields (pieces, side to move,
castling rights and en passant), followed by optional operations. The ballot
loader supplies move counters `0 1` for a four-field EPD position and ignores
all trailing operations, including `bm`, `id`, `hmvc` and `fmvn`. It does not run
best-move tests. For example:

```text
rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - bm e4; id "Start";
```

Full six-field FEN lines keep their original counters. EPD support is limited
to chess opening ballots (including the CLI `ballot` parameter); ordinary FEN
boxes still require full FEN, and **Open game** still opens PGN/PDN.

For two engines and 79 positions this creates **158 games**. By default, positions
are used in file order, including repeated entries. With **Shuffle opening pairs**,
Create pairing randomly permutes the opening entries first, then the existing
pairing generator creates the colour-reversed games for each entry. Both games
stay together; with several engines, every engine pairing uses the same scheduled
opening order. Duplicate entries retain their frequency. A random permutation can
occasionally be the same as the source order.

Shuffling can reduce bias from favourable openings occurring early in a sequential
test; it does not guarantee that a curated ballot is an independent random sample.
The option is locked once pairings exist. Clearing pairings allows a new schedule;
explicitly creating pairings with shuffling enabled generates a fresh permutation.
Loading or starting a saved tournament, replaying a game, viewing SPRT, and
querying it from the CLI never reshuffle the schedule.

Interactive CLI example (substitute your engine IDs):

```text
run_tournament engine1_id=1 engine2_id=2 ballot="ballot2.fen" shuffle_opening_pairs=true time=600 moves=75
```

The shuffle option uses the same GUI pairing path. Each game remains a normal
tournament row with the existing engine reservations, clock, result, reason and
replay rules.
This does not apply a ballot to Swiss pairings.

While a ballot is loaded, the ordinary Starting FEN field shows the first
position and is disabled. **Ballot file...** and **Clear ballot** are available
only before pairings exist: clear the pairing first to change the opening set.
Clearing the ballot restores ordinary single-FEN operation. Switching between
chess and draughts clears the ballot with the other game-specific settings.

Save/recovery files embed the actual scheduled position order, the shuffle option,
and each game's starting FEN. The saved order is authoritative; no random seed or
original ballot file is needed to reconstruct it. Existing files without the
shuffle option load with it unchecked, preserving their saved order. Reopening
or replaying uses those saved positions even if the
original ballot file was moved, edited or removed. PGN/PDN exports retain the
appropriate starting FEN for each recorded game. Ballot tournaments use save-file
version 4; older ZGUI versions reject them rather than ignoring the openings.
Ordinary tournaments retain their existing save formats.

### 7.2 Playing the tournament

**Play** becomes available after creating or loading pairings. Clearing the
pairings disables it again. Click **Play** to start pending games. ZGUI starts
games up to the configured
concurrency limit while respecting engine availability. Each simultaneous game
needs its own available engine instances and non-conflicting DXP resources.

Reservations apply across all tournaments, ordinary games and annotators. A busy
row identifies its engine and the tournament using it. Competing tournaments use
**oldest-waiting-first** allocation: a waiting turn keeps its place through timer
updates. Both engines must be available together. After starting one game, that
tournament rejoins behind existing waiters for its next game. A younger turn
normally cannot take an engine needed by an older waiting turn. If that older
turn cannot start because one of its engines is already in use, one younger game
may borrow its otherwise idle shared engines. This allowance is spent only when
a game actually starts, survives timer updates, and applies once per older turn.
Further conflicting games wait until that older turn starts or leaves the queue.
This bounded backfill avoids stranding all idle engines without permitting
unlimited bypass. Games using unrelated engines can continue. Stop or Close removes the tournament's waiting turn.
Separate engine registrations represent separate instances; DXP endpoint conflicts
still count as shared resources.

The pairing grid shows game number, round, White, Black, result, and reason.
Click a running row to display and follow that game's current tree in the main
window. Finished games can be selected and browsed in the same way as other
completed games.

Starting a game selects its row. Rows that already fit stay in their current
place; the grid scrolls only when needed to reveal a started row. Between starts,
you can scroll the list manually without it snapping back on each timer update.

Double-click a saved tournament game to load it into **Game History** and display
its board, moves, comments, variations and effective result. If that game is
already present, ZGUI selects the existing entry; reopening the same event does
not add another copy. Identity includes the tournament, game number and replay
attempt, so distinct ballot games are retained. A referee's changed result updates
the existing history header without replacing its moves or annotations. Live games
retain their existing selection path. Unplayed rows have no saved game to open.
Viewing saved games starts no engines, reserves no engines and does not rewrite
the tournament file. Entries remain available after the tournament tab closes.

Click **Stop** to stop the tournament's active games and pending scheduling.
Incomplete games keep result `*` with **Referee stopped tournament**, including
when stopped during engine initialization. Already completed games retain their
result and reason; actual engine errors remain diagnostic errors. Play and Stop
are disabled while shutdown completes. Incomplete games remain available for
review or rescheduling.

### 7.3 Results and rescheduling

Right-click a pairing to set its result manually. The result spelling depends
on the tournament's game:

| Result | Chess | Draughts |
|---|---|---|
| White wins | `1-0` | `2-0` |
| Draw | `1/2-1/2` | `1-1` |
| Black wins | `0-1` | `0-2` |
| Unfinished/unknown | `*` | `*` |

Chess standings award one point for a win and half a point for a draw.
Draughts standings award two points for a win and one point for a draw.

**Clear pairing** starts a fresh pairing/tournament after confirmation and keeps
the earlier tournament files. It is unavailable while games are running or
stopping. Use rescheduling to retry an individual game.

The **Reason** column shows the actual rule or clock cause when available:
checkmate, stalemate, repetition, move-count/endgame draw rules, or which side's
clock expired. Rules-based endings identify the orchestrator, for example
**Orchestrator declared draw by repetition; repetitions=3**. A chess timeout can still be a draw when the opponent cannot mate;
the explanation is retained. Engine endings identify the engine and colour, with
the raw protocol reason code when supplied. An unspecified engine ending does
not identify a rule-based cause. These descriptions preserve the existing result
and are saved with the tournament. Older completed rows retain their saved text.

A referee result edit retains the original reason and appends, for example,
**GWD (Black) claimed win (DXP reason 3). Referee declared win for Black**.
The same wording applies to both games: **Referee declared win for White**,
**Referee declared win for Black**, or **Referee declared draw**. With no original
reason, only the declaration is shown. Further edits replace that declaration.
Clearing the override with `*` restores the played result and its reason.
Older numeric “Operator set result to …” annotations are recognized on loading.
Use **Reschedule selected game** to clear a game's result and make it pending again.

An engine crash, unexpected process exit or failed launch leaves result `*`;
it does not automatically forfeit the game. The referee can declare a result or
reschedule it after investigating the diagnostic.

#### Reason reference

These are the fixed reason families currently produced by ZGUI. Names, sides,
counters, protocol codes and error details vary; saved older rows can retain
legacy wording. Engine claims describe what the engine reported, rather than
asserting an independently verified rule cause.

| Source | Reason text / meaning |
|---|---|
| Chess rules | **Orchestrator declared checkmate**; **Orchestrator declared draw by stalemate**, **insufficient mating material**, **75-move rule**, or **fivefold repetition**. |
| Accepted chess claims | **Orchestrator declared draw by 50-move rule (claim accepted)** or **threefold repetition (claim accepted)**, including the **intended** variants. |
| Draughts rules | **Orchestrator: White has no legal move** or **Black has no legal move**; **Orchestrator declared draw by 5-move endgame rule**, **16-move endgame rule**, **repetition; repetitions=N**, or **25-move rule; reversible_plies=N**. |
| Adjudication | **Adjudicator engine evaluation score comparison threshold cp (White perspective)** plus the flag-fall cause; failure leaves * for referee attention. |
| Clocks | **Orchestrator: Flag fell for white/black**, optionally with **engine move deadline expired** or **idle move deadline expired**. A chess timeout draw adds **opponent has insufficient mating material**. |
| Engine reports | **Name (White/Black) claimed draw**, **claimed win**, **resigned**, or **ended game**, with raw **DXP reason N** when provided. Unrecognized details are preserved. A fallback can say **Engine ended game** with side or no-move information. |
| Referee actions | **Referee stopped tournament**; **Referee declared win for White/Black**; **Referee declared draw**. A declaration follows the original cause when present. |
| Closing | **Stopped: tournament closed**. |
| Scheduling | **Running**, **Waiting for engine Name**, optionally **in use by …**, **Waiting for engine allocation**, optionally naming a tournament, **Stopping**, **Stopped**, or a blank pending row. |
| Configuration / failures | **Missing engine**, **Could not start: …**, **Capture failed: …**, or the actual runtime diagnostic, for example an unexpected process exit. Details are open-ended. |
| Fallback / imported records | **Game finished**, **Draw**, **Unknown result**, **Played result**, legacy **Manual result**, or the saved reason. **Bye** identifies an unplayed Swiss bye. |

This reference describes displayed causes; it does not add adjudication rules.

The cross table ranks engines by points, wins, Sonneborn-Berger score, and then
name. It also shows the individual matchup results. In a head-to-head event
with only two engines, their SB totals are equal; use Points to read the match
score.

### 7.4 Saving and loading tournaments

- **Save…** and **Load…** are disabled while this tab is running or stopping.
  Other tournament tabs can continue running while an idle tab loads a file.
  Automatic saving continues while games run.
- Changes and results save automatically. Use **Save** to choose the JSON file;
  **Load** opens a saved tournament in its own tab without starting it. Opening
  the same file or tournament identity again selects its existing tab. Other
  tournaments may continue running; two tabs cannot write the same JSON or
  publication file.
- The tournament PGN/PDN is created beside the JSON when first saved outside recovery.
  Move the JSON and its linked PGN/PDN together.
- An older or externally changed PGN/PDN is preserved rather than overwritten.
- Engine definitions must match the saved identities. Renaming the tournament
  is safe; changing an engine's executable, registered protocol ID/name, arguments
  or INI contents can leave old rows without a matching engine. See below.

Before a file is chosen, recovery files live in the per-user application
configuration directory. Save errors appear in the tournament title and pause
scheduling so the error can be resolved without losing results.

Closing a tab (its X or **Close tournament**) offers **Save / Discard / Cancel**
and warns that its running tournament will stop. Save chooses a file, then stops
and captures the games before writing the final state. Discard stops and closes
without an explicit save; existing recovery and published files remain. Cancel,
including cancelling the save-file picker, leaves the tournament running.
A final save failure leaves the stopped tab open so you can recover its data.

Closing the Tournaments window applies this to every tab. All choices and save
locations are collected before any tournament is stopped; cancelling any prompt
leaves them all open. Minimize keeps tournaments running. Closing ZGUI also
protects every tournament. There are no hidden tournament sessions after closing.

Close-stopped games retain result `*` and reason **Stopped: tournament closed**.
Explicitly loading their JSON and clicking Play resumes stopped/unplayed rows;
completed results remain. Discarded files are not offered for automatic resume.

### 7.5 Chess tournament details

Chess engine tournaments use **Tournament...**. Select
registered UCI engines, a starting FEN, time control, pairing type and concurrent
game count, then use **Create pairing** and **Play**. The default is 5+3 sudden
death. Single and double round-robin and the existing Swiss pairing heuristic
are available. With no ballot, every game uses the supplied starting FEN.
Alternatively, load an opening ballot to play every position with colours
reversed; optional shuffling keeps each two-game opening pair together (section 7.1).

Chess standings show one point for a win and half a point for a draw. The
existing tie-break order is points, wins, Sonneborn-Berger, then name. A Swiss
BYE awards one point and counts as a win in that tie-break; it starts no engine
and creates no played PGN. This retains the existing tournament conventions,
which are not a claim of compliance with FIDE Swiss regulations. Finish or
resolve the current Swiss round before creating the next one.

Tournament games force Ponder off at runtime, even when an engine has it saved
as true. Saved options and ordinary games keep their own choice. Saving a UCI
registration stores its options with that registration in `engines.json`; two
named registrations can use the same executable with different Threads, Hash or
strength settings. Existing registrations without private options still read
the old executable-side `.params.json` file until saved in the engine editor.
Older ZGUI versions ignore the new registration options; rebuild both platform
versions before using them. The legacy file is left unchanged. Start warns only when participants still
share those legacy settings. Private options do not isolate files an engine itself
writes beside its executable (for example logs or learning files). If an engine
cannot safely share those files, use separate engine directories. Hub/DXP parameter
files are unchanged.

Concurrency respects existing engine reservations: five participants permit at
most two games at once. Rows waiting for a busy engine say so. Concurrent active
searches still share CPU capacity, and both players' processes retain their Hash
memory. Choose Threads, Hash and concurrency to fit the machine; ZGUI does not
allocate cores automatically or claim that such games are isolated measurements.

Completed games, manual results and attempt history use the existing recovery
workflow. Chess saves a versioned JSON tournament and a companion **PGN** with
the game's start date, actual moves, comments and variations. Externally changed
PGNs are preserved. Loading restores records without starting processes; use
**Play** to continue pending rows. A stopped or failed row remains unfinished
with an explicit reason. Use a manual result or **Reschedule selected game**;
errors are not silently retried or awarded as forfeits. A flag fall uses the selected **Time forfeit** policy; the default remains a
normal rules-based result. Loading a draughts file opens/selects a draughts tab;
loading a chess file opens/selects a chess tab.

### 7.6 Tournament files in detail

Tournament changes and results are saved automatically. Until you choose a file,
ZGUI uses a recovery file in its application configuration directory; **Load**
opens that directory for a new tournament. Save errors pause scheduling and appear
in the tournament window title. Pairings cannot be replaced while games are still
running or stopping.

Applying changed settings, recreating round-robin pairings, or clearing pairings
starts a new tournament ID with separate files beside the previous JSON. The
previous tournament JSON and PGN/PDN remain available to load later. An unnamed
tournament gets a separate recovery file instead. These actions are blocked
until any save error has been resolved, so unsaved results are retained.

Use **Save** to write the tournament state as JSON. The file contains the
settings, selected engine names, pairings, results, reasons, and concurrency
limit. Use **Load** to open it later in its own tab, then **Play** to resume.
Engines are matched by saved identity keys based on
the executable, protocol ID, arguments, initialization text, INI path/contents
and DXP connection settings. The registered protocol ID is also the name shown
in engine selection; changing it can change the identity. Renaming the tournament
does not. Changing identity fields can leave older rows showing **Missing engine**;
restore the earlier engine configuration to resume those rows.

Saved UCI option values do not form part of these identity keys and are not frozen
in each tournament record. Resumed or replayed games use the matching
registration's current options. Keep a copy of the engine configuration used for
a comparison, and avoid changing it during a fixed match or SPRT experiment.

The JSON also contains each played game, its comments and variations, any manual
result override, and earlier attempts of rescheduled pairings. Manual corrections
change the standings while retaining the original played result. Rescheduling
archives the previous attempt and clears the current result.

ZGUI regenerates the tournament PGN/PDN from these saved records, with one game
per current pairing attempt, including games ending before their first move.
Byes do not create PGN/PDN games. The PGN/PDN path is chosen beside the first JSON file
and remains fixed when you rename the tournament or save the JSON elsewhere.
On the first save outside the recovery directory, the PGN/PDN moves beside the chosen
JSON; the old recovery files are removed after both new files are saved. A failed
save keeps the recovery files available.
An existing file or directory is never adopted as a new PGN/PDN target: ZGUI uses
a unique filename instead. Its first write also refuses to replace a file that
appeared after the name was chosen. Later saves update the PGN/PDN created for that
tournament. Saving over an existing JSON file asks for overwrite confirmation.
Older JSON files without the PGN/PDN ownership marker preserve any existing PGN/PDN as
an archive and generate a separate projection from the saved records.
Manual overrides are identified in the PGN/PDN headers along with the played result.
Loading the JSON repairs a stale or missing PGN/PDN. Paths are saved relative to the
JSON, so move the JSON and PGN/PDN together. If an older path points to a missing
directory, ZGUI generates a new PGN/PDN beside the JSON and preserves any existing
archive there. Earlier attempts remain in JSON.

Older tournament files did not contain the played games. When loading one with
an existing PGN/PDN archive, ZGUI preserves that archive and creates a separate PGN/PDN
for the linked records. Missing older moves cannot be recovered from standings.
Preserve the older archive along with the tournament JSON. ZGUI prompts to save
tournament state when closing if unsaved tournament data exists.

### Time forfeit adjudication

The tournament's **Time forfeit** selector defaults to **Orchestrator**. This keeps
the normal rules-based timeout result: usually a loss for the side whose flag fell,
with the chess insufficient-mating-material exception still able to give a draw.

Alternatively, choose a registered **Hub** engine for draughts or **UCI** engine
for chess. DXP engines cannot adjudicate arbitrary positions. The analysis-time
and cp-threshold edits then become enabled. Defaults are **1.0 seconds** and
**200 cp**. The time must be positive and at most 3600 seconds; the threshold
must be positive and at most 1000000000 cp.

When a flag falls, ZGUI first checks the existing game rules for a result already
decided on the board, such as checkmate, stalemate, or a rules-declared draw.
That result and its reason take precedence; no adjudicator is started.
Otherwise, both players shut down and ZGUI analyzes the unchanged final position
in a fresh instance of the selected engine. A playing engine may also
be the adjudicator. Its suggested move is never added to the game. The budget
applies to the search, excluding startup/shutdown; an engine may return early.
All comparisons use the adapters' normalized **White-perspective** evaluation:

| Evaluation | Result |
| --- | --- |
| Score >= +threshold | White wins. |
| Score <= -threshold | Black wins. |
| Score inside the band | Draw. |

This evaluation policy is symmetric: either side can win, including the side
whose flag fell. It is not capped at a draw for that side. The separate
**Orchestrator** policy continues to use the normal timeout rules.

The **Reason** column names the adjudicator and records the comparison, for
example `Adjudicator Scan evaluation 300 >= 200 cp (White perspective)` or
`Adjudicator Scan evaluation -100 > -200 cp (White perspective)`, followed by the
original flag-fall cause. Positive/negative mate scores adjudicate a White/Black
win; absent or ambiguous scores do not become zero. Failed, unavailable or
cancelled analysis leaves `*` and an explicit reason for referee attention.
Engine crashes and other non-clock failures retain their existing handling.

The existing reservations protect the adjudicator alongside the two players for
the whole game, across tournaments and annotators. A shared adjudicator can
therefore limit tournament concurrency. It starts only after both players stop;
the GUI remains responsive during its search. Stopping the tournament also
cancels adjudication. This policy is optional and should be fixed before play if
you intend to treat a comparison as a preplanned SPRT experiment.

Interactive CLI examples:

```text
run_tournament engine1="GWD" engine2="Kingsrow" time_forfeit=loss
run_tournament engine1="GWD" engine2="Kingsrow" time_forfeit="Scan" adjudication_time=1.0 adjudication_threshold=200
```

`time_forfeit=loss` selects the normal orchestrator rules, including timeout-draw
exceptions; it is the default. Otherwise `time_forfeit` is a unique engine name.
The matching `time_forfeit_id` or `time_forfeit_key` selector can disambiguate
registrations, using the IDs/keys from `list_engines`; supply only one selector.
`adjudication_time` is seconds and `adjudication_threshold` is cp. Supplying either
requires an engine policy. Decimal CLI values use a dot. The policy is configured
through the same tournament controls and execution used by the GUI.

An adjudicated tournament saves its engine identity, display name, time and
threshold in version-5 tournament JSON. Older ZGUI versions refuse that format.
Existing older files retain the orchestrator policy. Loading a file with a
missing adjudicator displays **Missing engine** and prevents starting those games
until that registration is restored or the policy is explicitly changed. Changing
the policy on a paired event uses the existing Apply/Revert settings workflow;
it does not silently reinterpret completed game records.

### 7.7 Live SPRT comparison

Expand **SPRT comparison** below the tournament games table. Choose **Candidate**
and **Baseline** using its independent selectors; **Swap** reverses them. The
existing engine checkboxes continue to filter standings. They do not change this
comparison once pairings exist. Drag the splitter to resize the pane, or collapse
it to give the space back to the games table.

Use **SPRT settings...** to set H0/H1 in **logistic Elo** and alpha/beta as
fractions. Defaults are 0 and 5 Elo with alpha=beta=0.05. H0 must be below H1;
alpha and beta must each be positive and their sum below 1. This is a paired
**generalized sequential probability ratio test (GSPRT)**, labelled SPRT in the
interface. It estimates the five outcome probabilities under each Elo hypothesis;
it does not assume a fixed draw rate. Normalized Elo is not supported in this model.

Alpha is the target risk of supporting H1 when H0 is true; beta is the target
risk of supporting H0 when H1 is true. For H0=0 and H1=+5 Elo, 0.05/0.05 targets
5% errors at those hypotheses. Lower rates generally require more evidence.
They do not mean a 95% probability that the candidate is better.

The left table counts two-game scores from the candidate's perspective:

| Pair score | Outcomes |
| --- | --- |
| 0 | Two losses (LL). |
| 0.5 | Loss and draw (LD/DL). |
| 1 | Two draws or a win and loss (DD/WL/LW). |
| 1.5 | Win and draw (WD/DW). |
| 2 | Two wins (WW). |

Only games against the selected opponent count, for chess and draughts. Each
scheduled opening must have exactly two games with colours reversed and the same
starting FEN. A double round-robin ballot provides these pairs; duplicate ballot
FEN entries remain separate. Without a ballot, a double round robin gives one
pair per selected opponent. Single legs and Swiss schedules are unavailable for
this view; an explanation is shown instead of a misleading calculation.

The graph shows the generalized log-likelihood ratio (LLR) and H0/H1 boundaries.
Hover over a graph point to see its opening-pair number, LLR, estimated logistic Elo difference from the candidate's
results through that point, and whether it is
the first crossing. All-win/all-loss samples have an infinite Elo estimate; this
is an empirical estimate, not an H0/H1 setting or a confidence bound. Positive evidence favours H1; negative evidence favours H0. Pairs enter in
scheduled opening order. If pair 8 finishes before pair 7, it waits. The view
replays this sequence and freezes its evidence sample at the **first crossing**.
The comparison uses one descriptive status line:

- **Running:** “SPRT inconclusive so far — 42 of 79 opening pairs included.”
- **Waiting for an earlier result:** “SPRT waiting for opening pair 43 — 42 of 79 pairs included.”
- **All selected opening pairs complete, no crossing:** “SPRT inconclusive — all 79 opening pairs included.”
- **Stopped with missing results:** “SPRT incomplete — 42 of 79 opening pairs included.”
- **Boundary reached:** “SPRT favours H1 (+5 Elo) — boundary reached after 57 opening pairs.” H0 shows its own Elo hypothesis.

The line stays on one row; narrow views shorten its drawing with an ellipsis,
without a status hover hint. For a finished tournament, the view
replays saved pairs using the current settings: it asks whether and when that
sequential test would have reached a boundary. An inconclusive result does not
establish that the engines are equal. Complete pairs outside the evidence sample
remain in the records. A missing or corrected result causes the view to
reconstruct the current sample and crossing from the saved effective results.

This display never stops a tournament. A fixed match can
continue after crossing, and an external runner can query `sprt=true` and issue
`stop_tournament` using the same calculation.

**Example: stopping early versus finishing the tournament.** Before playing,
choose H0 = 0 Elo, H1 = +5 Elo, alpha = 5% and beta = 5%. Under the test's
assumptions, alpha is the approximate long-run chance of favouring H1 when the
candidate is actually 0 Elo stronger; beta is the approximate long-run chance
of favouring H0 when it is actually +5 Elo stronger. These are error rates over
repeated tests, not a 95% probability that a particular conclusion is correct.

| Tournament behaviour | Example | SPRT interpretation |
| --- | --- | --- |
| Stop early | First H1 crossing at opening pair 42; stop playing. | H1 favoured at pair 42. |
| Finish all 79 pairs | First H1 crossing at pair 42; play the remaining pairs anyway. | The same SPRT decision at pair 42; all games remain in the full-match results. |
| Finish without crossing | Neither boundary reached after all 79 pairs. | Inconclusive; this does not establish equal strength. |

The error-rate interpretation is the same for the first two cases: continuing
play does not change the recorded first-crossing decision. A finished tournament
can replay the same specified test. Changing settings recalculates the analysis;
trying settings after seeing results until one gives a favourable answer does
not preserve the same 5% error claim. Running versus finished is not the relevant
statistical distinction; keeping the test fixed is.

The underlying saved/CLI provenance remains **configured_before_play** for a
complete design explicitly applied before play, **exploratory** for defaults or
settings chosen/changed afterward, and **amended** for referee changes or replayed
attempts. This records history; it is not independent proof of experimental
pre-registration. The alpha/beta rates are nominal, asymptotic GSPRT targets, not
exact finite-sample guarantees. Choosing hypotheses after seeing results does not
support the same error-rate claim as a preplanned test. A fixed, curated ballot
also differs from independent random sampling.

Explicit comparison settings are saved in optional versioned `sprt_view` metadata
inside tournament JSON; reopening reconstructs the graph and first crossing.
Older tournament files without this block open with exploratory defaults. Older
ZGUI versions may drop this view metadata when resaving; game records are unaffected.
An unchanged Apply preserves the existing design declaration.

The calculation is independently implemented and checked against the logistic
likelihood reference in [Fishtest's statistical documentation](https://official-stockfish.github.io/docs/fishtest-wiki/Fishtest-Mathematics.html).
Fishtest is a reference, not a runtime dependency.

## 8. PGN, PDN and FEN

### 8.1 Opening game files

Choose **File > Open game** (**Ctrl+O**) for PGN or PDN. If the game cannot be
determined unambiguously, choose Chess or Draughts. ZGUI lists games with White,
Black, event, and result. Double-click a game to load it into the main window.
Games are validated on selection, with import warnings shown in the browser.

For draughts PDN, a malformed variation may be skipped while preserving the
surrounding game and later games. A variation whose numbered start lies outside
its parent line is skipped rather than moved to another position. For chess PGN,
an illegal move or malformed variation rejects that game; the current document
is retained rather than being partly replaced.

The loader reconstructs the starting position, mainline, and variations in
the game tree. Invalid moves are reported with their ply so a damaged game can
be located.

### 8.2 Saving game files

Choose **File > Save PGN** for chess or **Save PDN** for draughts (**Ctrl+S**)
to save the displayed game tree. ZGUI appends the game to the selected file; it does not replace games already in that file.
Choose a new filename when a one-game file is required.

The Game Tree window can also copy the current tree in its game file format.
Closing or replacing a changed standalone document offers to save it; Cancel or
a failed save keeps the current game and display.

### 8.3 PGN and PDN compatibility

For chess:

PGN preserves tag values (including custom tags), comments, NAGs and nested
variations. Repeated moves from the same position merge their comments, NAGs
and continuations, with a warning. Formatting and comment delimiters may be
normalized. Comments after a variation are associated with the preceding move
and may be printed before that variation on saving. Orthodox chess PGN is supported; null moves are rejected, and an
optional **e.p.** suffix is accepted after en passant. Legacy CP1252 files are
converted to UTF-8 with a warning; saved PGN uses UTF-8 without a BOM.

The chess reader accepts a spelling only when it identifies one legal move.
It tolerates redundant source file/rank/square disambiguation (`Ngf3`, `N1f3`,
`Ng1f3`), missing or incorrect `+`/`#`, promotion without `=`, long algebraic
or UCI coordinates (`e2-e4`, `e2e4`), a missing capture `x`, and lower-case
`n`, `r`, `q` or `k`. Lower-case `b` always means the b-file, never a bishop;
use upper-case `B` for bishops. Castling may use zeroes (`0-0`). Ambiguous or
illegal moves, a spurious capture `x` on a non-capture and an invalid promotion
piece remain errors. A different legal promotion piece means a different move;
the reader never substitutes one for another.

File/Open and database import report **Non-standard SAN normalised** at most once
per game, including spellings in variations. Normal GUI saving writes canonical
SAN with correct check/mate suffixes, so opening and saving cleans up those
spellings without changing the played moves.

Standard `[%eval ...]`, `[%clk ...]` and `[%emt ...]` annotations are read and
written as typed evaluation/clock data; unknown commands stay in the comments.
The standard evaluation command includes depth when known and reloads as the
engine score, including when its source was an annotator. The lossless export
option retains the original source. The normal export omits ZGUI-specific PV/depth and secondary annotator metadata.
An optional lossless mode is available through the export API using the existing
node-data extension. Analysis PVs never become played variations. Movetext wraps
at token boundaries near column 80; an indivisible comment or token may be longer.
Each imported game is limited to 16 MiB, individual tokens to 1 MiB and variation
nesting to 128 levels. Large collections are indexed a game at a time, with move
validation deferred until selection.

For draughts:

ZGUI exports standard result spellings `1-0`, `1/2-1/2` and `0-1`; the tournament
window uses draughts point results `2-0`, `1-1` and `0-2`. Both forms are accepted
on import. The special result `0-0` is preserved; `*` denotes an unfinished game.

Scores and clocks appear as readable comments. Additional `[%gwd ...]` comments
preserve typed node metadata for ZGUI round trips. Other programs may show
these extensions as ordinary comments or ignore their meaning. Literal user
comments resembling metadata are escaped on export. Equivalent capture spellings
are merged; conflicting metadata keeps the first value and generates a warning
naming the discarded fields. Comments and different continuations are retained.

### 8.4 Working with FEN

Chess FEN includes piece placement, side to move, castling rights, en passant,
and halfmove/fullmove counters. The normal chess starting position is:

```text
rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
```

Draughts FEN lists the side to move and occupied numbered squares; for example:

```text
W:W31-50:B1-20
```

The FEN field shows the displayed position. Right-click the main board to:

- copy its FEN;
- choose **Paste FEN position from clipboard** to load a position;
- open **Setup position**;
- search that position in an open database.

In **Setup position**, select a piece type and click board squares to place or
remove it. Choose the side to move. **Start** restores the normal starting
position, **Clear** empties the board, and the FEN action parses the text entered
in the FEN box. **Apply** sends the resulting position back to the main window;
**Cancel** leaves the current position unchanged.

For chess, the same window has twelve pieces in two columns (White and Black).
The setup board always faces White, even if the main board is flipped. Incomplete
boards are allowed while editing, but **Apply** requires a valid chess FEN. No
playable position or running game changes until replacement is accepted.

The FEN box is also the editor for castling rights, en passant and move counters.
**Paste FEN** reads this box, rather than the clipboard. Chess Apply also reads
pending text edits; draughts retains its existing behavior of requiring Paste FEN
first. Invalid text stays available for correction. If board editing would
replace pending typed text, a confirmation defaults to Cancel. After cancelling,
use Paste FEN or Apply to read the text, edit the text to reconsider, or use
Start/Clear to replace it; further square clicks do not repeat the prompt.

Placing/removing a chess piece clears en passant and resets the halfmove counter,
while retaining the fullmove number. Castling rights are removed only when the
required king or rook is missing from its home square; edits never add rights.
Changing side clears en passant and preserves the other fields. Start restores
all starting fields; Clear sets no rights and counters 0/1. Enter any other
rights, en passant or counters explicitly in FEN. Validation checks the existing
chess rules and FEN structure, without proving full historical reachability.

Cancelling replacement or failing to save the current game leaves the setup
window open with its draft and text intact. Cancel/closing the setup window
leaves the main game unchanged. An accepted setup replaces the standalone board
through the existing save/discard workflow; it does not edit a running game or
its clock.

## 9. Game database

ZGUI uses SQLite databases for collections of chess PGN or draughts PDN games
and position search. The window layout, filters and import controls are shared.
New chess databases use schema 8, with explicit variant, key-format and game-identity
metadata. Existing schema-7 chess databases remain readable and writable without
automatic migration. Chess and draughts databases are separate files; one file
does not mix the games. **Open database** detects and validates the file's game,
then selects that game context. Each game retains its own database window;
opening another database for that game replaces its existing window after
validation. Unsupported or invalid files are rejected without replacing the
current window. Create a new database through **Create database**, rather than
opening an empty file.

Choose **Database > Create database** for a new `.sqlite` or `.db` file, or
**Database > Open database** for an existing one.

### 9.1 Importing games

In the database window, right-click and choose **Import PGN** for chess or
**Import PDN** for draughts. The progress view shows imported games, errors and
duplicates, and allows the import to be stopped. An `.import.log` file is written
beside the imported file. Chess log entries identify the game number and its
ending byte offset in the source; parser line/column numbers are relative to that
game. Fatal import errors include the failing PGN record. An invalid chess
mainline or variation rejects that
game; other valid games can still be imported. Column-one tag-like lines are
collection recovery boundaries even inside a damaged comment or variation;
indent literal tag-like lines in multiline comments. Draughts logs also record nonfatal
warnings for skipped malformed variations.

Duplicate detection compares complete canonical game content, including comments
and variations. Changed comments or branches remain separate records. Chess
schema-8 identity is the complete game with canonical legal SAN moves, including
correct check/mate suffixes. Original tag values, comments, NAGs and variations
are retained; source move spellings and whitespace outside those tokens are
normalized. Stored text uses conventional move numbers and parentheses.

Schema 7 retains its original token text, spacing, hash version and metadata,
including source move spellings such as `0-0`. Equivalent source spellings may
therefore remain separate games in schema 7. Its stored token layout is internal
data, not the GUI export format. Each database uses one identity policy; versions
are never mixed within a file. Older executables that support only schema 7
refuse schema 8. Position search and continuation statistics use the same keys,
tables and queries in both schemas.

Date (or UTCDate), ECO, WhiteElo and BlackElo also have typed database columns.
Unknown or malformed values become NULL in those columns while the original
PGN tags remain intact; the existing filters are unchanged.

For draughts, equivalent capture spellings identify the same game. Older
database identities are compared and upgraded as matching games are encountered,
so the first import against an older database may take longer. Opening a
supported older draughts database upgrades its internal format. An older ZGUI
that cannot understand the newer format refuses to open it. Keep a backup before
upgrading when you need to continue using an older executable.

The import progress window is modal: main-window menu shortcuts, including Quit,
are unavailable while it is open. Use its Stop action to cancel. Closing the main
window during import also requests cancellation and waits for the worker; games
already committed remain in the database.

Use **Rebuild position summary** only when the position index needs to be
recreated, for example after repairing or migrating a database.

### 9.2 Finding games

The game filters include White, Black, Event, Player, and a maximum number of
rows. Click **Apply filter** after changing them. Click the White, Black, or
Event column heading to sort; click it again to reverse the order. Double-click
a game to load it in the main window. Chess loads the complete PGN, including
comments and variations, through the same Save / Discard / Cancel protection as
opening a PGN file.

### 9.3 Searching for a position

The database board's context menu also offers **Paste FEN position from clipboard**.

Enter or paste a FEN in the position panel and click **Search**. The result lists
continuation moves with game, win, draw, and loss counts and provides matching
games where practical. Chess moves are shown in SAN. Only mainline positions
are indexed, including the starting and final positions; variations remain
available when loading the complete game. Position matching includes side to
move, castling rights and legally usable en passant, and ignores move counters.
Transpositions therefore find the same position.

The continuation grid counts occurrences: a repeated position in one game can
contribute more than once. The matching-game list counts distinct games. Wins
and losses are from the side-to-move perspective. Games with result `*` contribute
to occurrences but not to wins, draws or losses. A final position without a next
move can appear in the matching-game list without a continuation row.

Double-click a continuation row to play that move on the database miniboard and
search the resulting position. The FEN, continuation statistics and matching
games update together, so you can keep double-clicking to explore an opening.
This browsing leaves your main game unchanged. After editing the FEN or applying
position setup, click **Search** before choosing a continuation. If a stored
continuation is illegal, it is marked `(?)` and cannot be played.

The database board's context menu can copy or paste FEN and open the position
setup window.

When a database is open, enable **Search position in database** from the main
board's context menu. The database search then follows the position displayed
while you play or browse. If this option is enabled, the next main-board
navigation also replaces any position you explored inside the database window.

## 10. Preferences

Choose **File > Preferences**. Select **Chess** or **Draughts** at the top to edit
that game's appearance. The existing pages are reused for each game; switching
sections keeps both drafts and does not change the main board's selected game.
The dialog initially selects the game currently shown in the main window.

Windows and dialogs adapt their rows, labels and minimum sizes to the active font.
Resize or maximize them to give boards, lists and text areas more room. Toolbars
and database filters wrap when needed; preferences pages scroll when their content
needs more space. The main FEN field fits a full chess FEN and expands for longer
displayed positions. The game-moves pane prefers ten lines at its active
notation font when space permits, with a usable three-line minimum in smaller
windows. Smaller windows compact the score graph and log space while retaining
readable PV/status text and the complete MCTS statistics table. Existing splitters
still let you adjust the main panes.

In tables, the mouse wheel scrolls the view without changing the selected row.
Use a click or the arrow keys to change selection. Dragging a horizontal or
vertical scrollbar updates the view while you drag, including in tournament
lists and engine parameters.

The appearance settings control:

- light and dark squares of the main board;
- light and dark squares of analysis boards;
- target, last-move, PV-move, and hint highlighting.

The evaluation settings control:

- maximum displayed score;
- linear or logarithmic score scaling.

The **Notation** tab controls the game moves window. Choose a colour and set
**Bold** and **Italic** independently for each category:

- **Played moves**: bold by default;
- **Variations**: green and italic by default;
- **Engine PVs**: blue by default;
- **Annotator PVs**: purple by default;
- **Auto Play PVs**: blue by default;
- **Comments / other text**: gray and italic by default, including move numbers,
  punctuation, scores and clocks outside move ranges.

Customised older shared PV styles are retained for the new source categories
until you change them; otherwise engine and annotator PVs get distinct defaults.

Use **Font...** on the Notation tab to choose the font family and point size for
the whole moves window. Monospaced fonts work best. Bold and italic remain
independent per-category settings. Cancelling the chooser keeps the current
choice; **Save** applies and remembers it, and **Defaults** restores DejaVu Sans
Mono 11 pt on Linux or Consolas 11 pt on Windows. This is separate from the
application's general UI font.

The moves window uses SynEdit with wrapping and one font family/size. Changing
these settings affects only presentation: move/variation/PV clicks, Left/Right navigation, selection/copy and
saved game files keep their existing meaning. Colours and styles apply when you choose
**Save**; editing the dialog or choosing **Defaults** alone does not apply them.

Use **Chess defaults** or **Draughts defaults** to reset only the selected game's
draft. **Save** applies and persists every changed game section together. Settings
for an inactive game take effect when you select that game in the main window.
**Close**, including the window's close button, asks **Discard / Cancel** when
there are unsaved changes in either section; Cancel keeps both drafts.

Preferences are stored in `prefs.json` beside the ZGUI executable, under
`game_preferences.chess` and `game_preferences.draughts`. Existing root settings
remain as fallbacks for older files and are preserved when saving a game section.
Board orientation remains shared.

## 11. Common problems

### An engine does not appear in a game dialog

Check the selected game first: UCI engines are offered for chess; Hub/DXP for
draughts. The engine may also be reserved by another game or loaded as an annotator.
Stop the other use or register a separate engine instance. Also check that the
engine test was completed with **Launched correctly**.

### An engine does not start

When an engine or annotator cannot be started, ZGUI writes the reason to the
log and also shows it in a dialog. If the executable is missing, nothing is
launched; the Engines dialog marks such an engine with **(not found)** in the
executable column.

A message that the path "was written on another operating system" means that
`engines.json` was copied from, for example, a Linux installation to Windows.
Engine paths are not portable: register the engines again on this computer
with **Engines...**.

### A DXP engine cannot connect

Check the `listen`/`connect` role, host, and port. Confirm that the peer uses the
opposite role and the same port, and that no other configured DXP engine is
using that local port.

### Scores have the wrong sign

Edit the Hub engine and set `gui-score-perspective` to match what the engine
reports: side to move, White, or Black. ZGUI's display itself always uses
White's perspective.

### The score history is empty

For chess, use a UCI engine that reports a scored legal PV. The DXP socket does
not carry analysis scores; an engine that writes Hub-format analysis to stdout
can supply them with the **dxp-pv** feature flag (section 2.5). Other DXP engines
need a separate compatible annotator for an analysis score. For Hub engines, confirm
that the engine reports score information and
that `gui-score-perspective` matches its output. Loading a Hub annotator can
provide a separate annotator score.

### Auto Play is disabled

Stop the selected game and load an annotator (UCI for chess, Hub for draughts).
Auto Play requires the selected game to be in the stopped state; it is unavailable
while waiting to start, running, completed by a game result, or without an annotator.
While Auto Play is active, its button becomes an enabled **Stop** button. Click it
or press Escape to stop and restore the Auto Play caption.

### A tournament will not start all requested games

The concurrency value is an upper limit. Actual concurrency is also restricted
by available engine instances and DXP port conflicts.

### A saved PGN or PDN contains more than one game

**Save PGN** and **Save PDN** append. Select a new file when you do not want to add the current
game to an existing collection.

### A database will not open on Windows

The database features require **64-bit `sqlite3.dll`** for the x86_64 ZGUI build.
Place it beside `zgui.exe` so ZGUI can find it without relying on another program's
installation or PATH. Building ZGUI does not copy this library into the folder.
The SQLite command-line program `sqlite3.exe` is not a replacement for the DLL.

ZGUI loads SQLite when a database operation needs it. Starting the GUI or playing
a game without an error does not prove that SQLite is available. Test **Create
database** or **Open database** on Windows before distributing an installation.
If it already works with no DLL in the ZGUI folder, the library is being found
elsewhere on that computer. With a database open, PowerShell can show its location:

```powershell
(Get-Process zgui).Modules |
  Where-Object ModuleName -eq 'sqlite3.dll' |
  Select-Object FileName
```

## 12. Installation and developer notes

ZGUI is an Object Pascal application built with Lazarus/LCL 3.0 or later (GTK2
on Linux), its bundled SynEdit package, and Free Pascal 3.2.2 or later. The
boards draw their pieces directly; no external piece font is required.

**Runtime libraries:** Linux needs GTK2 and SQLite3. This build's SQLite loader
looks for `libsqlite3.so`; having only `libsqlite3.so.0` without the expected
library name may be insufficient.
Windows database features need the matching 64-bit `sqlite3.dll`; include it beside
`zgui.exe` in a portable release. SQLite is loaded on demand, not compiled into
ZGUI. Engines and their networks, books or tablebases are installed separately.

A typical source build is:

```bash
bash build.sh
```

`build.sh` embeds the current manual and Git build identity. On Windows, run
`build.bat` from the source directory; it finds `lazbuild.exe` on PATH or in a
standard Lazarus folder (or takes its path as an argument), builds `zgui.exe`
with the **Windows** build mode in `lib\candidate`, and replaces `zgui.exe`
only after a successful build, so a failed or interrupted build keeps the
previous executable. Alternatively, open `zgui.lpi` in Lazarus, select the **Windows** build
mode under Project → Project Options → Build modes, then choose **Build**. Both
use the build mode's pre-build step, which uses
Lazarus’s configured compiler to embed the manual and Git identity; Python is
not required. Install Git for Windows and make `git` available on PATH before
starting Lazarus. Use a Git checkout or copy including `.git` to identify the
commit. Changes to tracked files are marked in About.

Direct IDE builds in the **Default** mode or
`lazbuild zgui.lpi` builds remain supported, but report that the commit is
unavailable and load `MANUAL.md` from beside the executable. Builds from source
archives without Git metadata explicitly report that the commit is unavailable.

The repository's regression checks can be run with:

```bash
bash tests/run_regression_checks.sh
```

They need FPC, Python 3 and ripgrep. The other suites in `tests/`
(`run_gui_checks.sh`, `run_tournament_checks.sh`, `run_lifecycle_checks.sh` and
`run_dxp_checks.sh`) also need Lazarus/GTK2 and a display.

The source separates the game from the rest of the program. Game-neutral units
(game tree, notation walker, analysis state, orchestrator and game runner) reach
the game only through `uGamePosition`; international draughts is implemented in
units named `uDraughts*`. `tests/source_audit_check.sh` enforces the separation.

For DXP details, see [DXP Protocol.md](DXP%20Protocol.md). A local Scan
distribution includes `protocol.txt` for its Hub handshake and commands.

### 12.1 File locations and portability

- `engines.json` and `prefs.json` live beside the ZGUI executable. Keep that
  directory writable. Private UCI options are in `engines.json`. Hub/DXP and legacy
  UCI `.params.json` files live beside the engine executable (section 2.6);
  launch/INI paths remain part of engine configuration.
- PGN/PDN, database and saved tournament files live where you choose them. Import logs
  use the imported game file's filename with the `.import.log` extension beside it.
- Unsaved tournament recovery is the exception to portable storage: it uses the
  operating system's per-user application configuration directory, under
  `tournaments` (normally `~/.config/zgui/tournaments` on Linux). The tournament
  **Load** dialog opens that recovery directory for an unnamed tournament.

## 13. Keyboard reference

Use **Alt+F** for File, **Alt+D** for Database and **Alt+H** for Help. Keyboard
shortcuts are also shown beside their menu items:

| Action | Shortcut |
|---|---|
| Open game (PGN/PDN) | Ctrl+O |
| Save game (PGN/PDN) | Ctrl+S |
| Preferences | Ctrl+, |
| Create database | Ctrl+Shift+N |
| Open database | Ctrl+Shift+O |
| Quit | Ctrl+Q |
| Manual | F1 |
| About ZGUI | Shift+F1 |
| Flip the main board | F |
| Browse the focused move list, tree or PV | Left / Right Arrow |
| Stop Auto Play | Stop toolbar button or Escape |
| Leave game/PV browsing | Escape |
| Find text in the manual | Ctrl+F |
| Next manual match | F3 or Enter |
| Previous manual match | Shift+F3 |
| Close the manual | Escape |

**File → Quit** uses the same save prompts and safe shutdown as closing the main
window. Choose Cancel in a save prompt to keep working.


## 14. Help and version

Choose **Help → Manual** (F1) to open this manual inside ZGUI. The manual is
read-only and available offline in builds made with `build.sh` or the Windows
Lazarus build mode.

The manual window shows the contents on the left and the formatted manual on the
right: headings, bold labels, `highlighted` names and values, bulleted and
numbered lists, and tables with aligned columns. Click a section or subsection in
the contents to show it at the top; while you scroll, the contents mark the
section you are reading. Drag the divider to change the width of the contents.
The text is laid out again for the width of the window, so long lines never need
horizontal scrolling (only example code keeps its original lines). You can select
and copy text as usual.

Type in **Find** to search. Searching ignores the case of the letters A–Z and
treats any run of spaces and line breaks as one space, so a phrase is found even
where the layout breaks it across lines. The first match is highlighted and the
result count is shown. **Next** / **Previous** move between matches and wrap at
the ends; use **F3** / **Shift+F3** for the same actions. **Ctrl+F** focuses and
selects the search query. **Enter** finds the next match, and **Escape** closes
the manual window.

**Help → About ZGUI** shows the build description and full Git commit captured
when the executable was built. A build made from modified tracked files is
marked as including uncommitted changes. This identifies the running executable;
it does not query whichever checkout happens to be on disk later.

# Named tournament tabs and explicit Close — proposal, 2026-10-31

Status: approved with conditions in `claude/review-559f6aa.md` (2026-10-31).
The user requested proceeding with the fixes and tabbed approach. The embedding
spike is the required first step; native Windows validation remains required
unless the user explicitly waives that prerequisite. Production tournament-tab
integration has not started.

## Request and current behaviour

The user requested a multi-tabbed tournament window, tabs named after their
individual tournaments (Tournament1, Tournament2, etc.), and a warning on Close.
The user clarified on 2026-10-31: “The warning should be that this will stop the
tournament and give the save/discard/cancel options”. This confirms the product
behaviour; it does not waive the shared-code review gate.

Currently there is one TTournamentDialog per game context: one chess and one
draughts tournament. Each can run multiple games concurrently, but the normal
GUI does not create two independent tournaments of the same game. Closing the
nonmodal dialog uses LCL's default Hide and leaves its timer/scheduler alive.
The current data is retained; that action is confusingly presented as Close.

## Proposed window

One Tournaments window contains one TPageControl. Each tab contains the existing
tournament UI, with its settings, pairing grid, cross-table, Play/Stop and file
actions kept in their existing relative layout. No copied tournament scheduler,
record model, pairing algorithm or game runner.

- New tournament creates a tab for a chosen game (current main-board game as
  default) and a unique initial display name Tournament1, Tournament2, etc.
- User clarification (2026-10-31): “could you update the tournament settings
  rather than opening a new tab when switching from draughts to chess?”
  The Game selector changes the current tab in place; only New tournament
  creates another tab. Preserve the tab identity and name, apply the target
  game's engine filter, starting FEN and clock defaults, and keep the main
  board and all other tabs unchanged. Protect existing/running data through
  Save / Discard / Cancel before clearing incompatible pairings/results.
  After stopping/capturing, replace the existing dialog within that same tab
  with a target-variant dialog, reusing its existing construction/validation.
  Begin a new tournament identity when the game changes; never relabel a
  saved chess tournament as draughts or reuse its output paths.
- A tab follows the existing Tournament name field. Its game is identified in
  the visible title too, for example “Tournament1 (Chess)”. Duplicate custom
  names need a visible disambiguator; neither name nor tab index is identity.
- Two chess and two draughts tabs may exist and run together. Existing per-
  tournament concurrent-game limits and global engine reservations remain in
  force. A registration already reserved elsewhere must wait, as it does now.
- Switching tabs does not switch the main board, stop analysis, or restart a
  tournament. Explicitly selecting one of its games retains the current action.
- Tournament... raises the host and selects the last-used tab for the main
  board's game, creating its first tab only when none exists. New tournament is
  the explicit way to create another. No accidental duplicate tabs on reopen.
- Minimizing the host window leaves tournaments running. Close is not Hide;
  a separate Hide feature is outside this proposal.

## Close policy — confirmed by the user

Close tab concerns only that tournament. For a running tournament, show:

> Closing “Tournament1” will stop this tournament, including its running games.
> Remaining pairings will be left unplayed. Other tournaments will continue.
> Save the tournament before closing?

Buttons: **Save**, **Discard**, **Cancel**. Cancel is the default and Escape
behaves as Cancel. Both Save and Discard stop and close that tournament; Cancel
leaves it running and the tab open. No window-close action silently means Hide.
Preserve existing saved files in every case.

- Save must preserve a final authoritative snapshot after workers stop and
  results are captured; saving only before Stop would miss final state.
- Discard closes without an explicit Save. Existing automatic recovery and
  publication files remain; it does not delete or roll back autosaved state.
  Explain this in the dialog/help rather than promising unsaved-state rollback.
- Resolve any Save destination dialog before stopping: cancellation changes
  nothing. A save failure retains the tab. A failed final save may leave it
  stopped and open, with an actionable error; do not claim all-or-nothing
  cancellation once stop requests have already been sent.
- A finished tournament needs no running-games warning. Protect unsaved state
  with the same Save / Discard / Cancel decision where applicable.
- Stopping does not clear pairings or fabricate results for unplayed games.
  Retain the existing stopped-game and resume behaviour in saved state.

Closing the host window concerns all its tabs. Its warning must explicitly say
that all running tournaments in the window will stop, list their names, and
protect their saved state. Confirm all save/close decisions and destinations
before requesting any stops; Cancel at that stage leaves every tournament
unchanged. Do not merely close the selected tab or hide the others. Global
application shutdown uses this same close policy and the existing worker drain,
rather than prompting twice. Final-save failure retains the affected tab(s).

## Reuse and ownership seams for review

1. A small host owns a list of existing TTournamentDialog instances, with a
   stable tab/session identity. Embed each existing form in its TTabSheet
   (borderless, aligned to the page) if native LCL behaviour is sound. Validate
   layout/focus/minimum sizes first. Do not rewrite its controls as a second UI
   or silently extract a second tournament controller if embedding fails.
2. Preserve the main form as each dialog's Component Owner: current callbacks
   and engine-reservation queries rely on Owner being TMainForm. Visual Parent
   and lifetime management by the host are distinct; explicitly free dialogs
   and tabs with notification-safe removal.
3. Replace per-game singleton tournament lookup with enumeration of the host's
   sessions. Existing running games already carry TournamentOwner pointing at
   the initiating dialog; keep that identity and its result-routing callbacks.
   Neither active tab nor active game may route a background result.
4. Add only the close-preparation/finalization seams needed by the host to the
   existing dialog. Reuse StopRunningGames, capture, existing JSON/PGN/PDN and
   error handling. Stop scheduling before draining games. Free a dialog only
   after its workers/captures are retired; retained main-list games must no
   longer reference a destroyed TournamentOwner.
5. Keep current JSON format, tournament ID and unique recovery filenames.
   Reject or activate an existing tab when opening its same tournament/file
   again. Two tabs must never write the same authoritative file or publication
   path. Save As must check all open tabs before transferring a destination.
   Do not introduce a new persistence schema or automatic folder scan here.
6. Loading a tournament opens/selects its own tab using the file's variant,
   rather than replacing whichever same-game singleton is currently stored.
   Existing validation, saved results, history and recovery remain authoritative.
7. Track unsaved settings through the existing settings-signature/invalidation
   machinery. Audit whether authoritative state has been saved successfully;
   do not add a second tournament data model just to decide whether to prompt.

## Verification required for approval/implementation

- Four independent tabs: two chess, two draughts, with interleaved completions.
  Verify background starts and tab switches preserve the main selection and
  annotator. Exercise independent results, pairing, standings and publication.
- Reservation conflicts across same-game tabs and loaded annotators; no engine
  process is launched twice under one reserved identity.
- Tab naming, rename, duplicate names, reopen, same-file/tournament-ID handling,
  cross-variant file load, conflicting Save As and independent output files.
- Running and completed close, Cancel, Save cancellation/failure, recovery error,
  Stop during initialization, pending result capture and final snapshot saving.
- Close one tab while the other three run. No other timer, engine, result or
  file is affected. Games retained in the main list remain safely viewable.
- Host Close and application shutdown enumerate all tabs and protect workers
  and model lifetimes, retaining the T6 guarantees. Minimize keeps running; Close never silently hides.
- Existing font/window/DPI layout checks, Windows tab/focus/closing QA, the full
  GUI sweep, headless checks and both tournament suites. Tests use isolated
  registrations/files and leave engine*/ and the sibling GWDGUI untouched.

## Explicit exclusions

No new pairing algorithms, clock/game engine, tournament result policy, game-tree
implementation, database work, per-executable options redesign, or automatic
resource-limit policy. This proposal does not implement pending engine flags.

## Claude's approval conditions — 2026-10-31

1. Embedding spike with two existing dialogs first, including layout, focus,
   default/cancel buttons and keyboard behaviour. Native Windows run required;
   Linux/Wine is not native Windows. If embedding proves unsuitable, propose
   extracting the existing body into a TFrame before that shared refactor.
2. Busy-engine rows must identify the engine and owning tournament, such as
   “Waiting for engine X, in use by Tournament1”. Reuse reservation identities;
   never launch a duplicate reserved engine or silently leave a row stalled.
3. Discard preserves existing files but must not cause an automatic resume offer
   later. Current startup does not enumerate/offer tournament recovery files;
   keep that behaviour. If an automatic restore path is added, explicitly mark
   discarded sessions so they are not offered. Deliberate file loading remains
   a separate explicit action; no implicit replay on Open.
4. Close-stopped rows save `*` and “Stopped: tournament closed”. Reopen/resume
   must replay only stopped/unplayed rows, preserving completed results and
   history. Extend the existing transient/retry status checks for this reason;
   do not mark arbitrary failure reasons retryable.

The new U26 laptop-height finding is an independent GUI fix. No repository
pruning, AGENTS.md commit, or unfinished feature-flag implementation is included.

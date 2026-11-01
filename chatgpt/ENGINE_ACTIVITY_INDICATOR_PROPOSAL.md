# Engine sessions in use: global GUI indicator

Date: 2026-11-01
Status: implemented and verified on 2026-11-01.

User authorisation, 2026-11-01: “Please proceed with the small toolbar readout.
We could also show it in the bottom area of the window?” Implement the named
readout without prior review, using the bottom status area as requested;
Claude reviews the resulting commit afterwards.

## User request

“Could we show somewhere the number of active engines in the GUI (playing
matches, annotators)? The idea is that the user can gauge oversubscription.
It does not make sense to monitor the number of threads, GWD for example uses
2 threads but 1 thread is for communication only.”

## Display and meaning

Add one measured label to the bottom status area of the main window:

    Engines in use: 6 — games: 4, annotators: 2

This is a global session count across chess, draughts, standalone matches and
all tournament tabs. Do not infer CPU demand from operating-system thread counts
or engine options. Do not add automatic throttling, core allocation or warnings.

- Count each registered-engine player slot in a live game, including its idle
  opponent and pondering session. Human players add zero.
- Count each open annotator and MCTS annotator session once, including sessions
  in hidden game contexts. Auto Play uses the existing annotator; it adds no
  separate engine.
- Include starting and stopping sessions until the existing owner consumes the
  completion event and releases them. This describes sessions in use, rather
  than claiming that every engine is calculating at that instant. Startup can
  temporarily include an assigned engine whose launch has not completed.
- Exclude queued tournament pairings, completed games, saved registrations and
  brief engine-configuration probes. A remote DXP opponent counts as an engine
  session too; this is not an exact local CPU-load/process count. State these
  semantics in the tooltip and manual.

Use existing layout/font helpers to measure the bottom-aligned label and its
minimum width/height; no fixed pixel width, clipping or new window. Existing
board/analysis panes keep their arrangement above the small status line.

## Existing sources and minimal implementation

- `TMainForm.FGames` already owns all live standalone/tournament games for both
  variants. `TRunningGame.IsEngineReservationActive` remains true until its
  existing lifecycle reaches `rglFinished`, including Stop/removal pending.
- `TRunningGame` already stores `FWhitePlayerKind` and `FBlackPlayerKind` but
  does not expose a read-only player-slot count. Add a small `EnginePlayerCount`
  method returning the number equal to `pkRegistered`. Do not clone setup/engine
  definitions on every GUI refresh, inspect worker-private data or infer player
  kind from display names. Keep all lifecycle/ownership behavior unchanged.
- Sum that method only for existing active-reservation games. Do not count
  reservation keys: `AddEngineReservationKeys` can add identity and endpoint/port
  keys for one DXP engine. Do not deduplicate engine identities; separately owned
  engine sessions are separate instances even when the executable is the same.
- For annotators, read active form `FAnalyzerRunner` / `FMctsRunner` references
  and the corresponding references in *other* `TGameUiContext` objects. Skip
  `FActiveContext` while traversing stored contexts, because its saved fields
  can mirror/stale-cache the active form. Follow the same active/hidden context
  separation used by `CollectBusyEngineKeys`, without mutating its reservations
  or calling `CaptureGameContext` just to count.
- Recompute on the existing GUI timer after event delivery; update label text
  and invalidate measured layout only when the displayed counts change. All
  reads are GUI-owned lifecycle/reference data. No process polling, worker
  messages, new global engine registry or scheduling changes.
- Keep both variants' totals visible when switching games or tournament tabs.

## Verification

Extend existing GUI/lifecycle fixtures rather than replacing them. Cover zero
at startup; human/human, human/engine and engine/engine matches; concurrent chess
and draughts tournaments; queued pairings; both annotator types; hidden contexts;
pondering; Auto Play not adding a session; launch failures; Stop/close/removal and
late completion without double counting. Include a DXP reservation with multiple
keys to demonstrate that the count is one engine slot, not multiple resources.
Test font/window resizing and tooltip visibility without opening the user's main
display. Run the full headless suite, all GUI checks (including multi-game), both
tournament suites and application compilation. Update manual and changelog.

## Review gate

This needs a read-only addition to the shared running-game interface and a shared
main-form presentation change. Per `AGENTS.md`: “Proceed only after approval.”
The user has authorised this named readout, as quoted above. The earlier
termination-reason waiver is not used for this work. The implementation reuses
existing ownership and reservation lifecycles; unfinished engine-feature work
remains untouched.

## Verification results — 2026-11-01

- Final GTK2 application compilation passed.
- Full headless regression sweep passed, including both games' rules, engine
  lifecycle/clocks/pondering, database, source/build identity and manual checks.
- Final full GUI sweep: all 19 suites passed on hidden displays, including
  multi-game (173), UCI GUI/Auto Play (128), measured layout (9762), engine-end
  reasons (266) and tournament tabs (200). Multi-game and layout tests report
  zero unfreed memory blocks.
- Both chess and draughts tournament suites passed again with the relocated
  chooser (chess: 101 checks). Focused tournament layout/capture checks passed
  976 assertions with no failures; initial and resized captures inspected.
- Staged Pascal sources/tests matched the isolated tested source snapshot.
  Excluded unrelated unfinished engine-feature changes and left engine
  directories and user PGN files untouched. Native Windows QA remains pending.

## Follow-up: native status bar — 2026-11-01

Within this previously authorised readout, the user requested: “Can we remove the
extra space below the engine-count label” and “Could we move it to the TStatusBar?”
This is the named indicator's presentation correction; no scheduling, lifecycle,
counting or other shared functionality changes. Claude reviews the resulting
commit afterwards under the existing authorisation quoted above.

Replace the main-window label with one native TStatusBar (SimplePanel/SimpleText),
with no external bottom spacing. Native AutoSize uses a measured minimum height (font plus native borders), with
the main window's font and a text minimum including margins/size-grip space. Leave AutoHint
false so menu hints do not replace the engine total. Retain the explanatory Hint
and ShowHint, and the existing update trigger/counting code.

The multi-game check asserts native bottom-edge placement, absence of the old
label/padded row, stable status text rather than automatic menu hints, and the
same cross-game counters. The UCI check reads SimpleText. The full layout sweep
checks bottom alignment and font fit at normal/enlarged fonts and different window
sizes/DPI. The focused multi-game suite passes 175 checks. Full-suite results are
recorded in CHANGELOG.md; all GUI execution uses hidden displays and isolated
configuration. Native Windows visual confirmation remains pending.

The enlarged-font check exposed a GTK status-bar preferred height that did not
increase enough on its own. Set a measured minimum height using the current font
plus native edge metrics, while retaining zero external spacing. The focused
main-window font/size/DPI sweep then passes 1,188 checks with no reported leaks;
its captured images confirm the status bar meets the bottom edge.

Final verification: application compilation, all 19 GUI suites and both tournament
suites pass on the final source. Layout/font/DPI: 10,410 checks; multi-game: 175;
UCI GUI: 128; tournament tabs: 364; chess tournament: 101. Final heap reports show
zero leaks. The isolated test snapshot matches the staged application/test source;
unrelated unfinished engine-feature work is excluded from the build and commit.


## Follow-up: GTK2 internal status-bar height — 2026-11-01

Within the earlier authorisation, “Can we remove the extra space below the
engine-count label” and “Could we move it to the TStatusBar?”, the user supplied
Linux and Windows screenshots. Windows fits one line. Linux shows blank space
inside the status-bar bounds, which bottom-edge placement checks alone missed.

The Lazarus GTK2 status-bar implementation obtains preferred height from a
separate theme widget (`TGtk2WSStatusBar.GetPreferredSize`), rather than measuring
this control's font. A minimum height only prevents clipping; it cannot constrain
an excessive preferred height. For LCLGTK2 only, disable native AutoSize and set
Height from the existing measured minimum (current font plus native edge space)
in RefreshLayout. Keep normal native sizing on Windows. Retain TStatusBar,
its alignment, hints, count and update triggers. No native widget replacement,
GTK theme modification or engine/game logic changes.

Extend the existing both-game layout sweep to bound the GTK height by the text
height plus native edge space, as well as checking bottom placement and text fit.
Focused main-window
font/size/DPI checks pass 1,204 assertions without leaks; full-suite and build
results are recorded in CHANGELOG.md. All GUI execution uses hidden displays.
The user's desktop theme still needs visual confirmation after restarting the
rebuilt Linux executable. This correction remains in the named readout scope;
Claude can review the resulting commit afterwards.

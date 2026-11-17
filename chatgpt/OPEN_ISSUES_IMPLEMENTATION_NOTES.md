# Open-issues implementation

2026-11-17 user authorization, exact words:

> Could you now review ISSUES.md and address all open issues you agree with. You do not need to ask for approval from Claude.

Scope: the open issues in claude/ISSUES.md: C14, C11, F6, F7, U26, D6, U21, F8.
Only Coder comments in open rows may be edited; reviewer-owned statuses/fields
remain unchanged. Preserve existing GUI/shared implementations and both games.
Do not touch user engine directories, Claude outputs, or /tmp2/gwies/GWDGUI.

## Initial assessment

- C14/F6 and reported F7 retained-history delay implemented in e4d55b0; existing
  regression and real 160-game close evidence retained, not rewritten.
- C11: native Windows validation is outstanding, not an identified remaining code
  defect. Check available Windows/Wine tooling and report exact limitations.
- U26: reproduce the Inter-font sizing cases before changing layout.
- D6: assess per-registration option storage with legacy compatibility, reusing
  engine registry/parameter readers rather than new engine infrastructure.
- U21: implement inclusive Delete from here via existing tree removal/actor/GUI
  paths with stopped-only safety and stale-search protection.
- F8: coalesce the two synchronous notifications for one history removal into
  one save, preserving capture before release and immediate final persistence;
  avoid introducing timer-delayed ordinary saves or a new persistence layer.

Implementation/validation/commit records will follow here.
## Implementation

Implementation commit: `043134f`.

### D6: UCI options per registration

Use the existing engines.json definition with an optional uci_options array.
Missing means legacy executable-side parameters; an explicit empty array means
private native defaults. Saving the existing editor migrates only that registration
and leaves the old file unchanged. The acceptance callback receives the options
before registry persistence. Runtime cloning and UCI launch use the same definition
loader. Existing registry identity/arguments/INI fields remain authoritative;
the options array cannot replace them with stale copies. Hub/DXP storage is
unchanged. Legacy shared-file confirmation remains; private registrations bypass
that warning. No engine/process infrastructure is replaced.

Tests use two registrations of one real fake-UCI executable: Hash 32 and 64 reach
the separate processes; legacy Hash 16/file contents remain unchanged. Registry
roundtrip, definition cloning, private empty defaults, editor reopening, custom
identity, changed launch arguments, INI, validation and failure paths are covered.

### U21: Delete from here

The existing Game Tree popup creates a revision/parent-stamped actor command,
uses TrimMainlineToCount or RemoveBranch, invalidates existing topology caches and
removed-target searches, and selects the retained parent through existing GUI
refresh paths. Confirmation defaults to Cancel. Root, active games, unfinished
runner teardown and virtual PV previews cannot be edited. Prefix metadata,
siblings and game result are retained. No undo is introduced.

Finished history is marked edited so late/replayed runner snapshots cannot restore
the original tree. This is a history edit, not an automatic rewrite of an archived
tournament record. Existing PGN/PDN save paths export the edited tree. The tests
exercise inclusive middle/tip/first deletion, root/missing/stale rejection,
variation deletion, retained metadata, invalidated searches and append-after-delete;
PGN/PDN save/reload retains the surviving mainline, sibling and comment. GUI tests
exercise cancellation, running-state prohibition, stopped history editing, stale
snapshot replay and selection away/back, for both games.

### F8: one immediate save per removal

GameRemoved calls GameStopped with saving suppressed, removes its live reference,
then performs the existing immediate AutoSaveTournament once. MainForm.RemoveGame
uses this one notification. Capture/update happens before release. Normal stopped
notifications retain their immediate saves. No timer, global batching, or new
persistence layer is introduced. Both-game end-reason GUI fixtures assert exactly
one snapshot write per removal and preservation of the recorded reason.

### Previously fixed and verification-only findings

C14/F6/F7 retain e4d55b0 and the evidence in SHUTDOWN_REVIEW_F875EFE_NOTES.md;
no global worker-join API was added. U26's current layout passes the reported
Inter-font cases, so the change strengthens tests rather than guessing a layout
fix: normal main window stays within 700 pixels; the hidden/embedded three-tab
host is tested at 720 pixels. Existing all-font main/tournament layout checks pass.

C11 stays outstanding: Wine validates build.bat but is not native Windows CLI
transport proof. The cross-check script reports no x86_64-win64 compiler units.
No native Windows run or closure is claimed.

## Validation

- Full regression suite passed; final focused UCI test and tree boundary additions
  are rerun separately (102 UCI checks; 74 tree-deletion checks).
- Both tournament checks, lifecycle and DXP suites passed.
- Focused GUI: deletion 54; end-reason/save 314; UCI editor/analysis 129;
  tournament tabs 447; main readability with installed Inter 125.
- Full GUI rerun and final GTK2 build: completion recorded below.
- User engines, GWDGUI, and Claude outputs remain untouched. Tests run on a hidden
  display. Only open-row Coder comments are changed in the local issue list;
  reviewer-owned statuses and review files are untouched.

Final validation: all 28 GUI suites passed (0 failed), including multi_game_gui_check.
The final GTK2 application build passed and installed the root zgui executable.
Latest U26 diagnostics: main height 650/minimum 590 for both games; all three
Inter-font tournament tabs height 720/minimum 596. Final focused UCI checks: 102;
final deletion boundary/persistence checks: 74. Native Windows QA remains open.

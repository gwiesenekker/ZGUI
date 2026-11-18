# Response to review-ffccb25

2026-11-18. User request, exact words:

> Could you review Claude's latest review, update ISSUES.md, and address the findings you agree with? Please update CHANGELOG.md, compile, test, and commit.

Scope: reviewed C15 test corrections, the manual clarification in the review notes,
and comments in the two open issue rows. No new shared application behaviour.
Prior review: claude/REVIEWS.md, review-ffccb25. The earlier request to address
open issues without requesting Claude approval also remains recorded in
OPEN_ISSUES_IMPLEMENTATION_NOTES.md. Only open Coder comments are edited in
ISSUES.md; reviewer statuses, closed comments and review text stay untouched.

## Assessment

Agree with C15. A hard laptop acceptance check after forcing a 10-point or Inter
font conflated application-default sizing with font stress. More text must still
fit at a larger font, but its measured minimum need not satisfy the same fixed
laptop-height acceptance limit. The real application was already verified fixed
for U26 by Claude. No product layout change is warranted here.

C11 is still native Windows verification, not an identified remaining Linux code
defect. No native Windows result is available in this environment and no closure
is claimed.

## C15 implementation

- Measure the freshly shown main form for both games before any font/DPI stress;
  use default application fonts, request 1000x650, and assert actual height <=700.
  Report system font, form font, size, height and measured minimum. The all-dialog
  layout matrix measures this before changing fonts; later stress checks still
  inspect containment and text fit without a laptop-height requirement.
- The readability suite likewise measures both default-font games first, keeping
  its existing larger-font/notation/FEN/MCTS assertions as a separate phase.
- In the hidden-host tab check, keep the host/child default fonts rather than
  forcing Inter into an already embedded three-tab host. Request 690 pixels high
  for each tab and enforce <=700, also checking the child fits its page.
- Test-only TGuiLayoutTestWatch observes bounds through additive LCL handlers,
  preserving production event handlers, and removes observers on destruction.
  More than 5000 bounds changes without a test checkpoint aborts with the phase,
  count and last control path/bounds. An independent thread also aborts after
  20 seconds without progress, even if native GTK never returns to LCL. The last
  observed LCL control is diagnostic context, not proof it caused a native-only
  stall. Halt exits the test process without trying to unwind a GTK allocation
  loop. Existing outer per-process timeouts remain.
- Watchdog covers the tab, readability and layout-matrix suites. Its two deliberate
  failure probes are run as child processes: a panel toggling its bounds and a
  blocked main thread. Both must exit 3 with the expected diagnostic, within an
  outer 8-second timeout. Registered in run_gui_checks.sh.
- An attempted explicit Application.Scaled=True setup exposed different legacy
  harness assumptions and was discarded. No scaling or product changes remain.

## Review notes

The manual now warns that private registration options do not isolate logs,
learning files or other engine-written files next to the binary. Separate engine
folders are still needed if that engine cannot share such files safely.

The manual already states in section 4.3 that editing a finished history tree does
not automatically rewrite an archived tournament record. No duplicate wording.

A frozen settings-used record would be a useful separate reproducibility feature;
it is not needed for C15 and is not implemented here. Existing identity keys stay
unchanged for saved-tournament compatibility.

## Validation

- GTK2 application build passed.
- Full regression suite passed (tests/run_regression_checks.sh).
- All 29 GUI suites passed, zero failures (tests/run_gui_checks.sh), including
  multi_game_gui_check, the 11,258-check layout matrix, readability 125, tabs 447,
  and both deliberate watchdog failure probes.
- With a temporary GTK2_RC_FILES containing gtk-font-name = "Inter 10":
  readability 125, presentation-only tabs 273, and main-only layout 1,204 passed.
  Main height/minimum: normal default 650/593, Inter default 650/608, both games.
  Three tab heights/minima: 690/596. No font override is applied to laptop
  acceptance inside the tests; optional explicit font changes remain stress only.
- ISSUES.md field comparison confirms only the two open Coder comments changed.
- All GUI tests used hidden displays. No user engines, GWDGUI or Claude outputs
  were modified. Native Windows CLI verification remains outstanding.

Implementation commit: pending.

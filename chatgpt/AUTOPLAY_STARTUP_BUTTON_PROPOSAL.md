# Restore Auto Play availability after game-feature refresh

Date: 2026-11-01
Status: implemented and verified on 2026-11-01.

User authorisation, 2026-11-01: “Apply the Auto Play correction too; waive prior
review”, in response to the question naming this one-line correction. Scope:
restore button availability after the feature pass; no Auto Play move/annotation
or rules changes. Claude reviews the resulting commit afterwards.

## QA and cause

User: “QA: when you launch ZGUI auto-play is enabled.”

`TMainForm` initially disables `FAutoPlayButton`. Its existing
`UpdateAutoPlayButtonState` requires an annotator runner/key, a game tree and
`gosStopped` before allowing a new run; an active run must keep Stop enabled.

However, `ApplyFeature` sets every bound control's Enabled property directly to
`GameSupports(feature)`. The final constructor `UpdateContextFeatures` calls it
after the initial display refresh. Both game profiles support Auto Play, so this
last feature refresh overwrites the correctly disabled startup button. The same
class of overwrite is possible during a game-profile switch.

This concerns an enabled button, not an Auto Play session starting spontaneously.
The existing StartAutoPlay guard still protects the operation itself.

## Minimal correction

At the end of `TMainForm.UpdateContextFeatures`, after all capability bindings
and menu captions have been refreshed, call the existing:

```pascal
  UpdateAutoPlayButtonState;
```

This restores the established runtime availability after the capability pass.
Do not change generic ApplyFeature semantics for every control, duplicate the
eligibility expression, alter game rules, attach annotations, launch engines or
change the Auto Play/Stop behavior. Do not add new legality/terminal predicates
as part of this startup QA correction.

## Verification

Extend the existing multi-game GUI check to inspect the real Auto Play button:
it must be disabled after construction, first Show and repeated Chess/Draughts
switching with no annotator. Test with isolated preferences on a hidden display.
Keep existing UCI/Hub Auto Play tests for enabling with an annotator, Stop during
an active run and disabling after closing/failing an annotator. Run all GUI checks
and both tournament suites, plus headless regression checks and compile the app.
Document the correction for both games in CHANGELOG with the implementation ID.

## Review gate

This correction touches shared main-form capability/runtime-state coordination.
The user explicitly waived prior review for this named correction, as quoted
above. The previous termination-reason waiver is not used for Auto Play work.

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

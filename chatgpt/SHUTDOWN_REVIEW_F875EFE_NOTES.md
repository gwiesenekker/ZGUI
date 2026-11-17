# Shutdown review: C14, F6, F7; F8 deferred

Date: 2026-11-17. Implementation commit: `e4d55b0`.

Authorization: the user requested “Could you review Claude's latest review of the
opening-pair shuffling changes, update the comment column, and address the findings
you agree with? Please update CHANGELOG.md, compile, test, and commit.” The user
then supplied Claude's long-match shutdown investigation in reply. The full review
files are now available: claude/review-e4991b9.md (shuffle: no new defects) and
claude/review-f875efe-shutdown.md (C14/F6/F7/F8). This implements the reviewed C14 and
F6 fixes and measures the original F7 case; it does not implement the pending
save-batching proposal. Existing uncommitted dialog-caption changes remain intact
and outside this commit.

## Assessment and reuse

- C14: agree. Main form Stop followed by terminal destruction repeats WaitFor.
  FPC 3.2.2 Unix TThread.WaitFor calls WaitForThreadTerminate every time and records
  FThreadReaped; its destructor explicitly avoids joining twice. Set FStarted false
  after a successful Stop wait. Keep the main-form stop ordering. Exercise Stop
  twice explicitly in the helper and again in its destructor, plus process loops.
- F6: agree. StopEngines exits processes but retains adapters until the orchestrator
  destructor. Release adapters in the runner's existing cleanup after StopEngines,
  detach runtime callbacks first, and use the existing Engine setter to free each
  side. A finally ensures the second side is attempted even if the first fails.
  Completion notification remains after cleanup. Keep the orchestrator, final
  snapshots, board/history, score/PV and log available for finished-game history.
  Normal, cancelled, early-start and error paths still use the same cleanup.
- F7: address the retained-history case at its root through F6. Worker destruction
  now happens on existing runner threads, not serially on the GUI thread when
  finished games leave history. Do not add another global two-pass worker API
  without evidence of a remaining problem after this fix. Live-engine protocol
  stop deadlines remain unchanged.
- F8: valid duplicate-save risk on individual history removal, but not the measured
  normal close path: tournament close unlinks ownership before StopAllGames.
  Supersedes the earlier diagnosis in TOURNAMENT_SHUTDOWN_SAVE_BATCHING_PROPOSAL.md;
  that proposal stays pending, with no implementation or broad dirty-save changes.
- C11 and U26/full review remain open. No native Windows validation is claimed.
- The shuffle review has no new implementation findings. Its wording that a cluster
  can “no longer” drive an early decision is too absolute: shuffling reduces
  systematic ordering bias, not sampling variance or curated-ballot dependence.
  The implementation/manual already make the more limited claim.

## Verification

The new runner_engine_release_check uses adapters owning actual shared worker
threads with idle callbacks. It retains 160 finished runners per game type and
asserts zero live adapters/workers, no residual polling, and preserved final
state/result/reason/PV/score. 2,242 checks passed; freeing each 160-game retained
history took 2 ms in the focused run. The test fails against the pre-fix runner
on the first retained-worker assertion. No hard timing/CPU thresholds in this
unit regression.

Passed: GTK2 build, full regression (including 2,242 new lifetime checks and 60
CLI transport checks), lifecycle, DXP loopback peer, both tournament checks, and
all 27 GUI suites including multi_game_gui_check. Earlier caption-work layout
failures did not recur in this current run. Native Windows QA remains outstanding.

Real Stockfish reproduction on a hidden display used temporary copies of the app,
engine and Claude's ballot80.fen. All 160 games completed. Threads: 7 before,
6 afterward. Two-second idle CPU samples: 0.5% of a core before and after. GUI
close including confirmations took 0.53 s; 0.053 s after the last Discard. Exit
code 0, no access-violation/ExceptionOccurred text. This is a measured comparison,
not a portable timing guarantee. The first harness attempt reached 73 games at
its 200-second limit; reran the full match with a 650-second allowance.

Reproduction script: chatgpt/SHUTDOWN_LONG_MATCH_PROBE.py; it takes the built app
path and optionally a Stockfish binary path, and only writes temporary copies.
Run through tests/run_hidden_gui.py. Logs: /tmp/zgui-shutdown-review-{gui,
regression,tourney,lifecycle,dxp,measure2,build}.log.

The separate choice-dialog changes in uGuiDialogs.pas/uMainForm.pas and their
changelog entry remain uncommitted. The user-owned Claude outputs directory is
untouched. No broad save batching, ordinary persistence changes, or global worker
shutdown API is included.

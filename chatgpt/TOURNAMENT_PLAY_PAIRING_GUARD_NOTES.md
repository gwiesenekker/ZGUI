# Tournament Play requires pairings — 2026-11-01

The user reported: “you can click Play without a pairing. Play should only be
enabled after pairing.” For the named pairing-required Play guard for chess and
draughts, the user chose **“Apply now; waive prior review”** on 2026-11-01.
Claude reviews the resulting commit afterwards.

Reuse TournamentPairingGridIsEmpty in the existing UpdateButtons condition and
StartStopClick guard. Keep existing running/shutdown and settings-change checks.
Do not change pairing generation, scheduler eligibility, clocks or result policy.
Creating/loading pairings enables Play; clearing/loading an empty schedule or
switching to a fresh game disables it. A direct/programmatic click on an empty
schedule returns before validation, automatic persistence or scheduling starts.

The existing tab test now checks both games' fresh state, direct callback guard,
create/load transitions, and clearing/reloading an empty schedule. Correct its
old expectation that idle Play was enabled without pairings. The focused suite
passes 201 checks. Run the application build, all 19 GUI suites and both tournament
suites using an isolated source archive and hidden displays; record final results
in CHANGELOG.md. Existing user engine work and untracked files remain untouched.

## Related QA: stale game name in a tournament tab

The user also reported that a second tournament still showed its draughts game
name after switching to chess. This corrects the previously authorised in-place
switching work: “Implement in-place switching; waive prior review” (2026-11-01),
documented in TABBED_TOURNAMENTS_IMPLEMENTATION.md. The reset changed FVariant but
did not notify the existing title listener because the tournament name itself
stayed unchanged. Emit the existing OnTitleChanged callback after the completed
reset. The host's existing formatter updates names, duplicate-name IDs and game
suffixes; no new title infrastructure or dialog recreation.

Add assertions for both switch directions, the second tab, and preserving the
first tab's caption. The new both-direction assertion fails before the callback
and the focused suite passes 203 checks afterwards, retaining native handles.

Final verification: application compilation, all 19 GUI suites and both tournament
suites pass. The final tab suite passes 380 checks with zero reported leaks.
Staged source matches the isolated test snapshot. Native Windows QA remains
pending; no user engine directories or unrelated working files were changed.

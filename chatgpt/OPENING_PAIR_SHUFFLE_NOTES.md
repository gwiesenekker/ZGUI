# Shuffle opening pairs

2026-11-17 authorization: user answered **“Implement now; waive prior review”**
for this named scope: opt-in “Shuffle opening pairs” checkbox and CLI option for
chess and draughts; shuffle before pairing, retain reversed-colour pairs, save
the actual order, and never reshuffle on load or SPRT replay. The user also asked
“Shoiuld we add shuffle to the CLI?”; include `shuffle_opening_pairs=true|false`.

## Reuse and schedule

Add Fisher–Yates entry shuffling to the existing LCL-free ballot unit. It uses
the application's existing RNG (already seeded at main-form creation); do not
reseed or introduce another random generator. CreatePairing copies the current
ballot, optionally shuffles that copy, and passes it to the unchanged
BuildBallotPairingRound. Only after accepting the existing new-storage step does
it install the copy as the scheduled list. The generator still creates adjacent
reversed-colour rows for every engine matchup and opening. Duplicate FEN entries
remain distinct scheduled openings. A permutation may legitimately be unchanged.

Reuse the measured pairing row for an unchecked checkbox; lock it after pairing,
while running and in read-only state. Include the setting in the existing
settings signature. Clear ballot and game-context reset clear the checkbox.
Explicitly creating another pairing may produce a fresh permutation; read-only
operations, loading, starting/resuming and game rescheduling never call shuffle.

The CLI accepts a strict true/false argument (default false), rejects true with
no ballot, fills TTournamentMatchSettings, and uses ConfigureNewTournament plus
the existing CreatePairing. No parallel CLI scheduler or pairing path.

## Persistence

Existing opening_ballot.positions stores the actual scheduled order, and existing
per-game records store the corresponding FEN/round number. Add an optional boolean
opening_ballot.shuffle_opening_pairs to restore the checkbox. Missing means false;
wrong types are rejected before replacing the current event. No version bump:
older readers already run the explicit scheduled rows and preserve positions,
so ignoring this preference cannot change saved execution. No seed needed for
replay; the explicit permutation is authoritative. The source ballot is untouched.

## Verification

Unit fixtures cover empty/single-entry lists, duplicate frequency, a fixed-seed
permutation, and three-engine colour-reversed groups. Both-game GUI fixtures cover
opt-in/default and locking, shuffled setup FENs, saving the actual order, removing
the source file, identical complete SPRT snapshots after load and repeated save/
load, legacy missing metadata, malformed metadata, game replay, and reset paths.
The interactive CLI fixtures enable shuffling for both games and check validation
and the shared GUI setting. The normal ballot fixtures still check unchanged file
order.

Passed: GTK2 application build; full regression; both tournament checks; all 27
GUI suites including multi_game_gui_check. Focused counts: 224 ballot unit checks
(225 with the real ballot2.fen: 79 entries, 158 games), 248 ballot GUI assertions,
and 263 interactive CLI assertions. Full layout suite: 11,258 checks, no failures;
inspected the tournament-only normal/enlarged-font captures with the new checkbox.
Tests used hidden displays only. Native Windows QA remains outstanding.

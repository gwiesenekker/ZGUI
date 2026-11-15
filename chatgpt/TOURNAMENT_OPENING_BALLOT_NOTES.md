# Opening ballot tournaments — 2026-11-15

## Authorisation

The user requested an opening ballot file in the tournament window to play GWD
against Kingsrow from every position in ballot2.fen, twice with colours reversed.
For this shared tournament extension the user explicitly chose:

> Implement now; waive prior review

The user supplied `/tmp2/gwies/gwd8/ballot2.fen` and asked whether the same idea
applies to chess. The approved implementation supports both games. Claude can
review the resulting commit afterwards. The source ballot and local engine
installations/registrations are not modified or distributed.

## Implementation

- Add optional Ballot file / Clear ballot controls in the existing setup area.
  Validate one complete FEN per line through TGameVariant/TGamePosition, normalize
  with ToFEN, accept blank/comment lines and UTF-8 BOM, preserve order/duplicates,
  and install only a fully validated set. Invalid positions identify source lines.
- A ballot selects double round-robin and disables the single starting-FEN field
  and pairing-type selector. Its first FEN is displayed. Change/clear a ballot
  only before pairings exist; use existing Clear pairing first. Variant reset
  clears the ballot in place with the other game-specific settings.
- Reuse GenerateRoundRobinPairings for the base list of engine pairs. For each
  ballot entry, expand each pair into two consecutive ordinary tournament rows
  with colours reversed and identical starting FEN. Round is the ballot-entry
  number. With two engines and the supplied 79-position file this is 158 games.
- Store each game's FEN in the existing TTournamentGameRecord, including its
  current JSON and attempt history. Rescheduling retains it. GameSetupForRow
  passes it to the unchanged scheduler/start-game callback; fallback publication
  uses it in existing PGN/PDN renderers. No new game runner, clock, scheduling,
  engine-process, reservation, result or game-tree implementation is added.
- Ballot snapshots use storage version 4 with explicit variant/notation/ponder
  metadata, the validated opening list and each row's FEN. Validate structure,
  entry index/FEN correspondence and positions before replacing loaded state.
  Source filename is display metadata, not a dependency on resume. Older ZGUI
  readers reject version 4 instead of silently playing all games from one FEN.
  Ordinary non-ballot save formats remain unchanged.
- Retain normal engine reservation, concurrency, referee result and replay paths.
  Selecting multiple engine pairs expands every pair for every opening. Ballots
  do not introduce a Swiss pairing policy.

## Validation

Headless checks cover both games, side to move, chess halfmove/fullmove counters,
blank/comment/BOM handling, atomic rejection, duplicate frequency, multi-engine
pair expansion, saved record/replay FEN and the supplied external ballot.
GUI checks exercise the chooser, row count/colours, existing scheduler setup
handoff (a probe host deliberately declines starts without launching engines),
referee results and PGN/PDN FENs, snapshots, replay, missing source files, rejection
of invalid saved positions, clear/reset guards and both game variants.

All generated engine registrations and game files belong to isolated test output
folders. Full both-game regression, GUI (including multi_game_gui_check),
tournament, application build and manual results are recorded in CHANGELOG.md.
GUI execution uses hidden displays. Native Windows visual testing remains
outstanding. Real GWD/Kingsrow games are left for the user to start from the new
controls; the actual supplied ballot is read-only during validation.

The actual supplied ballot also passes the optional GUI check: 79 positions and
158 persisted rows, with every row's FEN checked through GameSetupForRow. The
combined focused GUI run passes 255 assertions without reported leaks. Full
GUI suite: 21 passed, 0 failed; layout: 10,618 checks; tournament tabs: 392.

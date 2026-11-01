# ZGUI agent rules

ZGUI runs chess and draughts side by side in one program, built on the GWDGUI baseline.
Both games are first-class.

## Reuse

Preserve the existing GUI and shared infrastructure. Do not reimplement generic
functionality:
- playing games, clocks, tournaments and databases;
- game trees, notation traversal and analysis coordination;
- engine process management.

Game-specific work (rules, notation and file adapters, engine protocols) goes through
the existing interfaces: `TGamePosition`/`TGameVariant`/`TGameRules`,
`TGameBoardControl`, `TGameEngine`, `TGameFileReader`, the setup adapters and the GUI
profiles. Engines belong to a game by protocol: UCI is chess; Hub and DXP are
draughts.

## Review gate

Before implementing a necessary change to generic (shared) functionality, ask the
user which route to take:
1. Apply the named change now, with prior Claude review explicitly waived; or
2. Have Claude review it first. In that case, write a proposal in `chatgpt/` and
   proceed only after approval.

Ask for this choice before writing a review proposal; do not create one by default.
If a shared change was already made without the required approval or waiver,
revert only that change to the previous commit, preserving unrelated user work.
Do not ask again for work already covered by an explicit approval or named waiver.

**Exception: user authorisation.** The user may explicitly authorise a named piece of
work to be implemented without the prior review, for example "implement the
multi-game proposal without requesting approval".
- Record the authorisation, in the user's words, with its date and scope, in the work
  notes (`chatgpt/`) and the changelog entry.
- It covers only that named scope. Shared changes outside it still need the review
  gate.
- Claude reviews the resulting commits afterwards, and findings are fixed as usual.

## Both games

Any change to shared code must keep both games working. Run the chess and the draughts
checks for it, including `tests/run_gui_checks.sh` (which includes
`multi_game_gui_check`). A visible behaviour change for the other game must be stated
in the changelog.

## Housekeeping

- Maintain `CHANGELOG.md`, with the commit ID of each entry.
- Explicitly requested application branding is permitted; it must not change
  behaviour.
- Never modify `/tmp2/gwies/GWDGUI`.
- Leave the user's untracked files (for example `Test.pgn`) and the local engine
  directories (`engine*/`) untouched.

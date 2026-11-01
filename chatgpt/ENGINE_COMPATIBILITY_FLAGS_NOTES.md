# Engine compatibility flags

## Authorisation — 2026-11-01

The user chose to finish the existing, uncommitted compatibility features before
publishing release 1.0:

> Lets first work on these features. If they are part of feature flags we should rename gui-gwd-dxp-pv to 'dxp-pv'

The user explicitly waived prior review:

> Waiver granted for these changes!

Scope: the existing JSON feature-flags parameter and checkbox editor,
`no-pondering`, `no-ponder-hit`, optional DXP stdout PV collection renamed to
`dxp-pv`, reuse of the Hub information parser and bounded stdout line framer,
documentation and checks. Claude can review the resulting commit afterwards.
Release packaging/publication remains separate.

## Implementation

- Seed `gui-feature-flags` as a JSON string containing an array, default `[]`.
  It is GUI metadata, excluded from engine options. Clicking its name or value
  in the existing grid opens checkboxes. Validate JSON on acceptance, preserve
  unknown flags, normalize/deduplicate names, and leave Cancel unchanged.
- Use `dxp-pv` as the public flag. Accept the earlier development spelling
  `gui-gwd-dxp-pv` when reading; checkbox acceptance writes the new spelling.
- UCI and Hub reuse their existing ponder lifecycle. `no-pondering` prevents
  speculative searches and takes precedence; UCI also sends runtime Ponder=false
  without overwriting the saved option. `no-ponder-hit` follows the existing
  stop/drain/restart path even on a predicted-move match.
- Share the existing Hub `info` parser with DXP. Merge partial PV/score/depth/time
  reports and retain existing score-perspective normalization. DXP actual moves
  and game-end metadata remain exclusively socket-driven. No DXP analysis mode
  or arbitrary third-party stdout parser is added.
- Parse optional DXP stdout while the existing worker waits on the socket, using
  a separate parser lock and the existing thread-safe search-info publication.
  Freeze the search root/history for score normalization, arm before game
  acceptance/opponent-move delivery, preserve early information across position
  setup, and retire collection when the move wait finishes. Log outside the
  parser lock, after publication, so existing live snapshots see fresh info.
- Extract the existing bounded stdout framer rather than duplicating it. Use
  the first LF for both LF/CRLF, including mixed chunks on Windows. Keep the
  64 KiB line limit and discard oversized tails through the next newline.
- Measure the checkbox dialog from the owner's font and existing GUI helpers.
  Additional long flag names can scroll horizontally.

## Validation

Focused checks cover legacy migration, invalid JSON, unknown flags, cancellation,
parameter-file round trips, grid interaction, large fonts, fragmented/mixed
line endings, oversized output recovery, partial Hub info and White-perspective
scores. Protocol peers cover both ponder overrides and their precedence for UCI
and Hub, and enabled/disabled DXP PV for both sides while rejecting stdout moves.

Full application, chess/draughts regression, GUI and tournament results are
recorded in CHANGELOG.md. GUI execution uses isolated hidden displays.
Native Windows QA and a Windows rebuild from the final release checkout remain
outstanding. DXP stdout and socket messages have no common search identifier;
an engine must emit its information for the current search. Arbitrarily delayed
old stdout cannot be correlated perfectly with a later socket move.

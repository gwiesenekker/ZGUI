# Tournament tabs and oldest-waiting-first allocation

2026-10-31

## Authority and scope

Implement the approved `TABBED_TOURNAMENTS_PROPOSAL.md` and the four conditions in
`claude/review-559f6aa.md`. The native Windows embedding prerequisite is cleared:
after the caption-check correction, the user reported **“No errors on Windows!”**.
The preceding failure remains recorded in the Windows checklist; it was not
counted as a pass.

Additional named shared scheduling authorisation, 2026-10-31:
**“Please implement oldest-waiting-first!”** This covers the waiting-order policy
across tournaments using the existing engine reservations and game launch path.
It does not authorise unrelated engine protocol, process or feature-flag work.

## Implementation

- One host embeds existing TTournamentDialog instances in named tabs. The main
  form remains their Component Owner and existing TournamentOwner routing stays
  authoritative. No new pairing, game, clock, standings or file model.
- New creates a tab. Tournament opens the last-used matching-game tab. The Game
  choice replaces incompatible settings inside the same page, with Save / Discard /
  Cancel protection, a fresh tournament identity and target-game defaults.
- Each tab retains independent IDs, JSON/publication paths, timers and results.
  Open selects an existing matching file/identity; conflicting JSON/publication
  ownership is rejected before the existing loader/autosave writes. Loading
  another file does not replace a live same-game tournament.
- Existing settings signatures protect edited empty drafts as well as pairings.
  Rename updates labels; duplicate names display a stable tab identifier.
- Tab Close stops that tournament, warns, and offers Save / Discard / Cancel with
  Cancel as default. All-window/application Close gathers every decision and save
  destination before stopping anything. Save captures final state before removal;
  a final save error leaves stopped tabs open. Discard retains existing files.
  There is no automatic startup recovery enumeration/resume offer.
- Close-stopped rows persist `*` and `Stopped: tournament closed`; the existing
  retry guards permit those rows to resume while preserving completed results.
- Waiting rows identify busy engines and their owning tournament. Shared existing
  reservations still include ordinary games/annotators and DXP endpoint aliases.

## Waiting-order policy

The queue grants scheduling precedence, not live engine reservations. It is owned
by the main form and used on the GUI thread. Existing game start/reservation
checks still acquire the complete engine pair together; nothing partially holds
an engine while waiting for the second.

A runnable tournament with a free concurrency slot enters a turn. All eligible
pairings in that turn use its monotonically ordered ticket. Timer refreshes retain
age. A candidate cannot bypass an older conflicting turn, including when that
turn is waiting for its other engine. Disjoint pairs remain startable. This
conservative precedence prevents a stream of younger requests from starving a
pair that requires two engines.

One successful start ends the turn. The next game rejoins at the back after the
existing launch stagger, so a large tournament cannot put its entire schedule
ahead of tournaments already waiting. A stopped/closed/invalid or full tournament
leaves the queue; obsolete candidates are removed on refresh. The queue is not
persisted: loading does not launch games or create waiting turns until Play.
Ordinary games/annotators retain the existing reservation policy; this is a fair
queue between tournaments, not a new scheduler for all application activities.

## Validation

- The focused checked GTK suite passes 132 checks with zero unfreed blocks:
  four concurrent tabs (two of each game), shared registration waiting/completion,
  main document preservation, close cancellation and final capture, completed-row
  preservation on resume, file/identity conflicts, same-page game switching,
  edited drafts, save failure retaining recoverable state, measured host font
  sizing, tab X/child Close, and all-tab application Close protection.
- Real fake-protocol peers exercise three competing double-round-robin tournaments
  per game. Their timer callbacks are deliberately checked newest-first; launch
  owners must still be 1, 2, 3, 1, 2, 3. Both games pass.
- Fourteen range/overflow/heap-checked queue assertions cover stable age, younger
  rejoining, disjoint engines, stop/removal, invalidated candidates, endpoint
  aliases and precedence chains.
- Application compilation, full headless regressions (including source/build
  identity/manual audits), all 19 GUI suites and both existing tournament suites
  pass. Checked executables report zero unfreed blocks.
- Native Windows embedding spike passed as reported by the user. The completed
  production tab host/fair queue has been executed on Linux GTK2; native Windows
  production QA remains outstanding.

Unrelated dirty engine feature-flag work, AGENTS.md, engine directories and user
Windows test binaries are excluded from the implementation commit and release.
Repository garbage collection is a separate housekeeping action, pending explicit
user authorisation after automatic approval review rejected an initial request.

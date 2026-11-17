# Live paired GSPRT view

Implementation commit: `720eddf`.

Authorization: 2026-11-17. The user answered **“Implement now; waive prior review”**
for independent candidate/baseline selectors, a collapsible counts/graph pane,
one paired-SPRT calculator shared by GUI and query_tournament, saved settings and
exploratory/preconfigured labels, for chess and draughts, with no automatic stopping.
The user then confirmed: “Please proceed with the live SPRT view using GSPRT.
Please update CHANGELOG.md, compile, test, and commit.”

## Implementation

- uSprt is an LCL-free constrained multinomial logistic-Elo GSPRT calculator.
  Empty categories are regularized with 0.001 counts; empty evidence gives LLR=0.
  Solve the likelihood multiplier independently by monotone bisection. Defaults:
  H0=0, H1=5 logistic Elo, alpha=beta=.05. Model paired-logistic-v1 explicitly
  distinguishes this from normalized Elo. Nominal error rates are asymptotic;
  curated fixed ballots and post-hoc parameter selection need caution.
- uTournamentPairResults collects selected head-to-head rows from the existing
  schedule. Saved opening numbers define membership; FEN and reversed colours
  validate it. Repeated FENs remain separate. Reuse this collector for pairs=true
  and GSPRT rather than adding another scheduler or result-normalization path.
- Consume only the contiguous completed prefix in scheduled order; replay and
  freeze at the first crossing. Report all completed pairs separately. Referee
  changes/replayed attempts mark amended evidence; changed designs after play
  are exploratory. Neither GUI nor query stops games or edits their records.
- uSprtPanel is a presentation-only composite below the existing games table,
  with independent selectors and a splitter. Existing engine checkboxes retain
  their standings role. Its internal measured layout owns its scrolling; a small
  TGuiCompositePanel boundary in uGuiLayout prevents the form's recursive fitter
  fighting native/composite child sizing. Native combo heights remain LCL-owned.
- Optional versioned sprt_view metadata preserves settings and provenance inside
  existing tournament documents without changing root format versions. Missing
  metadata opens as exploratory; malformed metadata is rejected before replacing
  the current event. Older binaries may drop view settings on resave.
- query_tournament sprt=true returns this same report and current GUI design;
  default and sprt=false shapes stay unchanged. Candidate perspective is explicit
  and independent of ordinary engine1 aggregates. CLI IDs retain the existing
  two-engine CLI-created-match scope; GUI comparisons support multi-engine events.
  Swiss and single-leg/incomplete schedules show unavailable with a reason.

## Statistical references

References and numerical comparison, 2026-11-17:
- https://official-stockfish.github.io/docs/fishtest-wiki/Fishtest-Mathematics.html
- https://raw.githubusercontent.com/official-stockfish/fishtest/master/server/fishtest/stats/LLRcalc.py
- https://www.cantate.be/Fishtest/support_MLE_multinomial.pdf

No Fishtest code is vendored or required at runtime. Independent equations are
cross-checked against six logistic likelihood fixtures generated from the official
Python reference, including sparse, draw-only, asymmetric and mixed counts.

## Validation

GTK2 build, all 25 GUI suites, full regression and both tournament suites pass.
29 numerical/collector assertions; 84 dedicated live-pane GUI assertions; 255
interactive CLI GUI assertions; 107 application/pipe assertions; 301 multi-game
assertions. Inspect hidden-display screenshots at fonts 10/16 for both games;
normal counts fit, enlarged content scrolls when the games viewport needs space.
New coverage includes mathematical reference values, both
boundary crossings, out-of-order pair completion, repeated FENs, multi-engine
selection, candidate inversion, settings changes, result amendments, save/reload,
invalid metadata, font/size changes, unchanged files and real pipe responses.
Native Windows execution remains outstanding; no native Windows result is claimed.

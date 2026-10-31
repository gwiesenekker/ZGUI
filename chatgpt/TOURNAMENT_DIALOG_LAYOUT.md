# Tournament dialog sizing — 2026-10-31

User authorisation: “QA: the starting field FEN width is too small in the Tournament setup dialog box. Also, could you review the layout of that box while you are at it?” This names GUI layout work and continues the prior authorisation for automatic GUI sizing without approval. Scope is tournament dialog geometry only, for chess and draughts; Claude may review the resulting commit afterwards.

Move the existing tournament-name/FEN label and edit controls to full-width rows. Keep the existing clock, pairing and action controls below in wrapping groups. Measure the FEN plus margin using its font and a representative chess FEN; refresh after font/DPI and FEN changes. Preserve all existing event handling, tournament settings, storage and game orchestration.

Extend the existing layout suite to check full FEN visibility at different fonts, window sizes, DPI and after text changes, for both games. Validate against a source snapshot excluding unfinished feature flags. Native Windows interaction is not available here.

Validation passed: application compilation, all seventeen GUI suites (9,148 layout checks, zero failures), and both tournament suites (draughts preservation OK; 101 chess tournament checks). Inspected a capture of the initial 980×680 dialog: complete starting FEN, aligned clock labels, and pairing/actions beside the clock group. Larger-font and DPI cases remain covered by the layout suite. No changes to tournament scheduling, storage or game behavior.

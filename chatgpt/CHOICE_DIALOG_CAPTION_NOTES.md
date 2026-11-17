# Choice-dialog caption fix

Date: 2026-11-17.
Implementation commit: `3875399`.
User authorization: “Apply now; waive prior Claude review”.
Scope: default the shared choice dialog confirmation caption to OK, with the
move-selection caller explicitly requesting Play move. Both database creation
and ambiguous file opening inherit OK. No selection behaviour changes.
Validation results are recorded in CHANGELOG.md.


2026-11-17 follow-up authorization: “Could you commit the dialog-caption fix as
well? Please update CHANGELOG.md, compile, and test.”

Fresh GTK2 build passed. Existing main_form_boundaries_check (draughts capture
choice), chess_board_check (promotion chooser), and multi_game_gui_check passed
on the isolated hidden display. These same edits were also present for the
successful full 27-suite GUI run, regression and both tournament checks during
the shutdown review. No new application changes were needed for this commit.
Native Windows QA remains outstanding.

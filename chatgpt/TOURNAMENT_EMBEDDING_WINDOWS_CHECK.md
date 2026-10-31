# Tournament embedding spike — Windows check

2026-10-31. This is the first step required by condition 1 of
`claude/review-559f6aa.md`, before production tournament-tab integration.
The user selected “I will run the Windows check”; no prerequisite was waived.

## Run on Windows

1. Update the source files, including `tests/tournament_embedding_check.pas`
   and `.lpi`. Use the Lazarus installation that builds ZGUI.
2. Open `tests/tournament_embedding_check.lpi` in Lazarus and Build/Run it with
   no arguments. It should finish with “Tournament embedding checks passed
   (160 checks)” and no exception. If started in a terminal, retain its output.
3. Set Run parameters to `--interactive`, then run it again. Leave this
   diagnostic window open for the checks below.

The spike opens two existing TTournamentDialog forms inside tabs, with the
unchanged main form as their component owner. It launches no engines. Its main
form is hidden; test controls are in a footer on each embedded dialog.
The production tournament controls are unchanged. Do not use Play/Load/Save as
part of this keyboard/layout check. No real tournament data is needed.

## Interactive checklist

- Switch between Tournament1 (Chess) and Tournament2 (International draughts).
  Edit Tournament name on one page: the other page must keep its own value.
- Click the name edit and press Enter. The window title should show an Accept
  count increasing for that tab only. Press Escape: only that tab's Cancel
  count should increase. Neither key should close the host or another tab.
- Press Alt+K. The active tab's Accept count should increase. Switch tabs and
  repeat; the previous tab must not receive the action.
- Press Tab and Shift+Tab through fields/buttons and switch pages using the
  keyboard. Focus must stay accessible and follow the visible tab.
- Resize and maximize/restore. Fields, default/cancel test buttons and the
  tournament grids must remain accessible, without a child window spilling
  outside its tab. Repeat with Windows display scaling if convenient.
- Close the diagnostic window. It must exit cleanly. No engine/worker process
  should have been launched or left behind.

Please report whether the automatic run passed and any interactive failure,
including Windows display scaling and Lazarus version. A failure does not call
for working around it with a replacement tournament controller: the approved
fallback is a separately reviewed extraction of the existing body into TFrame.

## Linux evidence and required host glue

The isolated spike against unchanged application baseline 559f6aa passes 160
GTK2 checks with zero unfreed blocks. Log: `/tmp/zgui-tabs-embedding.log`.
The host must restore default/cancel roles on page changes (LCL has one of each
per top-level form) and propagate the active dialog's measured minimum size.
The test sends complete key-down and key-up routes, rather than just the
before-interface notification. Mnemonics use LCL's existing DialogChar routing.
None of that is a new tournament scheduler or game controller.

This machine has Wine but no native Windows host and no FPC Win64 units
(the compiler probe fails with “Can't find unit system”). Wine is not claimed
as satisfying the requested native Windows check.

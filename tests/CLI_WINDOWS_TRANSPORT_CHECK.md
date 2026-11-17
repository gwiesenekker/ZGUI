# Native Windows CLI transport check

Claude's review requested a native Windows transport check before integration.
On 2026-11-16 the user explicitly waived that prerequisite: “Waive prerequisite;
finish integration with Windows QA outstanding”. Integration proceeds; these
checks remain required Windows QA and are not claimed completed.

This is a test helper using the same GUI subsystem as ZGUI, not a second ZGUI
application executable.

Open `tests/cli_terminal_check.lpi` in Lazarus on Windows, compile it, then:

1. Run `cli_terminal_check.exe` from cmd and PowerShell. It should create a dedicated
   console. Type `ping` and a Unicode line. Expect one `OK {"echo":...}` line each.
   The launching shell must not compete with the dedicated console's keyboard.
2. In cmd: `echo ping | cli_terminal_check.exe > replies.txt`.
   Check replies.txt contains one UTF-8 OK JSON line and no prompt/banner.
3. Leave input idle and run `cli_terminal_check.exe --close-after-ms 500`.
   The helper must exit promptly without requiring Enter.
4. Use the Python transport test with the built helper (Python 3):
   `python tests/cli_terminal_transport_check.py path/to/cli_terminal_check.exe`.
   This checks pipes, Unicode, errors, EOF and cancellation with blocked I/O.

Please report OS/shell, Lazarus/FPC version, the Python result, and whether the
interactive dedicated console handles Ctrl+C without closing the helper. The
console close menu is disabled deliberately; use the helper timeout for shutdown
testing (and the normal GUI for eventual ZGUI shutdown). Linux
results do not validate Windows console allocation, Unicode or cancellation.

After rebuilding ZGUI, also launch the actual `zgui.exe --cli` from cmd and
PowerShell, create/query a match and watch it in the GUI. Check `BUSY` during an
open modal dialog, EOF leaving the GUI open, and GUI close with idle stdin or a
client that stops reading stdout. The helper checks transport behavior but cannot
replace this final application test.

C13 regression: in one actual `zgui.exe --cli` pipe session, create and query
at least five tournaments. Keep stderr separate. Every stdout line must be one
complete `OK ` / `ERROR ` JSON response, including after closing the GUI; no
Lazarus messages, partial lines or heap reports may appear there. Repeat with
stdout redirected to a regular file (preserving its write/append position).

Test `stop_tournament id=N` against both chess and draughts matches: expect an
immediate OK acknowledgement, then query until the engines drain. The tab and
results must remain, with the same Referee stopped tournament reason as GUI Stop.
Also test repeated Stop, a tournament waiting for busy engines, unknown/closed/
replaced IDs, BUSY during a modal dialog and another tournament continuing.

Test `query_tournament id=N pairs=true` for both games and a 79-position ballot:
expect one complete JSON response with all 79 pair entries in scheduled order,
including null scores for unfinished/unresolved games. Duplicate FEN entries
remain separate. Default and pairs=false queries omit the pairs array. Check
referee-result changes, rescheduling, and stopping while pair queries are active.

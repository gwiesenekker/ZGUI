# Native Windows CLI transport check

Claude's review `claude/review-cd4b00c-interactive-cli.md` requires a native Windows
transport check before connecting the interactive terminal to tournament actions.
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

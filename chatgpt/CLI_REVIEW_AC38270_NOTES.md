# Claude implementation review: ac38270

Date: 2026-11-16. Review: `claude/review-ac38270.md`.

## Authority and scope

The user requested: “Could you review Claude's latest review of the CLI implementation and address the findings you agree with? Please update the comment column, CHANGELOG.md, compile, test, and commit.” The follow-up “Could you comment on the latest review by Claude?” continues that work. The reviewed scope is C13, U28, T16 and T17, reusing the existing transport, GUI notices, tournament setup and execution. No new scheduler or tournament runner.

The existing waiver remains: “Waive prerequisite; finish integration with Windows QA outstanding”. Native Windows validation is outstanding, including the new output isolation; C11 is not claimed closed.

## Decisions

- C13: reserve a close-on-exec/noninheritable original stdout before LCL initialization. Send ordinary OS/RTL stdout to stderr through finalization; the terminal writes responses to the reserved handle. Desktop Windows launches retain their dedicated console path, with a process-lifetime noninheritable NUL diagnostic sink before console allocation and after retirement. Missing piped stdout cannot fall back to stderr. Ordinary non-CLI startup is unchanged.
- T16: reuse the shared-executable policy on fresh selected registrations before pairing. Existing pairings remain authoritative at StartTournament. A refused fresh command leaves no tab or files.
- T17: distinguish a never-found name from a removed session ID/registration key.
- U28: option 2, non-modal notices in the existing analysis log in CLI sessions. Both games retain the modal BUSY guard for ordinary dialogs; ordinary GUI sessions retain modal engine-problem notices.
- Do not broaden this change into parent-death signaling or the pending full historical review.

## Validation

- GTK2 application build passed.
- Focused interactive GUI check: 97 assertions, including both games, no-file preflight refusal and exact missing-name/removed-registration messages.
- Full GUI run: 24/24 suites passed, including multi_game_gui_check and the actual executable five-tournament pipe check (68 integrated assertions in that run). Protocol checks validate every response and require EOF with no trailing stdout bytes; deliberate buffered diagnostics are found on stderr.
- Queued UCI and Hub engine-failure notices reach the existing analysis log and subsequent list/query commands answer. Real ordinary modal dialogs still return BUSY.
- Full regression suite passed, including all 20 terminal transport checks, chess/draughts rules, notation, game trees and process checks.
- Both tournament suites, lifecycle and local TCP DXP suites passed. Hidden nested displays only; no desktop tests.
- Native Windows remains untested, as waived. The local Win64 compiler probe fails because target RTL units are absent; the optional Wine build.bat check also cannot run under the local syscall restrictions. No Windows build/runtime pass is claimed.
- Implementation commit: `3627fda`. A clean post-commit rebuild passed and installed the executable at `/tmp2/gwies/ZGUI/zgui`.

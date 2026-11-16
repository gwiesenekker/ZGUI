# Claude review follow-up: 00e3d3e

Date: 2026-11-16. Review: `claude/review-00e3d3e.md`.

## Request and scope

The user requested: “Could you review Claude's review-00e3d3e.md, update the comment column, and address the findings you agree with? Please update CHANGELOG.md, compile, test, and commit.”

This review verifies the C13, T16, T17 and U28 fixes in `3627fda`; it raises no new findings. There is no functional fix to implement. The normal GUI and shared tournament execution remain unchanged for both games.

## Assessment

- Accept Claude's verification of private protocol stdout on Linux, refusal before pairing publication, clear missing-engine names and non-modal CLI engine-failure notices. Preserve closed issues' comments and reviewer-owned Status/Evidence, following `claude/REVIEW_FORMAT.md`.
- Update C11's Coder comments in both tables. Native Windows remains unverified under the existing waiver: “Waive prerequisite; finish integration with Windows QA outstanding”. Linux results do not close C11. The checklist is `tests/CLI_WINDOWS_TRANSPORT_CHECK.md`; the manual now includes the Windows walkthrough (`f52cb29`) and command reference (`c8e938b`), which postdate this review's code scope.
- Do not change the optional form CreateNew paths: redirected diagnostic messages are harmless and the review raises no defect in them. The early ASCII flag detection still delegates real argument binding to the existing UTF-8 path.
- Claude's probe-script EOF hang needs no application change. Existing integration checks cover EOF, GUI responsiveness and normal shutdown with no trailing stdout bytes.
- Historical U26, D6, U21, T3 and D7 remain outside this review's scope and await the announced full review. Do not claim them fixed here.

## Validation

- Fresh GTK2 application build passed.
- Interactive CLI GUI check passed: 97 assertions covering both games, preflight refusal, query counts and modal protection.
- Integrated CLI application check passed: 65 assertions in this run, including live chess/draughts boards, queued engine notices, five tournaments in both the harness and actual executable, complete JSON stdout, EOF, and idle/blocked shutdown.
- CLI terminal transport check passed: all 20 assertions, including UTF-8, malformed input, cancellation, broken output, Ctrl+C isolation and background-terminal behavior.
- Manual document checks passed against the current manual.
- GUI checks used hidden nested displays only. No native Windows result is claimed.
- No application code changed, so the wider unchanged game/rules/tournament suites were not repeated. The earlier full 24/24 GUI and regression results remain recorded with 3627fda; the checks above are fresh runs for this follow-up.

## Commit

Review record: `e880527`.

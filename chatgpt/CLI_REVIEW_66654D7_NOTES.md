# CLI review follow-up — 66654d7

Date: 2026-11-16. Implementation: `2770b5a`. Review: `claude/review-66654d7.md`.

User authorisation: “Before we continue could you comment on Claude's review of
the latest commit, update the 'comment' column as discussed and address all
issues you agree with?” Scope: the four new findings and the optional missing
option-value message in that reviewed CLI change. Interactive --cli remains a
proposal; it is not implemented here.

- T13: agree. Distinguish permissions/read-only media from held locks. Read-only
  loading does not automatically save or publish. Guard Play, Save/Save As,
  pairing, ballot, referee result and replay actions; disable editing; label the
  tab/caption; close without save prompts. The same behavior applies to both games.
  Existing unreadable sidecars must not be guessed unlocked: refuse when ownership
  cannot be checked. Acquire a readable existing sidecar exclusively to distinguish
  an unlocked read-only sidecar from a live writer. Writable existing sidecars do
  not imply the containing archive directory is writable.
- T14: agree. Shared format detection reports a missing expanded tournament path.
- U27: agree. Use the existing resizable, scrollable text dialog for help, preserving
  blank lines and one OK button. Add a test-only on-show hook to inspect the actual
  queued startup dialog rather than substituting a fake help result.
- C10: agree. Linux open uses O_CLOEXEC atomically, including the permission-probe
  descriptor. Other Unix retains fcntl, now checking failure. Windows handles stay
  non-inheritable. Existing child-process lock-release checks remain in the suite.
- Optional parser note: report “Expected a value for --file.” for a pending option,
  retaining duplicate/unknown checks and required-argument validation.
- Optional holder-name diagnostics are deferred: metadata is not authoritative,
  and the current refusal does not misidentify a live owner.
- U26 and the older D6/U21/T3/D7 group are not claimed resolved. Claude explicitly
  deferred the full review of their commit range; font-dependent layout failures
  need the stated Inter-font/display reproduction before further shared layout
  changes. The existing hidden-display suites are still required for these fixes.

Only open-issue Coder comments cells in the latest review are updated. Reviewer
Status/Evidence and closed rows are preserved. The comments and changelog identify implementation `2770b5a` and validation results.

Validation: application build, full regression suite, both tournament suites and
all 22 GUI suites passed. The focused CLI check passed 103 assertions (both games
including real mode-555 archive permission tests and the actual help dialog);
parser check: 56 assertions. Layout: 10,618; tournament tabs: 392. All GUI execution
used isolated displays. Native Windows QA remains outstanding; no Windows binary
was rebuilt. Review comments remain in the existing local `claude/` directory.

# Scan DXP launch test: listener startup race

2026-10-30. Status: implementing the specifically authorised listener-order fix,
separately from the automatic GUI resizing commit.

User authorisation on 2026-10-30: “Yes, correct, we should first make sure the
listener is running. Perhaps we can try a connect before launching the engine or
will the listener already error out?” Scope: the engine editor's DXP listen-role
startup, readiness/failure reporting and cleanup. AGENTS.md's named authorisation
exception applies; Claude can review the resulting commit afterwards.

User report: Scan does not connect when launched by the editor, but a terminal
launch while the editor's Launch engine test is active connects successfully.

Confirmed code ordering in TEngineEditForm.LaunchClick:
1. Start the process with its arguments and executable directory.
2. ReadForMs(250).
3. Create TDxpTestConnectionThread, which binds the listener for role listen.

Scan in DXP client mode can attempt its connection and exit before step 3. This
matches the observation. Current engine7 registration has DXP args dxp, loopback
host and role listen; the user has configured matching INI macros. User engine
files have been inspected only, not modified or launched by this investigation.

Fix the editor's DXP listen test by starting the existing socket-test thread and
waiting for an explicit successful-listen/error readiness signal BEFORE launching
its client engine. Do not substitute a fixed delay. Preserve the connect-role
order (engine server first, GUI connection afterwards), existing process manager,
INI macro writing, cancellation and log delivery. On bind failure, report it and
avoid launching the process. On process launch failure, stop the socket test.
The match adapter already starts its accept thread before launching; preserve it.

Acceptance: fake fast client connects on its first and only attempt; bind failure
launches no process; connect role still works; cancel and repeated launches clean
up the listener. Then verify Scan from an isolated engine copy (never overwrite
user engine directories), run DXP and GUI checks, update changelog and commit.

The user reports that Scan dxp-server=true does not work. Do not recommend that
workaround. Keep Scan as a client and fix the listener-before-process ordering.

A dummy TCP connection would consume the test listener's single accepted client
and stop its accept loop. Instead a readiness event is signalled only after Listen
succeeds; the GUI services Synchronize logs while waiting without pumping UI input.

The self-contained regression uses a single-attempt immediate client, repeats the
launch, checks that bind failure launches no process, and verifies cancellation.
User engine files remain untouched.

Validation: self-contained client/server launch tests passed, including repeated
launch, early process exit, occupied-port rejection and cancellation. A copy of
engine7/scan_linux plus its required data/eval, isolated under /tmp with a generated
INI and random port, connects successfully from the editor in client mode. No
engine*/ files were changed. The fake-engine regression remains independent of
those local downloads. Final clean-snapshot application/DXP/full GUI checks follow.

Final validation passed on the independent source snapshot: application compile,
existing DXP checks and all fourteen GUI suites, including both games, 87 mixed-game
checks and 8,944 layout checks. The final DXP test has no dependency on local Scan
files. Native Windows interaction remains untested.

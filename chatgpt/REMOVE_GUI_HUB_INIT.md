# Remove configurable Hub initialization

2026-10-31. User authorisation: “Lets for now get rid of gui-hub-init”. This
supersedes the earlier request to show/rename the option. Scope: remove the
configuration/control and restore the mandatory Hub initialization sequence in
both game/annotator startup and the existing editor launch test. The named
exception in AGENTS.md applies; Claude can review the resulting commit afterwards.

Primary evidence: engine6/protocol.txt, initialization example at lines 28–55:
hub -> wait -> set-param commands -> init -> ready. The GUI must send init; it
is not an engine-advertised option and does not require a user setting. GWDGUI's
legacy configurable InitText/gui-hub-init mechanism is unnecessary for that fixed
handshake. The new implementation sends init directly after SendHubParams.

Remove the separate Hub initialization row. Keep the existing hidden memo only
for the unchanged UCI/definition paths. Hub definitions saved by the editor use
its standard init value for registry compatibility; Hub startup ignores the
legacy InitText script. Retired gui-hub-init keys are hidden/ignored and removed
from the protocol's parameter section on ordinary Save. Other keys/sections remain
intact. Do not proactively rewrite engine*/ files or the user's registry.

Tests use fake Hub processes: retired overrides containing quit do not suppress
initialization or terminate startup, the editor sends exactly one init before
quit, the old setting is absent from the UI and saved section, and unrelated GUI
settings/UCI commands survive. Existing wire fixtures verify the unchanged normal
Hub command stream. Run the full GUI/headless suites and application compilation
against an isolated snapshot excluding unfinished feature flags. No subagents.

Final validation passed on the independent source snapshot: application compile,
all seventeen GUI suites and the complete headless regression suite. The editor
wire trace and runtime fake-engine checks exercise legacy quit overrides; existing
Hub wire fixtures still pass. Native Windows interaction remains untested.

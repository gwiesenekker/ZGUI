# ZGUI port constraints

Start from the GWDGUI baseline and preserve its GUI and shared infrastructure.
Do not reimplement generic functionality: playing games, clocks, tournaments,
databases, game trees, notation traversal, analysis coordination or engine process
management. Implement chess rules, notation/file adapters and UCI through the
existing interfaces wherever possible.

If a necessary change touches generic functionality, revert that change to the
previous commit and present the proposed change for Claude to review before
proceeding. Explicitly requested application branding is permitted; it must not
change behaviour. Maintain CHANGELOG.md. Never modify /tmp2/gwies/GWDGUI.

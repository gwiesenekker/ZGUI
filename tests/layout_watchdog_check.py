#!/usr/bin/env python3
"""Verify both watchdog exits using deliberate test-only layout failures."""
import subprocess
import sys

for mode, expected in (("bounds", "5000 bounds changes"), ("timeout", "no progress before deadline")):
    result = subprocess.run([sys.argv[1], f"--watchdog-{mode}-test"],
                            capture_output=True, text=True, timeout=8)
    assert result.returncode == 3, (mode, result.returncode, result.stdout, result.stderr)
    assert "LAYOUT WATCHDOG" in result.stderr and expected in result.stderr, result.stderr
    assert f"phase=deliberate --watchdog-{mode}-test" in result.stderr, result.stderr
    if mode == "bounds":
        assert "TForm:WatchdogProbe" in result.stderr, result.stderr
    print(f"Layout watchdog {mode}: expected diagnostic and exit 3")

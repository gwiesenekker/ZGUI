#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" >/dev/null && pwd -P)"
OUT_DIR="${1:-${TMPDIR:-/tmp}/zgui-app-build}"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR" "$ROOT_DIR/zgui.lpi"
install -m 775 "$OUT_DIR/zgui" "$ROOT_DIR/.zgui-new-build"
mv -f "$ROOT_DIR/.zgui-new-build" "$ROOT_DIR/zgui"
echo "Built $ROOT_DIR/zgui"

#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." >/dev/null && pwd -P)"
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 input.pgn [database.db] [game limit; 0=all] [existing]" >&2
  exit 2
fi
OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zgui-db-benchmark.XXXXXX")"
trap 'rm -rf "$OUT_DIR"' EXIT
fpc -B -O2 -Fu"$ROOT_DIR" -FU"$OUT_DIR" -FE"$OUT_DIR" \
  "$ROOT_DIR/tests/chess_database_benchmark.pas" > "$OUT_DIR/build.log" 2>&1 || {
  cat "$OUT_DIR/build.log"; exit 1;
}
/usr/bin/time -v "$OUT_DIR/chess_database_benchmark" "$1" "${2:-$OUT_DIR/games.db}" "${3:-0}" "${4:-}"

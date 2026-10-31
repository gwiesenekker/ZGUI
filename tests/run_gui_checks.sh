#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." >/dev/null && pwd -P)"
OUT_DIR="${TMPDIR:-/tmp}/gwdgui-gui-checks"
mkdir -p "$OUT_DIR/config" "$OUT_DIR/units"

echo "==> standalone_preservation_check (GTK2, hidden main form)"
if ! python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR" \
  "$ROOT_DIR/tests/standalone_preservation_check.lpi" > "$OUT_DIR/build.log" 2>&1; then
  cat "$OUT_DIR/build.log"
  exit 1
fi
cd "$OUT_DIR"
"$OUT_DIR/standalone_preservation_check"

echo "==> main_form_boundaries_check (GTK2, interaction and analysis lifecycle)"
if ! python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR" \
  "$ROOT_DIR/tests/main_form_boundaries_check.lpi" > "$OUT_DIR/boundaries-build.log" 2>&1; then
  cat "$OUT_DIR/boundaries-build.log"
  exit 1
fi
"$OUT_DIR/main_form_boundaries_check"


echo "==> gui_delivery_check (GTK2, queue consumption and shutdown)"
if ! python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR" \
  "$ROOT_DIR/tests/gui_delivery_check.lpi" > "$OUT_DIR/delivery-build.log" 2>&1; then
  cat "$OUT_DIR/delivery-build.log"
  exit 1
fi
"$OUT_DIR/gui_delivery_check"


echo "==> help_menu_check (GTK2, shortcuts and application help)"
if ! python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR" \
  "$ROOT_DIR/tests/help_menu_check.lpi" > "$OUT_DIR/help-build.log" 2>&1; then
  cat "$OUT_DIR/help-build.log"
  exit 1
fi
"$OUT_DIR/help_menu_check"


echo "==> notation_preferences_check (GTK2, styles and SynEdit ranges)"
if ! python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR" \
  "$ROOT_DIR/tests/notation_preferences_check.lpi" > "$OUT_DIR/notation-preferences-build.log" 2>&1; then
  cat "$OUT_DIR/notation-preferences-build.log"
  exit 1
fi
"$OUT_DIR/notation_preferences_check"


echo "==> chess_board_check (GTK2, chess board/PV and preserved layout)"
if ! python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR" \
  "$ROOT_DIR/tests/chess_board_check.lpi" > "$OUT_DIR/chess-build.log" 2>&1; then
  cat "$OUT_DIR/chess-build.log"
  exit 1
fi
"$OUT_DIR/chess_board_check"


echo "==> uci_gui_check (GTK2, existing editor and annotator)"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR" \
  "$ROOT_DIR/tests/uci_gui_check.lpi" > "$OUT_DIR/uci-build.log" 2>&1
"$OUT_DIR/uci_gui_check"


echo "==> setup_preferences_check (GTK2, chess setup and score colours)"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR" \
  "$ROOT_DIR/tests/setup_preferences_check.lpi" > "$OUT_DIR/setup-preferences-build.log" 2>&1
"$OUT_DIR/setup_preferences_check"


echo "==> chess_database_gui_check (GTK2, shared database dialog and selection)"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR" \
  "$ROOT_DIR/tests/chess_database_gui_check.lpi" > "$OUT_DIR/chess-database-build.log" 2>&1
"$OUT_DIR/chess_database_gui_check"

echo "==> multi_game_gui_check (GTK2, concurrent chess/draughts contexts)"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR/multi" \
  "$ROOT_DIR/tests/multi_game_gui_check.lpi" > "$OUT_DIR/multi-build.log" 2>&1
"$OUT_DIR/multi/multi_game_gui_check"

echo "==> game_preferences_check (GTK2, per-game appearance and U22)"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR/game-prefs" \
  "$ROOT_DIR/tests/game_preferences_check.lpi" > "$OUT_DIR/game-prefs-build.log" 2>&1
"$OUT_DIR/game-prefs/game_preferences_check"

echo "==> engine_ini_viewport_check (GTK2, INI editor bounds for both games)"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR/ini-viewport" \
  "$ROOT_DIR/tests/engine_ini_viewport_check.lpi" > "$OUT_DIR/ini-viewport-build.log" 2>&1
"$OUT_DIR/ini-viewport/engine_ini_viewport_check"

echo "==> gui_layout_check (GTK2, font/window/DPI resizing for both games)"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR/layout" \
  "$ROOT_DIR/tests/gui_layout_check.lpi" > "$OUT_DIR/layout-build.log" 2>&1
timeout 60s "$OUT_DIR/layout/gui_layout_check"

echo "==> dxp_editor_launch_check (GTK2, listener before client process)"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR/dxp-launch" \
  "$ROOT_DIR/tests/dxp_editor_launch_check.lpi" > "$OUT_DIR/dxp-launch-build.log" 2>&1
timeout 30s "$OUT_DIR/dxp-launch/dxp_editor_launch_check"

echo "==> engine_parameter_scroll_check (GTK2, immediate wheel scrolling for both games)"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR/parameter-scroll" \
  "$ROOT_DIR/tests/engine_parameter_scroll_check.lpi" > "$OUT_DIR/parameter-scroll-build.log" 2>&1
timeout 15s "$OUT_DIR/parameter-scroll/engine_parameter_scroll_check"

echo "==> init_colour_gui_check (GTK2, Hub initialization and preferences previews)"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR/init-colour" \
  "$ROOT_DIR/tests/init_colour_gui_check.lpi" > "$OUT_DIR/init-colour-build.log" 2>&1
timeout 30s "$OUT_DIR/init-colour/init_colour_gui_check"

echo "==> main_readability_gui_check (GTK2, full FEN and ten notation lines)"
python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR/main-readability" \
  "$ROOT_DIR/tests/main_readability_gui_check.lpi" > "$OUT_DIR/main-readability-build.log" 2>&1
timeout 30s "$OUT_DIR/main-readability/main_readability_gui_check"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." >/dev/null && pwd -P)"
OUT_DIR="${TMPDIR:-/tmp}/gwdgui-gui-checks"
mkdir -p "$OUT_DIR/config" "$OUT_DIR/units"
FAILED=()
PASSED=0

run_check() {
  local title="$1" project="$2" subdir="$3" limit="$4"
  local output="$OUT_DIR$subdir" log="$OUT_DIR/$project-build.log"
  echo "==> $title"
  if ! python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$output" \
      "$ROOT_DIR/tests/$project.lpi" > "$log" 2>&1; then
    cat "$log"
    FAILED+=("$project (build)")
    return
  fi
  if (cd "$output" && timeout "$limit" "./$project"); then
    PASSED=$((PASSED + 1))
  else
    FAILED+=("$project (run)")
  fi
}

run_check "tree_delete_gui_check (GTK2, safe inclusive deletion in both games)" tree_delete_gui_check "/tree-delete" 60s

run_check "tournament_history_gui_check (GTK2, saved-game history selection, results and deduplication)" tournament_history_gui_check "/tournament-history" 60s

run_check "time_forfeit_gui_check (GTK2, timeout adjudication, shared reservations, CLI and saved policies)" time_forfeit_gui_check "/time-forfeit" 90s

run_check "sprt_gui_check (GTK2, paired GSPRT view, persistence and both games)" sprt_gui_check "/sprt" 90s

run_check "interactive_cli_gui_check (GTK2, shared match setup, queries and modal BUSY)" interactive_cli_gui_check "/interactive-cli" 90s

echo "==> cli_application_check (pipes through GUI dispatcher and responsive shutdown)"
if python3 "$ROOT_DIR/tests/build_lazarus_check.py" gtk2 "$OUT_DIR/cli-application" "$ROOT_DIR/zgui.lpi" > "$OUT_DIR/cli-application-build.log" 2>&1 &&
   python3 "$ROOT_DIR/tests/cli_application_check.py" "$OUT_DIR/interactive-cli/interactive_cli_gui_check" "$OUT_DIR/cli-application/zgui"; then
  PASSED=$((PASSED + 1))
else
  FAILED+=("cli_application_check (run)")
fi

echo "==> native_main_resize_check (real application shrink/grow and idle CPU for both games)"
if timeout 60s python3 "$ROOT_DIR/tests/native_main_resize_check.py" "$OUT_DIR/cli-application/zgui"; then
  PASSED=$((PASSED + 1))
else
  FAILED+=("native_main_resize_check (run)")
fi

run_check "startup_cli_gui_check (GTK2, live CLI tournaments and cross-process file leases)" startup_cli_gui_check "/startup-cli" 60s

run_check "standalone_preservation_check (GTK2, hidden main form)" standalone_preservation_check "" 60s
run_check "main_form_boundaries_check (GTK2, interaction and analysis lifecycle)" main_form_boundaries_check "" 60s
run_check "gui_delivery_check (GTK2, queue consumption and shutdown)" gui_delivery_check "" 60s
run_check "help_menu_check (GTK2, shortcuts and application help)" help_menu_check "" 60s
run_check "notation_preferences_check (GTK2, styles and SynEdit ranges)" notation_preferences_check "" 60s
run_check "chess_board_check (GTK2, chess board/PV and preserved layout)" chess_board_check "" 60s
run_check "uci_gui_check (GTK2, existing editor and annotator)" uci_gui_check "" 60s
run_check "setup_preferences_check (GTK2, chess setup and score colours)" setup_preferences_check "" 60s
run_check "chess_database_gui_check (GTK2, shared database dialog and selection)" chess_database_gui_check "" 60s
run_check "multi_game_gui_check (GTK2, concurrent chess/draughts contexts)" multi_game_gui_check "/multi" 60s
run_check "game_preferences_check (GTK2, per-game appearance and U22)" game_preferences_check "/game-prefs" 60s
run_check "engine_ini_viewport_check (GTK2, INI editor bounds for both games)" engine_ini_viewport_check "/ini-viewport" 60s
run_check "gui_layout_check (GTK2, font/window/DPI resizing for both games)" gui_layout_check "/layout" 60s
run_check "dxp_editor_launch_check (GTK2, listener before client process)" dxp_editor_launch_check "/dxp-launch" 30s
run_check "engine_parameter_scroll_check (GTK2, all-grid scrolling/hints and tournament Play viewport)" engine_parameter_scroll_check "/parameter-scroll" 45s
run_check "init_colour_gui_check (GTK2, Hub initialization and preferences previews)" init_colour_gui_check "/init-colour" 30s
run_check "main_readability_gui_check (GTK2, full FEN and ten notation lines)" main_readability_gui_check "/main-readability" 30s
run_check "engine_end_reason_gui_check (GTK2, engine reason snapshots and tournament persistence)" engine_end_reason_gui_check "/end-reason" 45s

run_check "engine_feature_flags_gui_check (GTK2, compatibility flags editor)" engine_feature_flags_gui_check "/feature-flags" 45s

run_check "tournament_ballot_gui_check (GTK2, ballot positions and colour-reversed game rows)" tournament_ballot_gui_check "/ballots" 60s

XDG_CONFIG_HOME="$OUT_DIR/tabs-recovery" run_check "tournament_tabs_check (GTK2, tab lifecycle and fair cross-tournament allocation)" tournament_tabs_check "/tournament-tabs" 100s

echo "==> layout_watchdog_check (bounded resize loop and stalled native dispatch)"
if python3 "$ROOT_DIR/tests/layout_watchdog_check.py" "$OUT_DIR/tournament-tabs/tournament_tabs_check"; then
  PASSED=$((PASSED + 1))
else
  FAILED+=("layout_watchdog_check (run)")
fi

echo "GUI suites passed: $PASSED; failed: ${#FAILED[@]}"
if ((${#FAILED[@]})); then
  printf 'FAILED: %s\n' "${FAILED[@]}"
  exit 1
fi

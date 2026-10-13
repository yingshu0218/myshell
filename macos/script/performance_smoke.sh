#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-/private/tmp/myshell-release/Build/Products/Release/MyShell.app}"
SAMPLE_SECONDS="${SAMPLE_SECONDS:-10}"
SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-1}"
STABILIZE_SECONDS="${STABILIZE_SECONDS:-3}"
TERMINAL_COUNTS="${TERMINAL_COUNTS:-0 1 4 12}"
OUTPUT_BYTES="${OUTPUT_BYTES:-33554432}"
TAB_SWITCH_MS="${TAB_SWITCH_MS:-100}"
SCENARIO_DELAY_MS="${SCENARIO_DELAY_MS:-1000}"
RETAIN_TERMINAL_VIEWS="${RETAIN_TERMINAL_VIEWS:-0}"
CONCURRENT_COUNTS="${CONCURRENT_COUNTS:-1 4 12}"
OUTPUT_PROFILE="${OUTPUT_PROFILE:-ascii}"
OUTPUT_LINES="${OUTPUT_LINES:-100000}"
RESIZE_INTERVAL_MS="${RESIZE_INTERVAL_MS:-100}"
RESIZE_CYCLES="${RESIZE_CYCLES:-100}"
RESIZE_START_DELAY_MS="${RESIZE_START_DELAY_MS:-3000}"
TUI_FRAMES="${TUI_FRAMES:-1000}"
APP_BINARY="$APP_PATH/Contents/MacOS/MyShell"
MODE="${1:-smoke}"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "error: Release app not found at $APP_PATH" >&2
  exit 2
fi

APP_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]]; then
    /bin/kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

now_seconds() {
  /usr/bin/perl -MTime::HiRes=time -e 'printf "%.6f\n", time'
}

wait_for_children() {
  local expected="$1"
  local deadline
  deadline="$(
    /usr/bin/awk -v start="$(now_seconds)" 'BEGIN { printf "%.6f", start + 10 }'
  )"

  while :; do
    local child_pids count
    child_pids="$(/usr/bin/pgrep -P "$APP_PID" 2>/dev/null || true)"
    count="$(
      printf '%s\n' "$child_pids" \
        | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }'
    )"
    if [[ "$count" -ge "$expected" ]]; then
      return
    fi
    if /usr/bin/awk -v now="$(now_seconds)" -v end="$deadline" \
      'BEGIN { exit !(now >= end) }'; then
      echo "error: expected $expected terminal child processes, found $count" >&2
      return 1
    fi
    /bin/sleep 0.02
  done
}

sample_processes() {
  local label="$1"
  local terminals="$2"
  local started_at="$3"
  local ready_at="$4"
  local sample_count
  sample_count="$(
    /usr/bin/awk -v duration="$SAMPLE_SECONDS" -v interval="$SAMPLE_INTERVAL" \
      'BEGIN { value = int(duration / interval); print (value > 0 ? value : 1) }'
  )"
  local cpu_total="0"
  local peak_rss=0
  local index

  for ((index = 0; index < sample_count; index++)); do
    if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
      echo "error: MyShell exited before sampling completed" >&2
      return 1
    fi

    local child_pids pid_list sample cpu rss
    child_pids="$(/usr/bin/pgrep -P "$APP_PID" 2>/dev/null || true)"
    child_pids="$(printf '%s\n' "$child_pids" | /usr/bin/paste -sd, -)"
    pid_list="$APP_PID"
    if [[ -n "$child_pids" ]]; then
      pid_list="$pid_list,$child_pids"
    fi
    sample="$(/bin/ps -p "$pid_list" -o %cpu=,rss=)"
    cpu="$(printf '%s\n' "$sample" | /usr/bin/awk '{ total += $1 } END { printf "%.3f", total }')"
    rss="$(printf '%s\n' "$sample" | /usr/bin/awk '{ total += $2 } END { print total + 0 }')"
    cpu_total="$(
      /usr/bin/awk -v total="$cpu_total" -v value="$cpu" \
        'BEGIN { printf "%.3f", total + value }'
    )"
    if [[ "$rss" -gt "$peak_rss" ]]; then
      peak_rss="$rss"
    fi
    /bin/sleep "$SAMPLE_INTERVAL"
  done

  local startup_ms average_cpu app_cpu app_rss final_child_count
  startup_ms="$(
    /usr/bin/awk -v start="$started_at" -v ready="$ready_at" \
      'BEGIN { printf "%.1f", (ready - start) * 1000 }'
  )"
  average_cpu="$(
    /usr/bin/awk -v total="$cpu_total" -v count="$sample_count" \
      'BEGIN { printf "%.3f", total / count }'
  )"
  app_cpu="$(/bin/ps -p "$APP_PID" -o %cpu= | /usr/bin/tr -d ' ')"
  app_rss="$(/bin/ps -p "$APP_PID" -o rss= | /usr/bin/tr -d ' ')"
  final_child_count="$(
    { /usr/bin/pgrep -P "$APP_PID" 2>/dev/null || true; } \
      | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }'
  )"

  printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$label" "$terminals" "$startup_ms" "$average_cpu" "$app_cpu" \
    "$app_rss" "$peak_rss" "$final_child_count"
}

run_sample() {
  local label="$1"
  local terminals="$2"
  local output_bytes="${3:-}"
  local tab_switch_ms="${4:-}"
  local stabilize_seconds="${5:-$STABILIZE_SECONDS}"
  local use_metal="${6:-0}"
  local output_all="${7:-0}"
  local exit_after_output="${8:-0}"
  local output_lines="${9:-}"
  local tui_frames="${10:-}"
  local started_at ready_at
  if [[ ! "$terminals" =~ ^[0-9]+$ ]]; then
    echo "error: terminal count must be an integer" >&2
    return 2
  fi
  if [[ "$terminals" -gt 12 ]]; then
    terminals=12
  fi
  started_at="$(now_seconds)"
  MYSHELL_PERFORMANCE_MODE=1 \
    ApplePersistenceIgnoreState=YES \
    NSQuitAlwaysKeepsWindows=NO \
    MYSHELL_PERFORMANCE_TERMINALS="$terminals" \
    MYSHELL_PERFORMANCE_OUTPUT_BYTES="$output_bytes" \
    MYSHELL_PERFORMANCE_OUTPUT_ALL="$output_all" \
    MYSHELL_PERFORMANCE_OUTPUT_PROFILE="$OUTPUT_PROFILE" \
    MYSHELL_PERFORMANCE_OUTPUT_LINES="$output_lines" \
    MYSHELL_PERFORMANCE_TUI_FRAMES="$tui_frames" \
    MYSHELL_PERFORMANCE_TAB_SWITCH_MS="$tab_switch_ms" \
    MYSHELL_PERFORMANCE_DELAY_MS="$SCENARIO_DELAY_MS" \
    MYSHELL_PERFORMANCE_EXIT_AFTER_OUTPUT="$exit_after_output" \
    MYSHELL_PERFORMANCE_RETAIN_TERMINAL_VIEWS="$RETAIN_TERMINAL_VIEWS" \
    MYSHELL_PERFORMANCE_RESIZE_INTERVAL_MS="${resize_interval_ms:-}" \
    MYSHELL_PERFORMANCE_RESIZE_CYCLES="$RESIZE_CYCLES" \
    MYSHELL_PERFORMANCE_RESIZE_START_DELAY_MS="$RESIZE_START_DELAY_MS" \
    MYSHELL_PERFORMANCE_METAL="$use_metal" \
    "$APP_BINARY" >/dev/null 2>&1 &
  APP_PID=$!
  wait_for_children "$terminals"
  ready_at="$(now_seconds)"
  /bin/sleep "$stabilize_seconds"
  sample_processes "$label" "$terminals" "$started_at" "$ready_at"
  /bin/kill "$APP_PID" >/dev/null 2>&1 || true
  wait "$APP_PID" >/dev/null 2>&1 || true
  APP_PID=""
}

echo "scenario,terminals,startup_to_children_ms,tree_average_cpu_percent,app_final_cpu_percent,app_rss_kib,process_tree_peak_rss_kib,final_child_processes"
case "$MODE" in
  smoke)
    run_sample "idle" 1
    ;;
  matrix)
    for count in $TERMINAL_COUNTS; do
      run_sample "idle" "$count"
    done
    ;;
  throughput)
    run_sample "output-${OUTPUT_BYTES}-bytes" 1 "$OUTPUT_BYTES" "" 0
    ;;
  throughput-metal)
    run_sample "output-metal-${OUTPUT_BYTES}-bytes" 1 "$OUTPUT_BYTES" "" 0 1
    ;;
  unicode-output)
    OUTPUT_PROFILE=unicode-ansi \
      run_sample "unicode-ansi-${OUTPUT_BYTES}-bytes" 1 "$OUTPUT_BYTES" "" 0
    ;;
  same-lines)
    OUTPUT_PROFILE=ascii \
      run_sample "ascii-${OUTPUT_LINES}-lines" 1 "" "" 0 0 0 0 "$OUTPUT_LINES"
    OUTPUT_PROFILE=unicode-ansi \
      run_sample "unicode-ansi-${OUTPUT_LINES}-lines" \
        1 "" "" 0 0 0 0 "$OUTPUT_LINES"
    ;;
  resize)
    resize_interval_ms="$RESIZE_INTERVAL_MS" \
      run_sample "resize-${RESIZE_INTERVAL_MS}-ms" \
        1 "" "" 0 0 0 0 10000
    ;;
  resize-metal)
    resize_interval_ms="$RESIZE_INTERVAL_MS" \
      run_sample "resize-metal-${RESIZE_INTERVAL_MS}-ms" \
        1 "" "" 0 1 0 0 10000
    ;;
  tui)
    run_sample "tui-${TUI_FRAMES}-frames" \
      1 "" "" 0 0 0 0 "" "$TUI_FRAMES"
    ;;
  tui-metal)
    run_sample "tui-metal-${TUI_FRAMES}-frames" \
      1 "" "" 0 1 0 0 "" "$TUI_FRAMES"
    ;;
  metal-idle)
    run_sample "idle-metal" 1 "" "" "$STABILIZE_SECONDS" 1
    ;;
  tab-switch)
    run_sample "tab-switch-${TAB_SWITCH_MS}-ms" 12 "" "$TAB_SWITCH_MS"
    ;;
  concurrent-output)
    for count in $CONCURRENT_COUNTS; do
      run_sample "concurrent-output-${OUTPUT_BYTES}-bytes" \
        "$count" "$OUTPUT_BYTES" "" 0 0 1
    done
    ;;
  exit-after-output)
    run_sample "exit-after-output-${OUTPUT_BYTES}-bytes" \
      12 "$OUTPUT_BYTES" "" 8 0 1 1
    ;;
  all)
    for count in $TERMINAL_COUNTS; do
      run_sample "idle" "$count"
    done
    run_sample "output-${OUTPUT_BYTES}-bytes" 1 "$OUTPUT_BYTES" "" 0
    run_sample "output-metal-${OUTPUT_BYTES}-bytes" 1 "$OUTPUT_BYTES" "" 0 1
    run_sample "tab-switch-${TAB_SWITCH_MS}-ms" 12 "" "$TAB_SWITCH_MS"
    ;;
  *)
    echo "usage: $0 [smoke|matrix|throughput|throughput-metal|unicode-output|same-lines|resize|resize-metal|tui|tui-metal|metal-idle|tab-switch|concurrent-output|exit-after-output|all]" >&2
    exit 2
    ;;
esac

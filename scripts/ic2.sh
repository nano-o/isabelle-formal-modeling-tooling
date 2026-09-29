#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh disable=SC1091
source "$SCRIPT_DIR/common.sh"

DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: ic2.sh [--project-root DIR] [--dry-run] ACTION [ARGS...]

Project entry point for a native ic2 server. The project is the nearest
checkout containing isabelle-tooling.conf above the current directory, or the
one named by --project-root. The descriptor supplies the session directory,
the base session, and the heap bound; the server name is derived from the
checkout root, so every worktree gets its own server.

Actions:
  start [OPTIONS]      Start this checkout's server (see start-ic2.sh --help)
  stop [OPTIONS]       Stop this checkout's server
  name                 Print this checkout's derived server name
  wait [OPTIONS]       Wait non-interactively for a terminal check state
  health               Show one resource-usage snapshot of the server's processes
  IC2_COMMAND [...]    Run `isabelle ic2 ...` against this checkout's server,
                       with relative theory paths resolved from the session dir

Examples:
  ic2.sh start --cpus 8
  ic2.sh server status
  ic2.sh check Session/Theory.thy --command-timeout 15
  ic2.sh check status
  ic2.sh wait --timeout 900
  ic2.sh query diagnostics Session/Theory.thy --json
  ic2.sh repl-create Session/Theory.thy:87 r87
  ic2.sh stop
EOF
}

case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac

{ read -r requested_root; read -r consumed; } < <(parse_project_root_option "$@")
shift "$consumed"
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi

[[ $# -gt 0 ]] || { usage >&2; exit 2; }

require_command openssl
resolve_project "$requested_root"
SESSION_DIR="$PROJECT_FORMAL_ROOT"
SESSION="${PROJECT_CONF[ic2_base_session]}"
SERVER_NAME="$(derive_server_name "$PROJECT_CHECKOUT_ROOT")"
MAX_HEAP="${PROJECT_CONF[ic2_max_heap]:-}"

# Best effort: when the checkout uses agent-board and its executable
# resolves, leave a note on the board so live servers are visible next to the
# agents that own them, under the handle ic2 reserved for these notes. `post`
# waits for the board's lock, so the timeout bounds the delay; the note never
# changes the ic2 action's result. Silent without a board.
board_note() {
  local board
  [[ "$DRY_RUN" == false ]] || return 0
  board_configured "$PROJECT_CHECKOUT_ROOT" || return 0
  board="$(resolve_agent_board)" || return 0
  timeout 5 "$board" --project-root "$PROJECT_CHECKOUT_ROOT" --if-board --as ic2 \
    post --kind note "$*" >/dev/null 2>&1 || true
}

reject_fixed_options() {
  local option
  for option in "$@"; do
    case "$option" in
      --session-dir|--session-dir=*|--session|--session=*|--name|--name=*)
        die "$option is fixed by the project descriptor"
        ;;
    esac
  done
}

action="$1"
shift
case "$action" in
  name)
    [[ $# -eq 0 ]] || die "name takes no arguments"
    printf '%s\n' "$SERVER_NAME"
    exit 0
    ;;
  start)
    reject_fixed_options "$@"
    start_args=(--session-dir "$SESSION_DIR" --session "$SESSION" --name "$SERVER_NAME")
    [[ -z "$MAX_HEAP" ]] || start_args+=(--max-heap "$MAX_HEAP")
    [[ "$DRY_RUN" == false ]] || start_args+=(--dry-run)
    board_note "ic2 server $SERVER_NAME starting for $PROJECT_CHECKOUT_ROOT"
    exec "$SCRIPT_DIR/start-ic2.sh" "${start_args[@]}" "$@"
    ;;
  stop)
    reject_fixed_options "$@"
    stop_args=(--name "$SERVER_NAME")
    [[ "$DRY_RUN" == false ]] || stop_args+=(--dry-run)
    board_note "ic2 server $SERVER_NAME stopping for $PROJECT_CHECKOUT_ROOT"
    exec "$SCRIPT_DIR/stop-ic2.sh" "${stop_args[@]}" "$@"
    ;;
esac

# --- everything else is an `isabelle ic2` command against the named server ---

command_args=("$action" "$@")

is_nonnegative_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

status_claims_running_work() {
  local status_output="$1"
  local first_line="${status_output%%$'\n'*}"
  case "$first_line" in
    running|running\ *) return 0 ;;
  esac
  [[ "$status_output" =~ busy\([1-9][0-9]*[[:space:]]checks?\) ]]
}

# The daemon (at the pinned AutoCorrode revision) detects prover death itself
# and reports state=failed. This host-side check is the fallback: it looks for
# a Poly/ML descendant of the server pid. From a shell in a private PID
# namespace the process table is invisible; that is inconclusive, not death.
prover_process_missing() {
  local server_pid descendants
  server_pid="$(server_status_pid "$("$ISABELLE_CMD" ic2 server status -n "$SERVER_NAME" 2>/dev/null || true)")" || return 1
  [[ -d "/proc/$server_pid" ]] || return 1
  descendants="$(descendant_pids "$server_pid")"
  [[ -n "$descendants" ]] || return 1
  ! ps -o comm= -p "$(printf '%s\n' "$descendants" | paste -sd,)" 2>/dev/null |
    grep -Eq '^(poly|polyml)$'
}

STATUS_OUTPUT=""
STATUS_RC=0
capture_status() {
  if STATUS_OUTPUT="$("${exec_command[@]}" 2>&1)"; then
    STATUS_RC=0
  else
    STATUS_RC=$?
  fi
  if [[ "$STATUS_RC" -eq 0 ]] && status_claims_running_work "$STATUS_OUTPUT" &&
      prover_process_missing; then
    [[ -z "$STATUS_OUTPUT" ]] || STATUS_OUTPUT+=$'\n'
    STATUS_OUTPUT+="warning: prover process not found — prover likely died; restart with 'stop' + 'start'"
    STATUS_RC=1
  fi
}

print_status_output() {
  [[ -z "$STATUS_OUTPUT" ]] || printf '%s\n' "$STATUS_OUTPUT"
}

wait_for_check() {
  local interval=15
  local timeout=""
  local started_at=$SECONDS
  local first_line elapsed sleep_for

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval)
        [[ -n "${2:-}" ]] || die "wait --interval requires an argument"
        is_nonnegative_integer "$2" || die "wait --interval expects a non-negative integer, got: $2"
        interval="$2"; shift 2 ;;
      --timeout)
        [[ -n "${2:-}" ]] || die "wait --timeout requires an argument"
        is_nonnegative_integer "$2" || die "wait --timeout expects a non-negative integer, got: $2"
        timeout="$2"; shift 2 ;;
      -h|--help)
        cat <<'EOF'
Usage: ic2.sh wait [--interval SECONDS] [--timeout SECONDS]

Poll `check status` until it reports ok, failed, or idle. Empty replies are
retried. The default interval is 15 seconds; without --timeout, wait forever.
EOF
        return 0 ;;
      *) die "unknown wait option: $1" ;;
    esac
  done

  exec_command=("$ISABELLE_CMD" ic2 check status -n "$SERVER_NAME")
  while true; do
    capture_status
    first_line="${STATUS_OUTPUT%%$'\n'*}"
    if [[ -n "$STATUS_OUTPUT" && "$STATUS_RC" -ne 0 ]]; then
      print_status_output
      return "$STATUS_RC"
    fi
    case "$first_line" in
      ok|ok\ *) print_status_output; return 0 ;;
      failed|failed\ *|idle|idle\ *) print_status_output; return 1 ;;
      running|running\ *|"") ;;
      *) print_status_output; return 1 ;;
    esac
    elapsed=$((SECONDS - started_at))
    if [[ -n "$timeout" && "$elapsed" -ge "$timeout" ]]; then
      print_status_output
      printf 'timeout: check did not reach ok/failed/idle within %ss\n' "$timeout" >&2
      return 124
    fi
    sleep_for="$interval"
    if [[ -n "$timeout" && $((elapsed + sleep_for)) -gt "$timeout" ]]; then
      sleep_for=$((timeout - elapsed))
    fi
    sleep "$sleep_for"
  done
}

show_health() {
  local server_pid pids
  server_pid="$(server_status_pid "$("$ISABELLE_CMD" ic2 server status -n "$SERVER_NAME" 2>&1)")" ||
    die "server is not running: $SERVER_NAME"
  pids="$server_pid"$'\n'"$(descendant_pids "$server_pid")"
  ps -o pid=,rss=,pcpu=,etime=,comm= -p "$(printf '%s\n' "$pids" | sed '/^$/d' | paste -sd,)" 2>/dev/null |
    awk 'BEGIN { printf "%8s %10s %6s %12s %s\n", "PID", "RSS(MiB)", "CPU%", "ELAPSED", "COMMAND"; total = 0 }
         { total += $2; printf "%8s %10.1f %6s %12s %s\n", $1, $2 / 1024, $3, $4, $5 }
         END { printf "%8s %10.1f\n", "total", total / 1024 }'
}

# Every ic2 subcommand takes -n NAME. `check FILE...` parses its options
# before the positional files, so the name goes right after `check` there;
# everywhere else it goes last. `check` resolves relative theory paths against
# our cwd, so commands run from the session directory.
named_command=()
if [[ "${command_args[0]}" == check ]]; then
  case "${command_args[1]:-}" in
    status|cancel|attach|"") named_command=("${command_args[@]}" -n "$SERVER_NAME") ;;
    *) named_command=(check -n "$SERVER_NAME" "${command_args[@]:1}") ;;
  esac
else
  named_command=("${command_args[@]}" -n "$SERVER_NAME")
fi

if [[ "$DRY_RUN" == true ]]; then
  printf 'cd %q && isabelle ic2' "$SESSION_DIR"
  printf ' %q' "${named_command[@]}"
  printf '\n'
  exit 0
fi

require_isabelle
export_ic2_environment
exec_command=("$ISABELLE_CMD" ic2 "${named_command[@]}")
cd "$SESSION_DIR"

case "${command_args[0]}" in
  wait)
    wait_for_check "${command_args[@]:1}" || exit $?
    exit 0
    ;;
  health)
    [[ "${#command_args[@]}" -eq 1 ]] || die "health takes no arguments"
    show_health
    exit 0
    ;;
esac

if [[ "${command_args[0]}" == "check" && "${command_args[1]:-}" == "status" ]] ||
   [[ "${command_args[0]}" == "server" && "${command_args[1]:-}" == "status" ]]; then
  capture_status
  print_status_output
  exit "$STATUS_RC"
fi

exec "${exec_command[@]}"

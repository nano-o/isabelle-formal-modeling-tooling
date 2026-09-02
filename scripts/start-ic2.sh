#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

SESSION_DIR=""
SESSION="HOL"
SERVER_NAME=""
MAX_HEAP=""
THREADS=""
NO_IR=false
ENABLE_MCP=false
NO_BUILD=false
NO_MEMORY_BOUND=false
DRY_RUN=false
EXTRA_OPTIONS=()

usage() {
  cat <<'EOF'
Usage: start-ic2.sh --session-dir DIR --session NAME --name NAME [OPTIONS]

Start one detached ic2 server on the host Isabelle installation. The theory
project is included as an Isabelle session directory, the server starts from
the base session (never the project session, so project theories stay live
document nodes), and the Poly/ML process is placed in a transient user cgroup
bounded by --max-heap where systemd is available.

Options:
  --session-dir DIR   Directory holding the project's ROOT/ROOTS
  --session NAME      Base logic session (default: HOL)
  --name NAME         ic2 server name; also the socket name under
                      $ISABELLE_HOME_USER/ic2/
  --max-heap SIZE     Memory bound for the prover cgroup, e.g. 12G
  --cpus N            Isabelle `threads` option
  --no-ir             Start ic2 without its I/R bridge
  --mcp               Also enable ic2's optional MCP listener
  --no-build          Fail fast if the base heap is missing
  --no-memory-bound   Start without a cgroup even if one is available
  -o OPTION           Extra Isabelle option (repeatable)
  --dry-run           Print the command without running it
  -h, --help          Show this help
EOF
}

require_value() {
  [[ -n "${2:-}" ]] || die "$1 requires an argument"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-dir) require_value "$1" "${2:-}"; SESSION_DIR="$2"; shift 2 ;;
    --session) require_value "$1" "${2:-}"; SESSION="$2"; shift 2 ;;
    --name) require_value "$1" "${2:-}"; SERVER_NAME="$2"; shift 2 ;;
    --max-heap) require_value "$1" "${2:-}"; MAX_HEAP="$2"; shift 2 ;;
    --cpus) require_value "$1" "${2:-}"; THREADS="$2"; shift 2 ;;
    --no-ir) NO_IR=true; shift ;;
    --mcp) ENABLE_MCP=true; shift ;;
    --no-build) NO_BUILD=true; shift ;;
    --no-memory-bound) NO_MEMORY_BOUND=true; shift ;;
    -o) require_value "$1" "${2:-}"; EXTRA_OPTIONS+=("$2"); shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "$SESSION_DIR" ]] || die "--session-dir is required"
[[ -n "$SERVER_NAME" ]] || die "--name is required"
SESSION_DIR="$(canonical_dir "$SESSION_DIR")" || die "session directory does not exist: $SESSION_DIR"
[[ -f "$SESSION_DIR/ROOT" || -f "$SESSION_DIR/ROOTS" ]] ||
  die "session directory has no ROOT or ROOTS: $SESSION_DIR"
[[ "$THREADS" == "" || "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "--cpus expects a positive integer"

# Headless checking needs the session heap, not its PDF artifact. The
# session's own ROOT setting takes precedence over a global document=false
# option, so an empty document-variant list is the effective way to suppress
# PDF output.
command=(isabelle ic2 server start --daemon -n "$SERVER_NAME" -l "$SESSION" -d "$SESSION_DIR" -o document_variants=)

memory_bound="none"
if [[ -n "$MAX_HEAP" && "$NO_MEMORY_BOUND" == false ]]; then
  heap_mb="$(heap_to_megabytes "$MAX_HEAP")" || die "--max-heap: cannot parse: $MAX_HEAP"
  if [[ "$DRY_RUN" == true ]] || memory_bound_available; then
    # Isabelle prefixes the Poly/ML command with process_policy, so the prover
    # (and only the prover) lands in a transient user cgroup. A resource limit,
    # not a security boundary.
    command+=(-o "process_policy=systemd-run --user --scope -q -p MemoryMax=${heap_mb}M -p MemorySwapMax=0")
    memory_bound="${heap_mb}M (systemd user scope)"
  else
    echo "WARNING: no memory bound: systemd-run --user is unavailable; a runaway proof competes with the host" >&2
  fi
fi
[[ -z "$THREADS" ]] || command+=(-o "threads=$THREADS")
[[ "$NO_BUILD" == false ]] || command+=(-N)
[[ "$NO_IR" == false ]] || command+=(--no-iq)
[[ "$ENABLE_MCP" == false ]] || command+=(--mcp)
for option in "${EXTRA_OPTIONS[@]+"${EXTRA_OPTIONS[@]}"}"; do
  command+=(-o "$option")
done

echo "Session dir:  $SESSION_DIR"
echo "Session:      $SESSION"
echo "Server:       $SERVER_NAME"
echo "Memory bound: $memory_bound"

if [[ "$DRY_RUN" == true ]]; then
  echo "Start server:"
  print_command "${command[@]}"
  exit 0
fi

require_isabelle
export_ic2_environment
command[0]="$ISABELLE_CMD"

# ic2 servers outlive agent sessions; "already running" is success.
if status="$("$ISABELLE_CMD" ic2 server status -n "$SERVER_NAME" 2>/dev/null)"; then
  echo "Already running: ${status%%$'\n'*}"
  exit 0
fi

echo "Start server:"
print_command "${command[@]}"
(cd "$SESSION_DIR" && "${command[@]}")
echo "Started server: $SERVER_NAME"
echo "Log:            $("$ISABELLE_CMD" getenv -b ISABELLE_HOME_USER)/ic2/$SERVER_NAME.log"
echo "Query ic2:      $TOOLING_ROOT/scripts/ic2.sh server status"

#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

SERVER_NAME=""
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: stop-ic2.sh --name NAME [--dry-run]

Stop a named ic2 server. Heaps live in the host's ISABELLE_HOME_USER and are
never touched by this script.

Options:
  --name NAME         ic2 server name
  --remove            Accepted for compatibility with the container workflow;
                      a native server leaves nothing behind to remove
  --dry-run           Print the command without running it
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) [[ -n "${2:-}" ]] || die "--name requires an argument"; SERVER_NAME="$2"; shift 2 ;;
    --remove) shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ -n "$SERVER_NAME" ]] || die "--name is required"

command=(isabelle ic2 server stop -n "$SERVER_NAME")
echo "Stop server:"
print_command "${command[@]}"
if [[ "$DRY_RUN" == true ]]; then
  exit 0
fi

require_isabelle
export_ic2_environment
command[0]="$ISABELLE_CMD"
if ! "$ISABELLE_CMD" ic2 server status -n "$SERVER_NAME" >/dev/null 2>&1; then
  echo "Not running: $SERVER_NAME"
  exit 0
fi
"${command[@]}"
echo "Stopped: $SERVER_NAME"

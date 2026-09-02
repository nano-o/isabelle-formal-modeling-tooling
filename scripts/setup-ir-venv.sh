#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

LOCK_FILE="$TOOLING_ROOT/requirements-ir.lock"
VENV_DIR="$TOOLING_ROOT/.venv"
STAMP_FILE="$VENV_DIR/.requirements-ir.sha256"

verify_imports() {
  local python="$1"
  "$python" -c \
    'import mcp, prompt_toolkit; from mcp.server.fastmcp import Context, FastMCP' \
    >/dev/null
  PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1 \
    "$python" -m pip check >/dev/null
}

require_command python3
require_command openssl
python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' ||
  die "Python 3.10 or newer is required"
[[ -f "$LOCK_FILE" ]] || die "dependency lock file is missing: $LOCK_FILE"
[[ ! -L "$VENV_DIR" ]] || die "refusing to replace symlinked virtual environment: $VENV_DIR"

lock_hash="$(openssl dgst -sha256 "$LOCK_FILE" | awk '{print $NF}')"
recreate=false

if [[ ! -x "$VENV_DIR/bin/python3" || ! -f "$STAMP_FILE" ]]; then
  recreate=true
elif [[ "$(<"$STAMP_FILE")" != "$lock_hash" ]]; then
  recreate=true
elif ! verify_imports "$VENV_DIR/bin/python3"; then
  recreate=true
fi

if [[ "$recreate" == true ]]; then
  if [[ -e "$VENV_DIR" ]]; then
    echo "Refreshing I/R virtual environment: $VENV_DIR"
    rm -rf -- "$VENV_DIR"
  else
    echo "Creating I/R virtual environment: $VENV_DIR"
  fi

  python3 -m venv "$VENV_DIR"
  PIP_DISABLE_PIP_VERSION_CHECK=1 "$VENV_DIR/bin/python3" -m pip install \
    --no-deps \
    --requirement "$LOCK_FILE"
  verify_imports "$VENV_DIR/bin/python3"
  printf '%s\n' "$lock_hash" >"$STAMP_FILE"
else
  echo "I/R virtual environment already matches the lock file."
fi

echo "Python: $VENV_DIR/bin/python3"

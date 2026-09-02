#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TOOLING_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

PROJECT_DIR="$PWD"
ISABELLE_CMD="${ISABELLE:-}"
AUTOCORRODE_ROOT="${AUTOCORRODE_BASE:-}"
IR_HOME="${ISABELLE_IR_HOME:-}"
IR_VENV="${IR_PYTHON_VENV:-$TOOLING_ROOT/.venv}"
IQ_TOKEN_FILE="${IQ_TOKEN_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/isabelle-iq/auth-token}"
LOGIC="HOL"
LOGIC_EXPLICIT=false
SESSION=""
DRY_RUN=false
READ_ROOTS=()
THEORY_FILES=()

usage() {
  cat <<'EOF'
Usage: launch_jedit.sh [OPTIONS] [THEORY.thy ...]

Launch Isabelle/jEdit with I/Q restricted to a theory project and I/R pointed
at this AutoCorrode checkout.

Options:
  --project DIR       Theory project directory (default: current directory)
  --logic NAME        Base logic used with `isabelle jedit -l` (default: HOL)
  --session NAME      Load the requirements of session NAME with `-R`;
                      mutually exclusive with --logic
  --isabelle PATH     Isabelle executable or installation directory
  --autocorrode DIR   AutoCorrode checkout containing iq/ and ir/
  --ir-home DIR       Directory containing I/R's repl.py
  --venv DIR          Python virtual environment inherited by the I/R launcher
  --token-file FILE   File containing the persistent I/Q authentication token
  --read-root DIR     Additional I/Q read root; may be repeated
  --dry-run           Print the environment and command without launching
  -h, --help          Show this help

Environment equivalents:
  ISABELLE            Isabelle executable or installation directory
  AUTOCORRODE_BASE    AutoCorrode checkout
  ISABELLE_IR_HOME    I/R directory
  IR_PYTHON_VENV      Python virtual environment
  IQ_TOKEN_FILE       Persistent I/Q authentication-token file

Examples:
  scripts/launch_jedit.sh AutoCorrode.thy
  scripts/launch_jedit.sh --project ../MyProject --session MySession Foo.thy
  scripts/launch_jedit.sh --venv /home/me/.venvs/isabelle-ir Foo.thy
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

require_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "$value" ]] || die "$option requires an argument"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      require_value "$1" "${2:-}"
      PROJECT_DIR="$2"
      shift 2
      ;;
    --logic)
      require_value "$1" "${2:-}"
      [[ -z "$SESSION" ]] || die "--logic and --session are mutually exclusive"
      LOGIC="$2"
      LOGIC_EXPLICIT=true
      shift 2
      ;;
    --session)
      require_value "$1" "${2:-}"
      [[ "$LOGIC_EXPLICIT" == false ]] || die "--logic and --session are mutually exclusive"
      SESSION="$2"
      shift 2
      ;;
    --isabelle)
      require_value "$1" "${2:-}"
      ISABELLE_CMD="$2"
      shift 2
      ;;
    --autocorrode)
      require_value "$1" "${2:-}"
      AUTOCORRODE_ROOT="$2"
      shift 2
      ;;
    --ir-home)
      require_value "$1" "${2:-}"
      IR_HOME="$2"
      shift 2
      ;;
    --venv)
      require_value "$1" "${2:-}"
      IR_VENV="$2"
      shift 2
      ;;
    --token-file)
      require_value "$1" "${2:-}"
      IQ_TOKEN_FILE="$2"
      shift 2
      ;;
    --read-root)
      require_value "$1" "${2:-}"
      READ_ROOTS+=("$2")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      THEORY_FILES+=("$@")
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      THEORY_FILES+=("$1")
      shift
      ;;
  esac
done

[[ -d "$PROJECT_DIR" ]] || die "project directory does not exist: $PROJECT_DIR"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

if [[ -z "$AUTOCORRODE_ROOT" ]]; then
  candidate="$TOOLING_ROOT/AutoCorrode"
  if [[ -f "$candidate/ir/repl.py" && -d "$candidate/iq" ]]; then
    AUTOCORRODE_ROOT="$candidate"
  fi
fi

if [[ -n "$AUTOCORRODE_ROOT" ]]; then
  [[ -d "$AUTOCORRODE_ROOT" ]] ||
    die "AutoCorrode directory does not exist: $AUTOCORRODE_ROOT"
  AUTOCORRODE_ROOT="$(cd "$AUTOCORRODE_ROOT" && pwd -P)"
fi

if [[ -z "$IR_HOME" ]]; then
  [[ -n "$AUTOCORRODE_ROOT" ]] ||
    die "AutoCorrode not found; use --autocorrode DIR, --ir-home DIR, or set AUTOCORRODE_BASE"
  IR_HOME="$AUTOCORRODE_ROOT/ir"
fi

[[ -d "$IR_HOME" ]] || die "I/R directory does not exist: $IR_HOME"
IR_HOME="$(cd "$IR_HOME" && pwd -P)"
[[ -f "$IR_HOME/repl.py" ]] || die "repl.py not found in I/R directory: $IR_HOME"

if [[ -z "$AUTOCORRODE_ROOT" && -d "$(dirname "$IR_HOME")/iq" ]]; then
  AUTOCORRODE_ROOT="$(cd "$(dirname "$IR_HOME")" && pwd -P)"
fi

[[ -f "$IQ_TOKEN_FILE" ]] || die "I/Q token file does not exist: $IQ_TOKEN_FILE"
[[ -r "$IQ_TOKEN_FILE" ]] || die "I/Q token file is not readable: $IQ_TOKEN_FILE"
IQ_TOKEN_FILE="$(cd "$(dirname "$IQ_TOKEN_FILE")" && pwd -P)/$(basename "$IQ_TOKEN_FILE")"
IQ_AUTH_TOKEN="$(<"$IQ_TOKEN_FILE")"
[[ -n "${IQ_AUTH_TOKEN//[[:space:]]/}" ]] || die "I/Q token file is empty: $IQ_TOKEN_FILE"

TOKEN_MODE=""
if TOKEN_MODE="$(stat -c '%a' "$IQ_TOKEN_FILE" 2>/dev/null)"; then
  :
elif TOKEN_MODE="$(stat -f '%Lp' "$IQ_TOKEN_FILE" 2>/dev/null)"; then
  :
fi
if [[ "$TOKEN_MODE" =~ ^[0-7]+$ ]] && (( (8#$TOKEN_MODE & 077) != 0 )); then
  echo "WARNING: I/Q token file is accessible by group or other users (mode $TOKEN_MODE)." >&2
  echo "Restrict it with: chmod 600 $IQ_TOKEN_FILE" >&2
fi

if [[ -z "$ISABELLE_CMD" ]]; then
  if command -v isabelle >/dev/null 2>&1; then
    ISABELLE_CMD="$(command -v isabelle)"
  else
    for candidate in \
      "${ISABELLE_TOOLING_ISABELLE:-}" \
      "${ISABELLE_TOOLING_ISABELLE:-/nonexistent}/bin/isabelle"
    do
      if [[ -x "$candidate" ]]; then
        ISABELLE_CMD="$candidate"
        break
      fi
    done
    [[ -n "$ISABELLE_CMD" ]] ||
      die "Isabelle not found; use --isabelle PATH or set ISABELLE"
  fi
fi

if [[ -d "$ISABELLE_CMD" ]]; then
  if [[ -x "$ISABELLE_CMD/bin/isabelle" ]]; then
    ISABELLE_CMD="$ISABELLE_CMD/bin/isabelle"
  elif [[ -x "$ISABELLE_CMD/isabelle" ]]; then
    ISABELLE_CMD="$ISABELLE_CMD/isabelle"
  else
    die "no Isabelle executable found under: $ISABELLE_CMD"
  fi
fi
[[ -x "$ISABELLE_CMD" ]] || die "Isabelle executable is not executable: $ISABELLE_CMD"
ISABELLE_CMD="$(cd "$(dirname "$ISABELLE_CMD")" && pwd -P)/$(basename "$ISABELLE_CMD")"

LAUNCH_PATH="$PATH"
if [[ -n "$IR_VENV" ]]; then
  [[ -d "$IR_VENV" ]] || die "Python virtual environment does not exist: $IR_VENV"
  IR_VENV="$(cd "$IR_VENV" && pwd -P)"
  [[ -x "$IR_VENV/bin/python3" ]] || die "python3 not found in virtual environment: $IR_VENV"
  LAUNCH_PATH="$IR_VENV/bin:$LAUNCH_PATH"
fi

PATH="$LAUNCH_PATH" command -v python3 >/dev/null 2>&1 ||
  die "python3 is not available to I/R; use --venv DIR"

ALLOWED_READ_ROOTS="$PROJECT_DIR"
for root in "${READ_ROOTS[@]}"; do
  [[ -d "$root" ]] || die "additional read root does not exist: $root"
  root="$(cd "$root" && pwd -P)"
  ALLOWED_READ_ROOTS+="${PATH_SEPARATOR:-:}$root"
done

JEDIT_ARGS=(jedit)
if [[ -n "$SESSION" ]]; then
  JEDIT_ARGS+=(-d "$PROJECT_DIR" -R "$SESSION")
else
  JEDIT_ARGS+=(-l "$LOGIC")
  if [[ -f "$PROJECT_DIR/ROOT" || -f "$PROJECT_DIR/ROOTS" ]]; then
    JEDIT_ARGS+=(-d "$PROJECT_DIR")
  fi
fi

for theory in "${THEORY_FILES[@]}"; do
  if [[ "$theory" = /* ]]; then
    JEDIT_ARGS+=("$theory")
  else
    JEDIT_ARGS+=("$PROJECT_DIR/$theory")
  fi
done

ISABELLE_HOME_USER="$($ISABELLE_CMD getenv -b ISABELLE_HOME_USER 2>/dev/null || true)"
if [[ -n "$ISABELLE_HOME_USER" && ! -f "$ISABELLE_HOME_USER/jedit/jars/iq_plugin.jar" ]]; then
  echo "WARNING: I/Q plugin JAR not found at:" >&2
  echo "  $ISABELLE_HOME_USER/jedit/jars/iq_plugin.jar" >&2
  if [[ -n "$AUTOCORRODE_ROOT" ]]; then
    echo "Install it with: $TOOLING_ROOT/scripts/install-iq-plugin.sh" >&2
  fi
fi

echo "Project:          $PROJECT_DIR"
echo "I/Q write root:  $PROJECT_DIR"
echo "I/Q read roots:  $ALLOWED_READ_ROOTS"
echo "I/Q token file:  $IQ_TOKEN_FILE"
echo "I/R home:        $IR_HOME"
echo "Python:          $(PATH="$LAUNCH_PATH" command -v python3)"
echo "Isabelle:        $ISABELLE_CMD"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Command:          env PATH=%q ISABELLE_IR_HOME=%q IQ_AUTH_TOKEN=%q IQ_MCP_ALLOWED_ROOTS=%q IQ_MCP_ALLOWED_READ_ROOTS=%q' \
    "$LAUNCH_PATH" "$IR_HOME" '<redacted>' "$PROJECT_DIR" "$ALLOWED_READ_ROOTS"
  printf ' %q' "$ISABELLE_CMD" "${JEDIT_ARGS[@]}"
  printf '\n'
  exit 0
fi

exec env \
  PATH="$LAUNCH_PATH" \
  ISABELLE_IR_HOME="$IR_HOME" \
  IQ_AUTH_TOKEN="$IQ_AUTH_TOKEN" \
  IQ_MCP_ALLOWED_ROOTS="$PROJECT_DIR" \
  IQ_MCP_ALLOWED_READ_ROOTS="$ALLOWED_READ_ROOTS" \
  "$ISABELLE_CMD" "${JEDIT_ARGS[@]}"

#!/usr/bin/env bash
# Shared helpers for the Isabelle tooling scripts. TOOLING_ROOT is the tooling
# clone: this directory's parent, which also holds the AutoCorrode submodule,
# the I/R virtual environment, and the ic2 JAR.

COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# Used by scripts that source this library; ShellCheck also analyzes this file
# independently and cannot see those consumers.
# shellcheck disable=SC2034
TOOLING_ROOT="$(cd "$COMMON_SCRIPT_DIR/.." && pwd -P)"

die() {
  echo "ERROR: $*" >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

canonical_dir() {
  local path="$1"
  [[ -d "$path" ]] || return 1
  (cd "$path" && pwd -P)
}

canonical_file() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  local directory
  directory="$(cd "$(dirname "$path")" && pwd -P)"
  printf '%s/%s\n' "$directory" "$(basename "$path")"
}

sanitize_name() {
  local value="$1"
  # Every ic2 entry point derives its server name through here.
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//')"
  [[ -n "$value" ]] || value="project"
  printf '%s\n' "$value"
}

print_command() {
  printf '  '
  printf '%q ' "$@"
  printf '\n'
}

hash_files() {
  local file
  for file in "$@"; do
    [[ -f "$file" ]] || return 1
  done
  {
    for file in "$@"; do
      openssl dgst -sha256 -binary "$file"
    done
  } | openssl dgst -sha256 | awk '{print $NF}'
}

# ---------------------------------------------------------------------------
# Project descriptor and resolution
#
# A checkout that uses this tooling carries one committed file at its root,
# isabelle-tooling.conf, in a deliberately small key=value format: UTF-8, one
# key per line, full-line # comments, the value is everything after the first
# `=`. It is data, never sourced or passed to eval. Two relative roots make the
# layout configuration rather than architecture: source_rel is where the code
# under study lives and formal_rel is where the Isabelle session lives, both
# relative to the checkout root. model_kind is code (the default when absent)
# or theory, for a project with no implementation to model.

DESCRIPTOR_FILE_NAME="isabelle-tooling.conf"
DESCRIPTOR_REQUIRED_KEYS=(
  format_version source_rel formal_rel build_session session_dir
  ic2_base_session isabelle_version
)
DESCRIPTOR_OPTIONAL_KEYS=(
  tooling_revision ic2_max_heap export_name model_dispatch audit_collection
  model_kind
)
DESCRIPTOR_KINDS=(code theory)
# Keys whose values are paths relative to a root; they may not be absolute and
# may not contain a `..` component.
DESCRIPTOR_PATH_KEYS=(source_rel formal_rel session_dir model_dispatch)

# Set by resolve_project and read by the scripts that source this library;
# ShellCheck analyzes this file on its own and cannot see those consumers.
# shellcheck disable=SC2034
declare -gA PROJECT_CONF=()
PROJECT_CHECKOUT_ROOT=""
PROJECT_DESCRIPTOR=""
PROJECT_SOURCE_ROOT=""
PROJECT_FORMAL_ROOT=""

descriptor_key_known() {
  local key="$1"
  local known
  for known in "${DESCRIPTOR_REQUIRED_KEYS[@]}" "${DESCRIPTOR_OPTIONAL_KEYS[@]}"; do
    [[ "$known" == "$key" ]] && return 0
  done
  return 1
}

descriptor_kind_known() {
  local kind="$1"
  local known
  for known in "${DESCRIPTOR_KINDS[@]}"; do
    [[ "$known" == "$kind" ]] && return 0
  done
  return 1
}

descriptor_path_key() {
  local key="$1"
  local path_key
  for path_key in "${DESCRIPTOR_PATH_KEYS[@]}"; do
    [[ "$path_key" == "$key" ]] && return 0
  done
  return 1
}

# Reject an absolute path or any `..` component in a descriptor path value.
check_descriptor_path() {
  local file="$1"
  local key="$2"
  local value="$3"
  local component
  [[ "$value" != /* ]] || die "$file: $key must be relative to the checkout root, found absolute path: $value"
  [[ -n "$value" ]] || die "$file: $key must not be empty"
  local IFS='/'
  for component in $value; do
    [[ "$component" != ".." ]] || die "$file: $key must not contain a '..' component: $value"
  done
}

# parse_descriptor FILE: fill PROJECT_CONF from FILE, rejecting malformed
# lines, unknown or duplicate keys, missing required keys, an unsupported
# format_version, and path values that escape the checkout root.
parse_descriptor() {
  local file="$1"
  local line key value line_number=0
  PROJECT_CONF=()

  [[ -f "$file" ]] || die "descriptor not found: $file"
  if command -v iconv >/dev/null 2>&1; then
    iconv -f UTF-8 -t UTF-8 <"$file" >/dev/null 2>&1 ||
      die "$file: not valid UTF-8"
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    [[ "$line" == *=* ]] ||
      die "$file:$line_number: expected key=value, found: $line"
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^[a-z][a-z0-9_]*$ ]] ||
      die "$file:$line_number: malformed key: $key"
    descriptor_key_known "$key" ||
      die "$file:$line_number: unknown key: $key"
    [[ -z "${PROJECT_CONF[$key]+set}" ]] ||
      die "$file:$line_number: duplicate key: $key"
    PROJECT_CONF["$key"]="$value"
  done <"$file"

  for key in "${DESCRIPTOR_REQUIRED_KEYS[@]}"; do
    [[ -n "${PROJECT_CONF[$key]+set}" ]] ||
      die "$file: missing required key: $key"
  done
  [[ "${PROJECT_CONF[format_version]}" == "1" ]] ||
    die "$file: unsupported format_version: ${PROJECT_CONF[format_version]} (expected 1)"
  if [[ -n "${PROJECT_CONF[model_kind]+set}" ]]; then
    descriptor_kind_known "${PROJECT_CONF[model_kind]}" ||
      die "$file: unknown model_kind: ${PROJECT_CONF[model_kind]} (expected ${DESCRIPTOR_KINDS[*]})"
  fi
  for key in "${DESCRIPTOR_PATH_KEYS[@]}"; do
    [[ -n "${PROJECT_CONF[$key]+set}" ]] || continue
    check_descriptor_path "$file" "$key" "${PROJECT_CONF[$key]}"
  done
}

# find_checkout_root START: print the nearest ancestor of START (inclusive)
# that contains the descriptor, or fail.
find_checkout_root() {
  local dir="$1"
  while :; do
    if [[ -f "$dir/$DESCRIPTOR_FILE_NAME" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    [[ "$dir" != "/" ]] || return 1
    dir="$(dirname "$dir")"
  done
}

# resolve_project [PROJECT_ROOT]: bind PROJECT_* to a checkout. With an
# argument, canonicalize it and read the descriptor there; without one, walk up
# from the canonical $PWD to the nearest descriptor. Nested projects resolve to
# the nearest descriptor, and the explicit argument overrides that.
resolve_project() {
  local requested="${1:-}"
  local root

  if [[ -n "$requested" ]]; then
    root="$(canonical_dir "$requested")" ||
      die "--project-root: not a directory: $requested"
    [[ -f "$root/$DESCRIPTOR_FILE_NAME" ]] ||
      die "--project-root: no $DESCRIPTOR_FILE_NAME in $root"
  else
    root="$(find_checkout_root "$(pwd -P)")" ||
      die "no $DESCRIPTOR_FILE_NAME found in $(pwd -P) or any parent directory.
Run from inside a checkout that carries the descriptor at its root, or pass
--project-root DIR. To create one, copy the descriptor format from an existing
project (see formal/tooling/README.md)."
  fi

  # shellcheck disable=SC2034
  PROJECT_CHECKOUT_ROOT="$root"
  PROJECT_DESCRIPTOR="$root/$DESCRIPTOR_FILE_NAME"
  parse_descriptor "$PROJECT_DESCRIPTOR"
  # shellcheck disable=SC2034
  PROJECT_SOURCE_ROOT="$(canonical_dir "$root/${PROJECT_CONF[source_rel]}")" ||
    die "$PROJECT_DESCRIPTOR: source_rel does not name a directory: ${PROJECT_CONF[source_rel]}"
  # shellcheck disable=SC2034
  PROJECT_FORMAL_ROOT="$(canonical_dir "$root/${PROJECT_CONF[formal_rel]}")" ||
    die "$PROJECT_DESCRIPTOR: formal_rel does not name a directory: ${PROJECT_CONF[formal_rel]}"
}

# Consume a leading --project-root option from an argument list. Prints the
# requested root (possibly empty) on the first line and the number of
# arguments consumed on the second.
parse_project_root_option() {
  case "${1:-}" in
    --project-root)
      [[ -n "${2:-}" ]] || die "--project-root requires an argument"
      printf '%s\n2\n' "$2"
      ;;
    --project-root=*)
      printf '%s\n1\n' "${1#--project-root=}"
      ;;
    *)
      printf '\n0\n'
      ;;
  esac
}

# derive_server_name CHECKOUT_ROOT: the per-checkout ic2 server name, ic2-<sanitized basename>-<first 8 hex of sha256 of the
# canonical path>, so that every worktree gets its own prover. The basename part is cut to IC2_NAME_STEM_MAX characters:
# the server's socket is $ISABELLE_HOME_USER/ic2/<name>.sock, and ic2 refuses socket paths over 100 bytes.
IC2_NAME_STEM_MAX=24
# Read by doctor.sh, which sources this library; ShellCheck cannot see it.
# shellcheck disable=SC2034
IC2_NAME_MAX=$((4 + IC2_NAME_STEM_MAX + 1 + 8))
derive_server_name() {
  local checkout_root="$1"
  local name hash
  name="$(sanitize_name "$(basename "$checkout_root")")"
  name="${name:0:IC2_NAME_STEM_MAX}"
  name="$(printf '%s' "$name" | sed -E 's/[-.]+$//')"
  [[ -n "$name" ]] || name="project"
  hash="$(printf '%s' "$checkout_root" | openssl dgst -sha256 | awk '{print substr($NF, 1, 8)}')"
  printf 'ic2-%s-%s\n' "$name" "$hash"
}

# ---------------------------------------------------------------------------
# Host Isabelle, the tooling clone's build products, and ic2 servers

# Read by the scripts that source this library; ShellCheck cannot see them.
# shellcheck disable=SC2034
AUTOCORRODE_DIR="$TOOLING_ROOT/AutoCorrode"
# shellcheck disable=SC2034
IC2_COMPONENT_DIR="$AUTOCORRODE_DIR/ic2"
# shellcheck disable=SC2034
IR_VENV_DIR="$TOOLING_ROOT/.venv"
# shellcheck disable=SC2034
IR_LOCK_FILE="$TOOLING_ROOT/requirements-ir.lock"

# find_isabelle: print the Isabelle executable, preferring `isabelle` on PATH,
# else the one named by ISABELLE_TOOLING_ISABELLE (an executable or an
# installation directory). Fails if neither exists.
find_isabelle() {
  local candidate
  if candidate="$(command -v isabelle 2>/dev/null)"; then
    printf '%s\n' "$candidate"
    return 0
  fi
  candidate="${ISABELLE_TOOLING_ISABELLE:-}"
  [[ -n "$candidate" ]] || return 1
  if [[ -d "$candidate" && -x "$candidate/bin/isabelle" ]]; then
    candidate="$candidate/bin/isabelle"
  fi
  [[ -x "$candidate" ]] || return 1
  printf '%s\n' "$candidate"
}

# shellcheck disable=SC2034
ISABELLE_CMD=""
require_isabelle() {
  # shellcheck disable=SC2034
  ISABELLE_CMD="$(find_isabelle)" ||
    die "Isabelle not found: put its bin/ on PATH or set ISABELLE_TOOLING_ISABELLE"
}

# heap_to_megabytes VALUE: parse a human-readable heap bound (12G, 512M,
# 12288) to a plain number of megabytes.
heap_to_megabytes() {
  local value="$1"
  case "$value" in
    *[Gg]) printf '%s\n' $(( ${value%[Gg]} * 1024 )) ;;
    *[Mm]) printf '%s\n' "${value%[Mm]}" ;;
    *)
      [[ "$value" =~ ^[0-9]+$ ]] || return 1
      printf '%s\n' "$value"
      ;;
  esac
}

# memory_bound_available: whether a transient user cgroup can be created.
memory_bound_available() {
  command -v systemd-run >/dev/null 2>&1 &&
    systemd-run --user --scope -q -p MemoryMax=1G true >/dev/null 2>&1
}

# Environment for a natively started ic2 server or client: the tooling clone's
# I/R virtual environment first on PATH, so the daemon's `python3` finds the
# I/R dependencies, and AUTOCORRODE_BASE naming the pinned tree.
export_ic2_environment() {
  if [[ -x "$IR_VENV_DIR/bin/python3" ]]; then
    export PATH="$IR_VENV_DIR/bin:$PATH"
  fi
  export AUTOCORRODE_BASE="$AUTOCORRODE_DIR"
}

# server_status_pid STATUS_OUTPUT: the pid a `server status` summary reports,
# or nothing.
server_status_pid() {
  local output="$1"
  [[ "$output" =~ [[:space:]]pid=([0-9]+) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

# ---------------------------------------------------------------------------
# agent-board, optional
#
# A checkout uses agent-board when agent-board.conf is at its root. The
# executable is AGENT_BOARD_COMMAND (one absolute path, no arguments), else
# agent-board on PATH; its identity is the resolved real path. The tooling
# never reads the board's descriptor or storage.

# The agent-board interface this adapter supports; doctor requires the
# executable's `version --json` to report it, with the doctor and project
# capabilities.
# shellcheck disable=SC2034
AGENT_BOARD_INTERFACE=1

# board_configured CHECKOUT_ROOT: whether the checkout uses agent-board.
board_configured() {
  [[ -f "$1/agent-board.conf" ]]
}

# resolve_agent_board: print the resolved real path of the agent-board
# executable, or fail when it does not resolve.
resolve_agent_board() {
  local cmd="${AGENT_BOARD_COMMAND:-}"
  if [[ -n "$cmd" ]]; then
    [[ "$cmd" == /* && -f "$cmd" && -x "$cmd" ]] || return 1
  else
    cmd="$(command -v agent-board 2>/dev/null)" || return 1
    [[ "$cmd" == /* ]] || return 1
  fi
  readlink -f -- "$cmd"
}

# descendant_pids PID: every descendant of PID, one per line, or nothing when
# the process table is not visible from here.
descendant_pids() {
  local root="$1"
  ps -eo pid=,ppid= 2>/dev/null | awk -v root="$root" '
    { parent[$1] = $2 }
    END {
      for (p in parent) {
        q = p
        while (q in parent && parent[q] != root && parent[q] != 0) q = parent[q]
        if (q in parent && parent[q] == root) print p
      }
    }'
}

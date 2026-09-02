#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

AUTOCORRODE_DIR="${AUTOCORRODE_BASE:-$TOOLING_ROOT/AutoCorrode}"
ISABELLE_INPUT="${ISABELLE:-${ISABELLE_HOME:-}}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: install-iq-plugin.sh [OPTIONS]

Build and install the I/Q jEdit plugin from the tooling clone's pinned
AutoCorrode submodule, then write a provenance stamp beside the JAR.

Options:
  --isabelle PATH     Isabelle executable or installation directory
  --autocorrode DIR   AutoCorrode checkout (default: the tooling clone's submodule)
  --dry-run           Print the build/install command without running it
  -h, --help          Show this help
EOF
}

require_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "$value" ]] || die "$option requires an argument"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --isabelle)
      require_value "$1" "${2:-}"
      ISABELLE_INPUT="$2"
      shift 2
      ;;
    --autocorrode)
      require_value "$1" "${2:-}"
      AUTOCORRODE_DIR="$2"
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
    *)
      die "unknown option: $1"
      ;;
  esac
done

resolve_isabelle() {
  local candidate="$1"
  [[ -n "$candidate" ]] || return 1
  if [[ -d "$candidate" ]]; then
    if [[ -x "$candidate/bin/isabelle" ]]; then
      candidate="$candidate/bin/isabelle"
    elif [[ -x "$candidate/isabelle" ]]; then
      candidate="$candidate/isabelle"
    else
      return 1
    fi
  fi
  [[ -x "$candidate" ]] || return 1
  canonical_file "$candidate"
}

ISABELLE_CMD=""
isabelle_candidates=("$ISABELLE_INPUT")
if command -v isabelle >/dev/null 2>&1; then
  isabelle_candidates+=("$(command -v isabelle)")
fi
isabelle_candidates+=("${ISABELLE_TOOLING_ISABELLE:-}")
for candidate in "${isabelle_candidates[@]}"; do
  if ISABELLE_CMD="$(resolve_isabelle "$candidate" 2>/dev/null)"; then
    break
  fi
  ISABELLE_CMD=""
done
[[ -n "$ISABELLE_CMD" ]] ||
  die "Isabelle not found; put Isabelle2025-2 on PATH or use --isabelle PATH"

AUTOCORRODE_DIR="$(canonical_dir "$AUTOCORRODE_DIR")" ||
  die "AutoCorrode directory does not exist: $AUTOCORRODE_DIR"
[[ -f "$AUTOCORRODE_DIR/iq/Makefile" ]] ||
  die "I/Q plugin source is missing under: $AUTOCORRODE_DIR"

require_command git
require_command make
AUTOCORRODE_REV="$(git -C "$AUTOCORRODE_DIR" rev-parse HEAD 2>/dev/null)" ||
  die "AutoCorrode checkout has no Git revision: $AUTOCORRODE_DIR"
git -C "$AUTOCORRODE_DIR" diff --quiet --ignore-submodules -- ||
  die "AutoCorrode checkout has uncommitted changes; refusing to stamp an unpinned build"
git -C "$AUTOCORRODE_DIR" diff --cached --quiet --ignore-submodules -- ||
  die "AutoCorrode checkout has staged changes; refusing to stamp an unpinned build"

ISABELLE_VERSION="$($ISABELLE_CMD version)"
[[ "$ISABELLE_VERSION" == "Isabelle2025-2" ]] ||
  die "I/Q is pinned to Isabelle2025-2, found: $ISABELLE_VERSION"
ISABELLE_HOME="$($ISABELLE_CMD getenv -b ISABELLE_HOME)"
ISABELLE_HOME_USER="$($ISABELLE_CMD getenv -b ISABELLE_HOME_USER)"
PLUGIN_DIR="$ISABELLE_HOME_USER/jedit/jars"
PLUGIN_JAR="$PLUGIN_DIR/iq_plugin.jar"
STAMP_FILE="$PLUGIN_DIR/iq_plugin.jar.stamp"

install_command=(
  make -C "$AUTOCORRODE_DIR/iq"
  "ISABELLE_HOME=$ISABELLE_HOME"
  "ISABELLE=$ISABELLE_CMD"
  "INSTALL_DIR=$PLUGIN_DIR"
  install
)

echo "AutoCorrode: $AUTOCORRODE_DIR ($AUTOCORRODE_REV)"
echo "Isabelle:    $ISABELLE_CMD ($ISABELLE_VERSION)"
echo "Plugin:      $PLUGIN_JAR"
echo "Command:"
print_command "${install_command[@]}"

if [[ "$DRY_RUN" == true ]]; then
  exit 0
fi

"${install_command[@]}"
[[ -f "$PLUGIN_JAR" ]] || die "I/Q build did not install the expected JAR: $PLUGIN_JAR"

stamp_tmp="$(mktemp "$PLUGIN_DIR/.iq_plugin.jar.stamp.XXXXXX")"
trap 'rm -f -- "$stamp_tmp"' EXIT
{
  printf 'autocorrode_revision=%s\n' "$AUTOCORRODE_REV"
  printf 'isabelle_version=%s\n' "$ISABELLE_VERSION"
} >"$stamp_tmp"
chmod 644 "$stamp_tmp"
mv -f -- "$stamp_tmp" "$STAMP_FILE"
trap - EXIT

echo "Provenance:  $STAMP_FILE"

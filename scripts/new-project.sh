#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

CHECKOUT=""
FORMAL_REL="formal"
SOURCE_REL="."
SESSION=""
PROJECT_NAME=""
MAX_HEAP="12G"
ISABELLE_VERSION="Isabelle2025-2"
TOOLING_URL="${ISABELLE_TOOLING_URL:-https://github.com/nano-o/isabelle-formal-modeling-tooling}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: new-project.sh --checkout DIR --session NAME [OPTIONS]

Create the descriptor and an empty Isabelle session for a project checkout from
the tooling templates. Existing files are never overwritten.

Options:
  --checkout DIR      Root of the project checkout (the descriptor goes here)
  --session NAME      Isabelle session name; also the session directory name
  --formal-rel PATH   Formal artifacts directory relative to the checkout (default: formal)
  --source-rel PATH   Code directory relative to the checkout (default: .)
  --project-name STR  Human name used in generated text (default: checkout basename)
  --max-heap SIZE     ic2 prover memory bound (default: 12G)
  --dry-run           List what would be written
  -h, --help          Show this help

Writes:
  DIR/isabelle-tooling.conf
  DIR/FORMAL_REL/{ROOT,ROOTS,AGENTS.md,README.md,CLAUDE.md -> AGENTS.md}
  DIR/FORMAL_REL/NAME/{ROOT,NAME.thy}
EOF
}

require_value() { [[ -n "${2:-}" ]] || die "$1 requires an argument"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --checkout) require_value "$1" "${2:-}"; CHECKOUT="$2"; shift 2 ;;
    --session) require_value "$1" "${2:-}"; SESSION="$2"; shift 2 ;;
    --formal-rel) require_value "$1" "${2:-}"; FORMAL_REL="$2"; shift 2 ;;
    --source-rel) require_value "$1" "${2:-}"; SOURCE_REL="$2"; shift 2 ;;
    --project-name) require_value "$1" "${2:-}"; PROJECT_NAME="$2"; shift 2 ;;
    --max-heap) require_value "$1" "${2:-}"; MAX_HEAP="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "$CHECKOUT" ]] || die "--checkout is required"
[[ -n "$SESSION" ]] || die "--session is required"
[[ "$SESSION" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || die "--session must be an Isabelle session name (letters, digits, underscores): $SESSION"
CHECKOUT="$(canonical_dir "$CHECKOUT")" || die "--checkout: not a directory: $CHECKOUT"
check_descriptor_path "(new-project)" formal_rel "$FORMAL_REL"
check_descriptor_path "(new-project)" source_rel "$SOURCE_REL"
[[ -n "$PROJECT_NAME" ]] || PROJECT_NAME="$(basename "$CHECKOUT")"
heap_to_megabytes "$MAX_HEAP" >/dev/null || die "--max-heap: cannot parse: $MAX_HEAP"
TOOLING_REVISION="$(git -C "$TOOLING_ROOT" rev-parse HEAD 2>/dev/null || die "cannot read the tooling clone revision")"

FORMAL_DIR="$CHECKOUT/$FORMAL_REL"
SESSION_DIR="$FORMAL_DIR/$SESSION"
TEMPLATES="$TOOLING_ROOT/templates"

# render TEMPLATE TARGET: substitute the @PLACEHOLDER@ tokens.
render() {
  sed \
    -e "s|@SOURCE_REL@|$SOURCE_REL|g" \
    -e "s|@FORMAL_REL@|$FORMAL_REL|g" \
    -e "s|@TOOLING_REVISION@|$TOOLING_REVISION|g" \
    -e "s|@TOOLING_URL@|$TOOLING_URL|g" \
    -e "s|@SESSION@|$SESSION|g" \
    -e "s|@PROJECT_NAME@|$PROJECT_NAME|g" \
    -e "s|@MAX_HEAP@|$MAX_HEAP|g" \
    -e "s|@ISABELLE_VERSION@|$ISABELLE_VERSION|g" \
    "$1"
}

targets=(
  "$CHECKOUT/$DESCRIPTOR_FILE_NAME"
  "$FORMAL_DIR/ROOTS" "$FORMAL_DIR/AGENTS.md" "$FORMAL_DIR/README.md" "$FORMAL_DIR/CLAUDE.md"
  "$SESSION_DIR/ROOT" "$SESSION_DIR/$SESSION.thy"
)
for target in "${targets[@]}"; do
  [[ ! -e "$target" ]] || die "refusing to overwrite existing file: $target"
done

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would write:\n'
  printf '  %s\n' "${targets[@]}"
  exit 0
fi

mkdir -p "$SESSION_DIR"
render "$TEMPLATES/isabelle-tooling.conf" >"$CHECKOUT/$DESCRIPTOR_FILE_NAME"
render "$TEMPLATES/formal/ROOTS" >"$FORMAL_DIR/ROOTS"
render "$TEMPLATES/formal/AGENTS.md" >"$FORMAL_DIR/AGENTS.md"
render "$TEMPLATES/formal/README.md" >"$FORMAL_DIR/README.md"
ln -s AGENTS.md "$FORMAL_DIR/CLAUDE.md"
render "$TEMPLATES/formal/ROOT" >"$SESSION_DIR/ROOT"
render "$TEMPLATES/formal/Session.thy" >"$SESSION_DIR/$SESSION.thy"

# The generated descriptor must parse; fail loudly here rather than later.
parse_descriptor "$CHECKOUT/$DESCRIPTOR_FILE_NAME"

printf 'Created:\n'
printf '  %s\n' "${targets[@]}"
echo "Next: $TOOLING_ROOT/scripts/doctor.sh --project-root $CHECKOUT"
echo "      isabelle build -D $FORMAL_DIR"

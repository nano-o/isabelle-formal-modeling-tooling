#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

REVISION=""
STAGE=""
FORMAL_REL="formal"
SOURCE_REL="."
SESSION=""
PROJECT_NAME=""
MAX_HEAP="12G"
KIND="code"
ISABELLE_VERSION="Isabelle2025-2"
TOOLING_URL="${ISABELLE_TOOLING_URL:-https://github.com/nano-o/isabelle-formal-modeling-tooling}"

usage() {
  cat <<'EOF_USAGE'
Usage: new-project.sh --revision COMMIT --stage DIR --session NAME --project-name STR [OPTIONS]

The session renderer behind `isabelle-tooling init`; run that instead. Render
the descriptor and an empty Isabelle session from the templates at COMMIT,
read with `git show`, never from a working tree, into the empty directory DIR,
laid out as they go in the checkout. init publishes them with the project
files, descriptor last. A code project's templates are templates/ and
templates/formal/; a theory project's are templates/theory/, except ROOTS.

Options:
  --revision COMMIT   Full commit of the tooling whose templates are rendered
  --stage DIR         Empty directory to render into
  --session NAME      Isabelle session name; also the session directory name
  --project-name STR  Human name used in generated text
  --formal-rel PATH   Formal artifacts directory relative to the checkout (default: formal)
  --source-rel PATH   Code directory relative to the checkout (default: .)
  --max-heap SIZE     ic2 prover memory bound (default: 12G)
  --kind KIND         code (default) or theory: a project with no implementation
  -h, --help          Show this help

Renders into DIR:
  isabelle-tooling.conf
  FORMAL_REL/{ROOTS,AGENTS.md,README.md,CLAUDE.md -> AGENTS.md}
  FORMAL_REL/NAME/{ROOT,NAME.thy}
EOF_USAGE
}

require_value() { [[ -n "${2:-}" ]] || die "$1 requires an argument"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --revision) require_value "$1" "${2:-}"; REVISION="$2"; shift 2 ;;
    --stage) require_value "$1" "${2:-}"; STAGE="$2"; shift 2 ;;
    --session) require_value "$1" "${2:-}"; SESSION="$2"; shift 2 ;;
    --formal-rel) require_value "$1" "${2:-}"; FORMAL_REL="$2"; shift 2 ;;
    --source-rel) require_value "$1" "${2:-}"; SOURCE_REL="$2"; shift 2 ;;
    --project-name) require_value "$1" "${2:-}"; PROJECT_NAME="$2"; shift 2 ;;
    --max-heap) require_value "$1" "${2:-}"; MAX_HEAP="$2"; shift 2 ;;
    --kind) require_value "$1" "${2:-}"; KIND="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ "$REVISION" =~ ^[0-9a-f]{40}$ ]] || die "--revision must be a full 40-hex commit"
[[ -n "$STAGE" && -d "$STAGE" ]] || die "--stage must name an existing directory"
[[ -z "$(ls -A "$STAGE")" ]] || die "--stage must be empty: $STAGE"
[[ -n "$SESSION" ]] || die "--session is required"
[[ "$SESSION" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || die "--session must be an Isabelle session name (letters, digits, underscores): $SESSION"
[[ -n "$PROJECT_NAME" ]] || die "--project-name is required"
# The values go through sed and into generated text on one line.
[[ "$PROJECT_NAME" != *[$'|&\\\n']* ]] || die "--project-name must not contain |, &, a backslash or a newline"
check_descriptor_path "(init)" formal_rel "$FORMAL_REL"
check_descriptor_path "(init)" source_rel "$SOURCE_REL"
for value in "$FORMAL_REL" "$SOURCE_REL"; do
  [[ "$value" != *[$'|&\\\n']* ]] || die "paths must not contain |, &, a backslash or a newline: $value"
done
heap_to_megabytes "$MAX_HEAP" >/dev/null || die "--max-heap: cannot parse: $MAX_HEAP"
descriptor_kind_known "$KIND" || die "--kind must be one of: ${DESCRIPTOR_KINDS[*]}"
git -C "$TOOLING_ROOT" cat-file -e "$REVISION^{commit}" 2>/dev/null ||
  die "$REVISION is not a commit in $TOOLING_ROOT"
case "$KIND" in
  code) templates="" ;;
  theory)
    templates="theory/"
    git -C "$TOOLING_ROOT" cat-file -e "$REVISION:templates/theory" 2>/dev/null ||
      die "$REVISION has no templates/theory/: that revision predates theory projects"
    ;;
esac

# render TEMPLATE TARGET: the template at REVISION, placeholders substituted.
render() {
  local template="$1" target="$2"
  mkdir -p "$(dirname "$target")"
  git -C "$TOOLING_ROOT" show "$REVISION:templates/$template" >"$target.template" 2>/dev/null ||
    die "templates/$template does not exist at $REVISION"
  sed \
    -e "s|@SOURCE_REL@|$SOURCE_REL|g" \
    -e "s|@FORMAL_REL@|$FORMAL_REL|g" \
    -e "s|@TOOLING_URL@|$TOOLING_URL|g" \
    -e "s|@SESSION@|$SESSION|g" \
    -e "s|@PROJECT_NAME@|$PROJECT_NAME|g" \
    -e "s|@MAX_HEAP@|$MAX_HEAP|g" \
    -e "s|@ISABELLE_VERSION@|$ISABELLE_VERSION|g" \
    -e "s|@TOOLING_REVISION@|$REVISION|g" "$target.template" >"$target"
  rm -f -- "$target.template"
}

formal="$STAGE/$FORMAL_REL"
render "${templates}isabelle-tooling.conf" "$STAGE/$DESCRIPTOR_FILE_NAME"
render formal/ROOTS "$formal/ROOTS"
render "${templates}formal/AGENTS.md" "$formal/AGENTS.md"
render "${templates}formal/README.md" "$formal/README.md"
ln -s AGENTS.md "$formal/CLAUDE.md"
render "${templates}formal/ROOT" "$formal/$SESSION/ROOT"
render "${templates}formal/Session.thy" "$formal/$SESSION/$SESSION.thy"

# The generated descriptor must parse; fail here rather than later.
parse_descriptor "$STAGE/$DESCRIPTOR_FILE_NAME"

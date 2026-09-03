#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh disable=SC1091
source "$SCRIPT_DIR/common.sh"

CHECK_ML="$(cd "$SCRIPT_DIR/.." && pwd -P)/model-runner/export_check.ML"

usage() {
  cat <<'EOF'
Usage: export-check.sh [--project-root DIR] [--no-build] [-o OPTION]...
                       [--allow SYMBOL]... [--verbose] [--dry-run]

Check that the exported executable model is the proved one. Builds the
project's session, then loads it and audits, for every code equation of every
constant in the exported program and for every fact in the audit collection,
the oracles and axioms the derivation depends on: any oracle fails (a `sorry`
is the skip_proof oracle), and any axiom declared by a project theory fails
unless it is definitional (a definition, or a typedef's type_definition).
Axioms of theories outside the project session are the trusted baseline.
It also scans the project theories' sources: a `code_printing` naming a
symbol of the exported program, a `code_module` injection, or a
`code_reserved`, fails unless allowlisted.

Options:
  --no-build        Do not run `isabelle build` first
  -o OPTION         Extra `isabelle build` option, repeatable
  --allow SYMBOL    Accept a project-declared code_printing or code_reserved
                    for this fully qualified symbol (repeatable). Class
                    relations are written SUB<SUPER, instances TYCO::CLASS.
  --verbose         List every audited theorem
  --dry-run         Print the commands instead of running them

Descriptor keys used: build_session, session_dir, export_name, and
audit_collection (default export_audit), the named_theorems collection the
theories add their refinement theorems to; the collection must exist. Exit
status 0 when the check passes, 1 when it finds a problem.
EOF
}

case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac

{ read -r requested_root; read -r consumed; } < <(parse_project_root_option "$@")
shift "$consumed"

BUILD=true
DRY_RUN=false
VERBOSE=false
BUILD_OPTIONS=()
ALLOWLIST=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) BUILD=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    --allow) [[ -n "${2:-}" ]] || die "--allow requires an argument"; ALLOWLIST+=("$2"); shift 2 ;;
    -o) [[ -n "${2:-}" ]] || die "-o requires an argument"; BUILD_OPTIONS+=(-o "$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

resolve_project "$requested_root"
require_isabelle

SESSION="${PROJECT_CONF[build_session]}"
SESSION_PATH="$PROJECT_FORMAL_ROOT/${PROJECT_CONF[session_dir]}"
EXPORT_NAME="${PROJECT_CONF[export_name]:-}"
AUDIT_COLLECTION="${PROJECT_CONF[audit_collection]:-export_audit}"
[[ -n "$EXPORT_NAME" ]] ||
  die "$PROJECT_DESCRIPTOR: export_name is not set.
Add export_name=SESSION.THEORY:PATH as listed by 'isabelle export -l -d SESSION_DIR SESSION'."
[[ "$EXPORT_NAME" == "$SESSION".*:* ]] ||
  die "$PROJECT_DESCRIPTOR: export_name must look like $SESSION.THEORY:PATH, found: $EXPORT_NAME"
[[ -f "$CHECK_ML" ]] || die "export check ML not found: $CHECK_ML"
EXPORT_THEORY="${EXPORT_NAME%%:*}"
# The check is compiled in the export theory's ML context: the raw ML_process
# toplevel does not see the tool structures HOL loads (Code_Preproc, Typedef).
EVAL_CHECK="Context.setmp_generic_context (SOME (Context.Theory (Thy_Info.get_theory \"$EXPORT_THEORY\"))) (ML_Context.eval_file ML_Compiler.flags) (Path.explode \"$CHECK_ML\")"

run() {
  if $DRY_RUN; then
    print_command "$@"
  else
    "$@"
  fi
}

# The audit runs inside the session's heap, and Isabelle keeps no heap for a
# leaf session unless asked with -b; the first run therefore rebuilds the
# session once even when a plain `isabelle build` already passed.
if $BUILD; then
  echo "export-check: building session $SESSION (with heap image)" >&2
  run "$ISABELLE_CMD" build -b "${BUILD_OPTIONS[@]}" -D "$SESSION_PATH" >&2
fi

environment=(
  "ISABELLE_EXPORT_CHECK_SESSION=$SESSION"
  "ISABELLE_EXPORT_CHECK_EXPORT_NAME=$EXPORT_NAME"
  "ISABELLE_EXPORT_CHECK_AUDIT=$AUDIT_COLLECTION"
  "ISABELLE_EXPORT_CHECK_ALLOWLIST=${ALLOWLIST[*]}"
)
if $VERBOSE; then
  environment+=("ISABELLE_EXPORT_CHECK_VERBOSE=1")
fi

if $DRY_RUN; then
  print_command env "${environment[@]}" "$ISABELLE_CMD" ML_process -l "$SESSION" -d "$SESSION_PATH" -e "$EVAL_CHECK"
  exit 0
fi

# The check prints its verdict and exits the ML process itself on failure; an
# ML error while loading the file also fails the process, and a missing
# verdict line is treated as a failure too.
output_file="$(mktemp "${TMPDIR:-/tmp}/isabelle-export-check.XXXXXX")"
trap 'rm -f -- "$output_file"' EXIT
status=0
env "${environment[@]}" "$ISABELLE_CMD" ML_process -l "$SESSION" -d "$SESSION_PATH" -e "$EVAL_CHECK" \
  >"$output_file" 2>&1 || status=$?
grep -v '^val it = (): unit$' "$output_file" || true
if [[ "$status" -ne 0 ]]; then
  exit 1
fi
grep -q '^export check: OK' "$output_file" || {
  echo "export-check: no verdict from the check (see output above)" >&2
  exit 1
}

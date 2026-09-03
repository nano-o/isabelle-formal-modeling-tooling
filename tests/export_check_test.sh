#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test_lib.sh disable=SC1091
source "$TEST_DIR/test_lib.sh"
SCRIPT="$TEST_DIR/../scripts/export-check.sh"
CHECK_ML="$(cd "$TEST_DIR/.." && pwd -P)/model-runner/export_check.ML"

run_and_capture 2 no-export "$SCRIPT" --project-root "$PROJECT" --dry-run
assert_output_contains no-export "export_name is not set"

printf 'export_name=Test.Model:code/model.ML\n' >>"$PROJECT/isabelle-tooling.conf"

# The build saves a heap image; the check runs in the export theory's context
# with the descriptor's collection (default export_audit) and the allowlist.
run_and_capture 0 dry "$SCRIPT" --project-root "$PROJECT" --dry-run -o quick_and_dirty --allow HOL.foo --allow Test.bar
assert_output_contains dry "isabelle build -b -o quick_and_dirty -D $PROJECT/formal/Test"
assert_output_contains dry "ISABELLE_EXPORT_CHECK_SESSION=Test ISABELLE_EXPORT_CHECK_EXPORT_NAME=Test.Model:code/model.ML ISABELLE_EXPORT_CHECK_AUDIT=export_audit ISABELLE_EXPORT_CHECK_ALLOWLIST=HOL.foo\\ Test.bar"
assert_output_contains dry "ML_process -l Test -d $PROJECT/formal/Test -e "
assert_output_contains dry "Thy_Info.get_theory"
assert_output_contains dry "Test.Model"
assert_output_contains dry "$CHECK_ML"

printf 'audit_collection=refinement_facts\n' >>"$PROJECT/isabelle-tooling.conf"
run_and_capture 0 dry-collection "$SCRIPT" --project-root "$PROJECT" --dry-run --no-build --verbose
assert_output_contains dry-collection "ISABELLE_EXPORT_CHECK_AUDIT=refinement_facts"
assert_output_contains dry-collection "ISABELLE_EXPORT_CHECK_VERBOSE=1"
if grep -q "isabelle build" "$TEST_TMP_DIR/dry-collection.out"; then
  fail "--no-build still ran isabelle build"
fi

run_and_capture 2 bad-arg "$SCRIPT" --project-root "$PROJECT" --dry-run --frobnicate
assert_output_contains bad-arg "unknown argument: --frobnicate"

echo "export_check_test: ok"

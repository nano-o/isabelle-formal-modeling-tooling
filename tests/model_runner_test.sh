#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test_lib.sh disable=SC1091
source "$TEST_DIR/test_lib.sh"
SCRIPT="$TEST_DIR/../scripts/model-runner.sh"
RUNNER_ML="$(cd "$TEST_DIR/.." && pwd -P)/model-runner/runner.ML"

printf 'v1\tf\tc1\t1\n' >"$TEST_TMP_DIR/input.tsv"

# Without export_name the runner stops with the remediation.
run_and_capture 2 no-export "$SCRIPT" --project-root "$PROJECT" --dry-run batch "$TEST_TMP_DIR/input.tsv" "$TEST_TMP_DIR/out.tsv"
assert_output_contains no-export "export_name is not set"

cat >>"$PROJECT/isabelle-tooling.conf" <<'CONF'
export_name=Test.Model:code/model.ML
model_dispatch=differential/model_dispatch.ML
CONF
run_and_capture 2 no-dispatch "$SCRIPT" --project-root "$PROJECT" --dry-run batch "$TEST_TMP_DIR/input.tsv" "$TEST_TMP_DIR/out.tsv"
assert_output_contains no-dispatch "model_dispatch file not found: $PROJECT/formal/differential/model_dispatch.ML"

mkdir -p "$PROJECT/formal/differential"
: >"$PROJECT/formal/differential/model_dispatch.ML"

# Dry run, batch: build with the extra option, export, then ML_process with the
# export, the dispatch, and the runner in that order and the batch environment.
run_and_capture 0 batch-dry "$SCRIPT" --project-root "$PROJECT" --dry-run -o quick_and_dirty batch "$TEST_TMP_DIR/input.tsv" "$TEST_TMP_DIR/out.tsv"
assert_output_contains batch-dry "isabelle build -o quick_and_dirty -D $PROJECT/formal/Test"
assert_output_contains batch-dry "isabelle export -n -d $PROJECT/formal/Test -O "
assert_output_contains batch-dry "-x Test.Model:code/model.ML Test"
assert_output_contains batch-dry "env ISABELLE_MODEL_RUNNER_MODE=batch ISABELLE_MODEL_RUNNER_INPUT=$TEST_TMP_DIR/input.tsv ISABELLE_MODEL_RUNNER_OUTPUT=$TEST_TMP_DIR/out.tsv.partial."
assert_output_contains batch-dry "/export/Test.Model/code/model.ML -f $PROJECT/formal/differential/model_dispatch.ML -f $RUNNER_ML"
assert_output_contains batch-dry "ML_process -l HOL -f "

# --no-build skips the build; --logic changes the ML_process logic.
run_and_capture 0 nobuild-dry "$SCRIPT" --project-root "$PROJECT" --dry-run --no-build --logic Pure batch "$TEST_TMP_DIR/input.tsv" "$TEST_TMP_DIR/out.tsv"
if grep -q "isabelle build" "$TEST_TMP_DIR/nobuild-dry.out"; then
  fail "--no-build still ran isabelle build"
fi
assert_output_contains nobuild-dry "ML_process -l Pure -f "

# Dry run, resident: the FIFO in the work directory is the input.
run_and_capture 0 resident-dry "$SCRIPT" --project-root "$PROJECT" --dry-run --no-build resident
assert_output_contains resident-dry "env ISABELLE_MODEL_RUNNER_MODE=resident ISABELLE_MODEL_RUNNER_INPUT="
assert_output_contains resident-dry "/input.fifo "

# Argument validation.
run_and_capture 2 bad-mode "$SCRIPT" --project-root "$PROJECT" --dry-run evaluate
assert_output_contains bad-mode "unknown mode: evaluate"
run_and_capture 2 batch-args "$SCRIPT" --project-root "$PROJECT" --dry-run batch "$TEST_TMP_DIR/input.tsv"
assert_output_contains batch-args "batch takes exactly INPUT and OUTPUT"
run_and_capture 2 missing-input "$SCRIPT" --project-root "$PROJECT" --dry-run batch "$TEST_TMP_DIR/absent.tsv" "$TEST_TMP_DIR/out.tsv"
assert_output_contains missing-input "input file not found"
sed -i 's/^export_name=.*/export_name=Other.Model:code\/model.ML/' "$PROJECT/isabelle-tooling.conf"
run_and_capture 2 wrong-session "$SCRIPT" --project-root "$PROJECT" --dry-run batch "$TEST_TMP_DIR/input.tsv" "$TEST_TMP_DIR/out.tsv"
assert_output_contains wrong-session "export_name must belong to session Test"

echo "model_runner_test: ok"

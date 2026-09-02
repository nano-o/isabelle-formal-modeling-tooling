#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test_lib.sh disable=SC1091
source "$TEST_DIR/test_lib.sh"
SCRIPT="$TEST_DIR/../scripts/ic2.sh"
printf 'running\n' >"$MOCK_ISABELLE_STATE_DIR/server"

# Commands run from the session directory, against the derived server name.
expected_name="$(cd "$PROJECT" && "$SCRIPT" name)"
[[ "$expected_name" == ic2-project-* ]] || fail "derived name: $expected_name"
run_and_capture 0 check-submit env -C "$PROJECT/formal/Test" "$SCRIPT" check Test/Foo.thy --command-timeout 15
assert_output_contains check-submit "mock ic2: check -n $expected_name Test/Foo.thy --command-timeout 15 (cwd $PROJECT/formal)"
run_and_capture 0 dry-run "$SCRIPT" --project-root "$PROJECT" --dry-run query sorry Test/Foo.thy --json
assert_output_contains dry-run "cd $PROJECT/formal && isabelle ic2 query sorry Test/Foo.thy --json -n $expected_name"

for state in ok failed idle; do
  expected_rc=1
  [[ "$state" == "ok" ]] && expected_rc=0
  status_file="$TEST_TMP_DIR/$state.status"
  printf '%s 20ms\n' "$state" >"$status_file"
  run_and_capture "$expected_rc" "wait-$state" env MOCK_STATUS_SEQUENCE_FILE="$status_file" \
    "$SCRIPT" --project-root "$PROJECT" wait --interval 0
  assert_output_contains "wait-$state" "$state 20ms"
done

status_file="$TEST_TMP_DIR/transient-empty.status"
printf '<EMPTY>\nrunning 10ms\nok 20ms\n' >"$status_file"
run_and_capture 0 wait-transient-empty env MOCK_STATUS_SEQUENCE_FILE="$status_file" \
  "$SCRIPT" --project-root "$PROJECT" wait --interval 0
assert_output_contains wait-transient-empty "ok 20ms"
[[ "$(grep -Fc -- "ok 20ms" "$TEST_TMP_DIR/wait-transient-empty.out")" -eq 1 ]] ||
  fail "wait-transient-empty: final status was not printed exactly once"

status_file="$TEST_TMP_DIR/timeout.status"
printf 'running 10ms\nrunning 20ms\n' >"$status_file"
run_and_capture 124 wait-timeout env MOCK_STATUS_SEQUENCE_FILE="$status_file" \
  "$SCRIPT" --project-root "$PROJECT" wait --interval 1 --timeout 1
assert_output_contains wait-timeout "timeout: check did not reach ok/failed/idle within 1s"

# Liveness fallback: the server pid is this test shell, whose only descendants
# are not Poly/ML, so running work with no prover is flagged. A pid with no
# visible process table entry is inconclusive and passes through.
run_and_capture 1 dead-prover env MOCK_STATUS_OUTPUT="running 100ms  theories=Test" MOCK_SERVER_PID=$$ \
  "$SCRIPT" --project-root "$PROJECT" check status
assert_output_contains dead-prover "warning: prover process not found"
run_and_capture 0 invisible-prover env MOCK_STATUS_OUTPUT="running 100ms  theories=Test" MOCK_SERVER_PID=4194304 \
  "$SCRIPT" --project-root "$PROJECT" check status
run_and_capture 1 dead-prover-server env MOCK_SERVER_STATUS_OUTPUT="m: state=ready session=HOL pid=$$ busy(1 check)" \
  "$SCRIPT" --project-root "$PROJECT" server status
assert_output_contains dead-prover-server "warning: prover process not found"

run_and_capture 0 health env MOCK_SERVER_PID=$$ "$SCRIPT" --project-root "$PROJECT" health
assert_output_contains health "RSS(MiB)"
assert_output_contains health "total"

echo "ic2.sh tests passed"

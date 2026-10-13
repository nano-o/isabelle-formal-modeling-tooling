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

# Roles. preflight passes only in a checkout marked as an ic2 worktree that
# no running jEdit owns, whatever the repository's layout; marking leaves the
# working tree clean.
run_and_capture 1 preflight-no-git "$SCRIPT" --project-root "$PROJECT" preflight
assert_output_contains preflight-no-git "$PROJECT is not a Git checkout"

repo="$TEST_TMP_DIR/repo"
git_project "$repo"
run_and_capture 1 preflight-main "$SCRIPT" --project-root "$repo" preflight
assert_output_contains preflight-main "is not marked as an ic2 worktree"
git -C "$repo" worktree add -q -b plain "$TEST_TMP_DIR/plain"
run_and_capture 1 preflight-unmarked-linked "$SCRIPT" --project-root "$TEST_TMP_DIR/plain" preflight
run_and_capture 0 mark-linked "$SCRIPT" --project-root "$TEST_TMP_DIR/plain" worktree mark
run_and_capture 0 preflight-marked-linked "$SCRIPT" --project-root "$TEST_TMP_DIR/plain" preflight
run_and_capture 0 unmark-linked "$SCRIPT" --project-root "$TEST_TMP_DIR/plain" worktree unmark
run_and_capture 1 preflight-unmarked-again "$SCRIPT" --project-root "$TEST_TMP_DIR/plain" preflight
# A relative PATH is relative to the current directory, as for git.
run_and_capture 0 worktree-add env -C "$repo/formal" "$SCRIPT" worktree add ../../proof -b proof
assert_output_contains worktree-add "Marked as an ic2 worktree: $TEST_TMP_DIR/proof"
run_and_capture 0 preflight-added "$SCRIPT" --project-root "$TEST_TMP_DIR/proof" preflight
assert_output_contains preflight-added "preflight: ok: $TEST_TMP_DIR/proof is an ic2 worktree"
run_and_capture 1 preflight-main-after "$SCRIPT" --project-root "$repo" preflight
for checkout in "$repo" "$TEST_TMP_DIR/plain" "$TEST_TMP_DIR/proof"; do
  [[ -z "$(git -C "$checkout" status --porcelain)" ]] || fail "marking left $checkout dirty"
done

# The `.bare` layout: every checkout, main included, is a linked worktree.
bare="$TEST_TMP_DIR/bare-project"
mkdir "$bare"
git clone -q --bare "$repo" "$bare/.bare"
printf 'gitdir: ./.bare\n' >"$bare/.git"
git -C "$bare" worktree add -q "$bare/main" main
run_and_capture 1 bare-preflight-main "$SCRIPT" --project-root "$bare/main" preflight
assert_output_contains bare-preflight-main "is not marked as an ic2 worktree"
run_and_capture 0 bare-worktree-add env -C "$bare/main" "$SCRIPT" worktree add ../proof -b bare-proof
run_and_capture 0 bare-preflight-added "$SCRIPT" --project-root "$bare/proof" preflight
run_and_capture 1 bare-preflight-main-after "$SCRIPT" --project-root "$bare/main" preflight

# A marked worktree that a running jEdit owns. The jEdit record's lock is
# held here the way launch_jedit.sh leaves it to jEdit: preflight, start and
# check refuse while it is held, and pass once it is not.
proof="$TEST_TMP_DIR/proof"
record="$(git -C "$proof" rev-parse --path-format=absolute --git-path isabelle-tooling/jedit)"
printf 'pid=12345\nroot=%s\n' "$proof/formal" >"$record"
held="$TEST_TMP_DIR/jedit-held"
: >"$held"
(exec 9<>"$record"; flock 9; printf 'locked\n' >"$held"; while [[ -e "$held" ]]; do sleep 0.1; done) &
holder=$!
wait_for_line "$held" '^locked$'
run_and_capture 1 preflight-jedit "$SCRIPT" --project-root "$proof" preflight
assert_output_contains preflight-jedit "jEdit owns $proof (pid 12345, write root $proof/formal)"
run_and_capture 2 start-jedit "$SCRIPT" --project-root "$proof" --dry-run start
assert_output_contains start-jedit "jEdit owns $proof (pid 12345, write root $proof/formal)"
run_and_capture 2 check-jedit "$SCRIPT" --project-root "$proof" check Test/Foo.thy
assert_output_contains check-jedit "jEdit owns $proof"
run_and_capture 0 check-status-jedit "$SCRIPT" --project-root "$proof" check status
rm "$held"
wait "$holder"
run_and_capture 0 preflight-jedit-gone "$SCRIPT" --project-root "$proof" preflight
run_and_capture 0 start-jedit-gone "$SCRIPT" --project-root "$proof" --dry-run start
run_and_capture 0 check-jedit-gone "$SCRIPT" --project-root "$proof" check Test/Foo.thy
assert_output_contains check-jedit-gone "mock ic2: check -n"

echo "ic2.sh tests passed"

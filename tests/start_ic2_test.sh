#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test_lib.sh disable=SC1091
source "$TEST_DIR/test_lib.sh"
SCRIPT="$TEST_DIR/../scripts/ic2.sh"
name="$(cd "$PROJECT" && "$SCRIPT" name)"

# Dry run: the descriptor's session directory, base session, heap bound, and
# the derived name reach `server start`; the heap bound is a systemd scope.
run_and_capture 0 start-dry "$SCRIPT" --project-root "$PROJECT" --dry-run start --cpus 4
assert_output_contains start-dry "Session dir:  $PROJECT/formal"
assert_output_contains start-dry "Session:      HOL"
assert_output_contains start-dry "Server:       $name"
assert_output_contains start-dry "Memory bound: 2048M (systemd user scope)"
assert_output_contains start-dry "isabelle ic2 server start --daemon -n $name -l HOL -d $PROJECT/formal -o document_variants= -o process_policy=systemd-run\\ --user\\ --scope\\ -q\\ -p\\ MemoryMax=2048M\\ -p\\ MemorySwapMax=0 -o threads=4"
run_and_capture 2 start-fixed "$SCRIPT" --project-root "$PROJECT" start --session Other
assert_output_contains start-fixed "--session is fixed by the project descriptor"

# Real lifecycle against the mock: start, already-running is success, stop,
# stopping a stopped server is success.
run_and_capture 0 start-1 "$SCRIPT" --project-root "$PROJECT" start --no-memory-bound
assert_output_contains start-1 "Started server: $name"
run_and_capture 0 start-2 "$SCRIPT" --project-root "$PROJECT" start
assert_output_contains start-2 "Already running: mock: state=ready"
run_and_capture 0 stop-1 "$SCRIPT" --project-root "$PROJECT" stop --remove
assert_output_contains stop-1 "Stopped: $name"
run_and_capture 0 stop-2 "$SCRIPT" --project-root "$PROJECT" stop
assert_output_contains stop-2 "Not running: $name"
[[ "$(paste -sd' ' "$MOCK_ISABELLE_STATE_DIR/lifecycle")" == "start stop" ]] ||
  fail "lifecycle: $(paste -sd' ' "$MOCK_ISABELLE_STATE_DIR/lifecycle")"
grep -q -- "server start --daemon -n $name -l HOL -d $PROJECT/formal -o document_variants=$" "$MOCK_ISABELLE_LOG" ||
  fail "start without a memory bound passed unexpected arguments: $(grep 'server start' "$MOCK_ISABELLE_LOG")"

# A server started from a different directory but the same name is the same server.
printf 'running\n' >"$MOCK_ISABELLE_STATE_DIR/server"
run_and_capture 0 start-3 env -C "$PROJECT/formal/Test" "$SCRIPT" start
assert_output_contains start-3 "Already running"

echo "start-ic2.sh tests passed"

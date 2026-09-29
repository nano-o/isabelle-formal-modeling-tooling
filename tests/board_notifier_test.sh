#!/usr/bin/env bash
set -euo pipefail

# The optional agent-board notifier in ic2.sh, against a stub executable: it
# runs only when agent-board.conf is at the checkout root and the executable
# resolves, never on a dry run, never changes the ic2 result, and waits at
# most five seconds for a board command that blocks, as `post` does while
# another process holds the board's lock.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test_lib.sh disable=SC1091
source "$TEST_DIR/test_lib.sh"
SCRIPT="$TEST_DIR/../scripts/ic2.sh"
name="$(cd "$PROJECT" && "$SCRIPT" name)"
unset AGENT_BOARD_COMMAND AGENT_BOARD_AGENT AGENT_BOARD_DIR

STUB_DIR="$TEST_TMP_DIR/stub-bin"
STUB="$STUB_DIR/agent-board"
CALLS="$TEST_TMP_DIR/board-calls"
mkdir -p "$STUB_DIR"
cat >"$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_CALLS"
echo "stub board noise" >&2
[[ -z "${STUB_SLEEP:-}" ]] || exec sleep "$STUB_SLEEP"
exit "${STUB_RC:-0}"
STUB_EOF
chmod +x "$STUB"
export STUB_CALLS="$CALLS"
# A PATH without any agent-board: the mock isabelle and the usual tools.
BASE_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r dir; do
  [[ -x "$dir/agent-board" ]] || printf '%s:' "$dir"; done)"
export PATH="${BASE_PATH%:}"

calls() { if [[ -f "$CALLS" ]]; then wc -l <"$CALLS"; else echo 0; fi; }
lifecycle() {
  local label="$1"
  shift
  run_and_capture 0 "$label-start" env "$@" "$SCRIPT" --project-root "$PROJECT" start --no-memory-bound
  assert_output_contains "$label-start" "Started server: $name"
  run_and_capture 0 "$label-stop" env "$@" "$SCRIPT" --project-root "$PROJECT" stop
  assert_output_contains "$label-stop" "Stopped: $name"
}

# Not configured: the executable is never called, even when it resolves.
lifecycle unconfigured AGENT_BOARD_COMMAND="$STUB"
[[ "$(calls)" -eq 0 ]] || fail "the notifier ran without agent-board.conf"

printf 'format_version=1\nboard_revision=%040d\n' 0 >"$PROJECT/agent-board.conf"

# Configured but unresolved, or resolved from a relative or missing path.
lifecycle unresolved
lifecycle relative AGENT_BOARD_COMMAND=stub-bin/agent-board
lifecycle missing AGENT_BOARD_COMMAND="$TEST_TMP_DIR/nothing"
[[ "$(calls)" -eq 0 ]] || fail "the notifier ran without a resolvable executable"

# Dry runs post nothing.
run_and_capture 0 dry-start env AGENT_BOARD_COMMAND="$STUB" "$SCRIPT" --project-root "$PROJECT" --dry-run start
[[ "$(calls)" -eq 0 ]] || fail "a dry run posted a note"

# Resolved through AGENT_BOARD_COMMAND, then through PATH: one note per action,
# with the checkout, --if-board and the ic2 handle; stub stderr is discarded.
lifecycle command AGENT_BOARD_COMMAND="$STUB"
expected_start="--project-root $PROJECT --if-board --as ic2 post --kind note ic2 server $name starting for $PROJECT"
expected_stop="--project-root $PROJECT --if-board --as ic2 post --kind note ic2 server $name stopping for $PROJECT"
[[ "$(sed -n 1p "$CALLS")" == "$expected_start" ]] || fail "start note: $(sed -n 1p "$CALLS")"
[[ "$(sed -n 2p "$CALLS")" == "$expected_stop" ]] || fail "stop note: $(sed -n 2p "$CALLS")"
if grep -Fq "stub board noise" "$TEST_TMP_DIR/command-start.out"; then fail "stub stderr reached the output"; fi
lifecycle on-path PATH="$STUB_DIR:$PATH"
[[ "$(calls)" -eq 4 ]] || fail "PATH resolution: $(calls) calls"

# A failing board command does not change the result.
lifecycle failing AGENT_BOARD_COMMAND="$STUB" STUB_RC=2

# A blocked board command delays the action by at most five seconds.
started=$(date +%s%N)
run_and_capture 0 blocked-start env AGENT_BOARD_COMMAND="$STUB" STUB_SLEEP=30 \
  "$SCRIPT" --project-root "$PROJECT" start --no-memory-bound
elapsed_ms=$((($(date +%s%N) - started) / 1000000))
assert_output_contains blocked-start "Started server: $name"
((elapsed_ms >= 4500 && elapsed_ms < 8000)) || fail "blocked note took ${elapsed_ms} ms"
run_and_capture 0 blocked-cleanup "$SCRIPT" --project-root "$PROJECT" stop

echo "board notifier tests passed"

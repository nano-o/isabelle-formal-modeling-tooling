#!/usr/bin/env bash
set -euo pipefail

# launch_jedit.sh and ic2 keep out of each other's checkout: the launcher
# refuses while the checkout's ic2 server runs, and the jEdit it records makes
# ic2 refuse until that jEdit exits. The mock `isabelle jedit` stays up while
# MOCK_JEDIT_UNTIL names an existing file.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test_lib.sh disable=SC1091
source "$TEST_DIR/test_lib.sh"
SCRIPT="$TEST_DIR/../scripts/launch_jedit.sh"
IC2="$TEST_DIR/../scripts/ic2.sh"

repo="$TEST_TMP_DIR/repo"
worktree="$TEST_TMP_DIR/proof"
git_project "$repo"
"$IC2" --project-root "$repo" worktree add "$worktree" -b proof >/dev/null 2>&1
record="$(git -C "$worktree" rev-parse --path-format=absolute --git-path isabelle-tooling/jedit)"

# What the launcher checks before it starts jEdit: a token file, an I/R
# directory and a virtual environment.
token="$TEST_TMP_DIR/token"
printf 'test-token\n' >"$token"
chmod 600 "$token"
mkdir -p "$TEST_TMP_DIR/ir" "$TEST_TMP_DIR/venv/bin"
: >"$TEST_TMP_DIR/ir/repl.py"
ln -s "$(command -v python3)" "$TEST_TMP_DIR/venv/bin/python3"
inputs=(--isabelle "$TEST_TMP_DIR/bin/isabelle" --ir-home "$TEST_TMP_DIR/ir"
  --venv "$TEST_TMP_DIR/venv" --token-file "$token")
launch=("$SCRIPT" --project "$worktree/formal" "${inputs[@]}")

# Outside Git there is nothing to record.
run_and_capture 0 no-git "$SCRIPT" --project "$PROJECT/formal" "${inputs[@]}" --dry-run
assert_output_contains no-git "jEdit record:    (none: not in a Git checkout)"

# The worktree's ic2 server is running: refuse, and say how to stop it.
printf 'running\n' >"$MOCK_ISABELLE_STATE_DIR/server"
run_and_capture 2 server-running "${launch[@]}"
assert_output_contains server-running "this checkout's ic2 server is running: $("$IC2" --project-root "$worktree" name)"
assert_output_contains server-running "ic2.sh --project-root $worktree stop"
if grep -q '^jedit' "$MOCK_ISABELLE_LOG"; then
  fail "jEdit started beside a running ic2 server"
fi
rm "$MOCK_ISABELLE_STATE_DIR/server"

# A dry run names the record without writing it.
run_and_capture 0 dry-run "${launch[@]}" --dry-run
assert_output_contains dry-run "jEdit record:    $record"
[[ ! -e "$record" ]] || fail "a dry run wrote the jEdit record"

# The server has stopped: jEdit launches in the marked worktree and records
# its pid and write root.
open="$TEST_TMP_DIR/jedit-open"
: >"$open"
MOCK_JEDIT_UNTIL="$open" "${launch[@]}" >"$TEST_TMP_DIR/launch.out" 2>&1 &
jedit_pid=$!
wait_for_line "$record" '^root='
grep -Fqx "pid=$jedit_pid" "$record" || fail "jEdit record pid: $(cat "$record")"
grep -Fqx "root=$worktree/formal" "$record" || fail "jEdit record root: $(cat "$record")"

# While it runs, ic2 refuses the worktree, and so does a second launch.
run_and_capture 1 preflight-open "$IC2" --project-root "$worktree" preflight
assert_output_contains preflight-open "jEdit owns $worktree (pid $jedit_pid, write root $worktree/formal)"
run_and_capture 2 start-open "$IC2" --project-root "$worktree" --dry-run start
assert_output_contains start-open "jEdit owns $worktree"
run_and_capture 2 second-launch "${launch[@]}"
assert_output_contains second-launch "a jEdit launched on this checkout is still running (pid $jedit_pid"

# Once it exits, ic2 may work there again; the stale record stays behind.
rm "$open"
wait "$jedit_pid" || fail "launch: $(cat "$TEST_TMP_DIR/launch.out")"
assert_output_contains launch "mock jedit: jedit"
[[ -f "$record" ]] || fail "the jEdit record is gone"
run_and_capture 0 preflight-closed "$IC2" --project-root "$worktree" preflight
run_and_capture 0 start-closed "$IC2" --project-root "$worktree" --dry-run start

echo "launch_jedit.sh tests passed"

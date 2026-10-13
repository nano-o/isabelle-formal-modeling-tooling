#!/usr/bin/env bash
# Shared setup for the wrapper tests: a temporary project with a descriptor and
# a mock `isabelle` first on PATH.

TEST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEST_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/isabelle-tooling-test.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_DIR"' EXIT
TEST_TMP_DIR="$(cd "$TEST_TMP_DIR" && pwd -P)"

mkdir -p "$TEST_TMP_DIR/bin" "$TEST_TMP_DIR/state" "$TEST_TMP_DIR/project/formal/Test"
cp "$TEST_LIB_DIR/fixtures/isabelle" "$TEST_TMP_DIR/bin/isabelle"
chmod +x "$TEST_TMP_DIR/bin/isabelle"
: >"$TEST_TMP_DIR/project/formal/ROOT"
cat >"$TEST_TMP_DIR/project/isabelle-tooling.conf" <<'EOF'
format_version=1
source_rel=.
formal_rel=formal
build_session=Test
session_dir=Test
ic2_base_session=HOL
ic2_max_heap=2G
isabelle_version=Isabelle2025-2
EOF
# shellcheck disable=SC2034
PROJECT="$TEST_TMP_DIR/project"

export PATH="$TEST_TMP_DIR/bin:$PATH"
export MOCK_ISABELLE_STATE_DIR="$TEST_TMP_DIR/state"
export MOCK_ISABELLE_LOG="$TEST_TMP_DIR/isabelle.log"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_and_capture() {
  local expected_rc="$1"
  local name="$2"
  shift 2
  local output_file="$TEST_TMP_DIR/$name.out"
  local actual_rc
  if "$@" >"$output_file" 2>&1; then
    actual_rc=0
  else
    actual_rc=$?
  fi
  if [[ "$actual_rc" -ne "$expected_rc" ]]; then
    echo "FAIL: $name: expected rc=$expected_rc, found rc=$actual_rc" >&2
    sed -n '1,120p' "$output_file" >&2
    return 1
  fi
}

assert_output_contains() {
  local name="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$TEST_TMP_DIR/$name.out"; then
    echo "FAIL: $name: output did not contain: $expected" >&2
    sed -n '1,120p' "$TEST_TMP_DIR/$name.out" >&2
    return 1
  fi
}

# git_project DIR: a Git repository at DIR holding a copy of the test project,
# committed on main, with Git isolated from the user's configuration.
git_project() {
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
  cp -R "$PROJECT" "$1"
  git -C "$1" init -q -b main
  git -C "$1" add -A
  git -C "$1" commit -qm "test project"
}

# wait_for_line FILE PATTERN: wait up to ten seconds for a line of FILE to
# match the extended regular expression PATTERN.
wait_for_line() {
  local _
  for _ in $(seq 100); do
    grep -Eq -- "$2" "$1" 2>/dev/null && return 0
    sleep 0.1
  done
  fail "no line matching $2 in $1"
}

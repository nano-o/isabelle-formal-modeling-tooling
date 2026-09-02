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

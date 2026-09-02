#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../scripts/common.sh disable=SC1091
source "$TEST_DIR/../scripts/common.sh"
SCRIPT="$TEST_DIR/../scripts/new-project.sh"

TEST_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/isabelle-tooling-newproject.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

checkout="$TEST_TMP_DIR/my project"
mkdir -p "$checkout"
"$SCRIPT" --checkout "$checkout" --session Demo_Session >/dev/null

for f in isabelle-tooling.conf formal/ROOTS formal/AGENTS.md formal/README.md formal/Demo_Session/ROOT formal/Demo_Session/Demo_Session.thy; do
  [[ -f "$checkout/$f" ]] || fail "missing $f"
done
[[ "$(readlink "$checkout/formal/CLAUDE.md")" == "AGENTS.md" ]] || fail "CLAUDE.md is not a symlink to AGENTS.md"
grep -q '@' "$checkout/isabelle-tooling.conf" && fail "unsubstituted placeholder in the descriptor"
grep -rq '@[A-Z_]*@' "$checkout/formal" && fail "unsubstituted placeholder under formal/"
grep -q '^session Demo_Session = HOL +' "$checkout/formal/Demo_Session/ROOT" || fail "ROOT session line"
grep -q '^theory Demo_Session$' "$checkout/formal/Demo_Session/Demo_Session.thy" || fail "theory name"

(cd "$checkout/formal" && resolve_project "" &&
  [[ "${PROJECT_CONF[build_session]}" == Demo_Session ]] &&
  [[ "${PROJECT_CONF[tooling_revision]}" == "$(git -C "$TOOLING_ROOT" rev-parse HEAD)" ]] &&
  [[ "$PROJECT_FORMAL_ROOT" == "$checkout/formal" ]]) || fail "generated descriptor does not resolve"

# Never overwrites.
if "$SCRIPT" --checkout "$checkout" --session Demo_Session >/dev/null 2>&1; then
  fail "second run overwrote files"
fi

# Layout C: formal at the top, code in X.
assurance="$TEST_TMP_DIR/assurance"
mkdir -p "$assurance/X"
"$SCRIPT" --checkout "$assurance" --session Model --formal-rel . --source-rel X --project-name "The X project" >/dev/null
[[ -f "$assurance/Model/ROOT" && -f "$assurance/AGENTS.md" ]] || fail "layout C files"
grep -q '^source_rel=X$' "$assurance/isabelle-tooling.conf" || fail "layout C source_rel"
grep -q 'The X project' "$assurance/README.md" || fail "project name substitution"

# Rejections.
"$SCRIPT" --checkout "$TEST_TMP_DIR" --session 'bad name' >/dev/null 2>&1 && fail "bad session name accepted"
"$SCRIPT" --checkout "$TEST_TMP_DIR" --session Ok --formal-rel ../up >/dev/null 2>&1 && fail "escaping formal_rel accepted"
"$SCRIPT" --checkout "$TEST_TMP_DIR/does-not-exist" --session Ok >/dev/null 2>&1 && fail "missing checkout accepted"

echo "new-project.sh tests passed"

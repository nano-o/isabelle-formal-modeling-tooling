#!/usr/bin/env bash
# Needs a real Isabelle: builds the four fixture sessions and checks the verdicts.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$TEST_DIR/../.." && pwd -P)"
SCRIPT="$ROOT/scripts/export-check.sh"
FIXTURES="$ROOT/tests/fixtures/export-check"
OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/isabelle-export-check-test.XXXXXX")"
trap 'rm -rf -- "$OUT_DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

expect() {
  local fixture="$1" expected_rc="$2" needle="$3"
  local rc=0
  "$SCRIPT" --project-root "$FIXTURES/$fixture" >"$OUT_DIR/$fixture.out" 2>&1 || rc=$?
  [[ "$rc" -eq "$expected_rc" ]] ||
    { sed -n '1,60p' "$OUT_DIR/$fixture.out" >&2; fail "$fixture: expected rc=$expected_rc, found rc=$rc"; }
  grep -Fq -- "$needle" "$OUT_DIR/$fixture.out" ||
    { sed -n '1,60p' "$OUT_DIR/$fixture.out" >&2; fail "$fixture: output lacks: $needle"; }
  echo "export_check_test: $fixture ok"
}

expect clean 0 "export check: OK"
expect printing 1 "code_printing overrides constant Fixture.succ_bounded of the exported program"
expect oracle 1 "code equation of Fixture.succ_bounded: depends on oracle Fixture.trust_me"
expect axiom 1 "depends on unjustified axiom Base.shift_axiom"

# The allowlist accepts exactly the named symbol.
rc=0
"$SCRIPT" --project-root "$FIXTURES/printing" --no-build --allow Fixture.succ_bounded >"$OUT_DIR/allow.out" 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || { sed -n '1,60p' "$OUT_DIR/allow.out" >&2; fail "allowlisted printing fixture should pass"; }
echo "export_check_test: allowlist ok"

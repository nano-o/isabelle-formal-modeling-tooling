#!/usr/bin/env bash
# Needs a real Isabelle: batch and resident modes on the clean fixture.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$TEST_DIR/../.." && pwd -P)"
SCRIPT="$ROOT/scripts/model-runner.sh"
FIXTURE="$ROOT/tests/fixtures/export-check/clean"
OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/isabelle-model-runner-test.XXXXXX")"
trap 'rm -rf -- "$OUT_DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Batch: comments echoed, rows suffixed, output installed atomically.
printf '# corpus\nv1\tsucc_bounded\tc1\t41\n\nv1\tsucc_bounded\tc2\t1000\n' >"$OUT_DIR/input.tsv"
"$SCRIPT" --project-root "$FIXTURE" batch "$OUT_DIR/input.tsv" "$OUT_DIR/output.tsv" >"$OUT_DIR/batch.log" 2>&1 ||
  { cat "$OUT_DIR/batch.log" >&2; fail "batch run failed"; }
printf '# corpus\nv1\tsucc_bounded\tc1\t41\tOK\t42\n\nv1\tsucc_bounded\tc2\t1000\tOK\t1000\n' >"$OUT_DIR/expected.tsv"
cmp "$OUT_DIR/expected.tsv" "$OUT_DIR/output.tsv" || fail "batch output differs from the expected rows"
echo "model_runner_test: batch ok"

# Batch fails closed on a rejected record and leaves no output behind.
printf 'v1\tsucc_bounded\tc1\t41\nv1\tsucc_bounded\tc2\t-1\n' >"$OUT_DIR/bad.tsv"
rc=0
"$SCRIPT" --project-root "$FIXTURE" --no-build batch "$OUT_DIR/bad.tsv" "$OUT_DIR/bad-out.tsv" >"$OUT_DIR/bad.log" 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "batch accepted a rejected record"
grep -q "line 2: rejected record: negative nat: -1" "$OUT_DIR/bad.log" || { cat "$OUT_DIR/bad.log" >&2; fail "reject message missing"; }
[[ ! -e "$OUT_DIR/bad-out.tsv" ]] || fail "batch installed an output after a rejection"
ls "$OUT_DIR"/bad-out.tsv.partial.* 2>/dev/null && fail "partial output left behind"
echo "model_runner_test: batch reject ok"

# Resident: one answer per input line after #ready, including reject, error, blank.
printf 'v1\tsucc_bounded\tc1\t41\n# note\n\nv1\tsucc_bounded\tc3\t-5\nv1\tbogus\tc4\t1\nv1\tcrash\tc5\t1\nv1\tsucc_bounded\tc6\t7\n' |
  "$SCRIPT" --project-root "$FIXTURE" --no-build resident 2>"$OUT_DIR/resident.err" |
  sed -n '/^#ready$/,$p' | sed '/^structure Model_Runner/,$d' >"$OUT_DIR/resident.out" ||
  { cat "$OUT_DIR/resident.err" >&2; fail "resident run failed"; }
printf '#ready\nv1\tsucc_bounded\tc1\t41\tOK\t42\n# note\n#\n#reject\t4\tnegative nat: -5\n#reject\t5\tunknown tag: bogus\n#error\t6\tFail "deliberate dispatch crash"\nv1\tsucc_bounded\tc6\t7\tOK\t8\n' >"$OUT_DIR/resident.expected"
cmp "$OUT_DIR/resident.expected" "$OUT_DIR/resident.out" || { cat -A "$OUT_DIR/resident.out" >&2; fail "resident answers differ"; }
echo "model_runner_test: resident ok"

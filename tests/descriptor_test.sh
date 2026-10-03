#!/usr/bin/env bash
set -euo pipefail

# Tests for the project descriptor parser, the checkout resolver, and the
# per-checkout server-name derivation in common.sh, plus the project wrapper
# on top of them.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../scripts/common.sh disable=SC1091
source "$TEST_DIR/../scripts/common.sh"
WRAPPER="$TEST_DIR/../scripts/ic2.sh"

TEST_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ic2-descriptor-test.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_DIR"' EXIT
TEST_TMP_DIR="$(canonical_dir "$TEST_TMP_DIR")"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# write_descriptor DIR [EXTRA_LINES...]: a valid layout-A/B descriptor with
# formal_rel=formal, followed by any extra lines verbatim.
write_descriptor() {
  local dir="$1"
  shift
  mkdir -p "$dir/formal"
  : >"$dir/formal/ROOT"
  {
    printf '# test descriptor\n'
    printf 'format_version=1\n'
    printf 'source_rel=.\n'
    printf 'formal_rel=formal\n'
    printf 'build_session=Test\n'
    printf 'session_dir=Test\n'
    printf 'ic2_base_session=HOL\n'
    printf 'isabelle_version=Isabelle2025-2\n'
    printf '%s\n' "$@"
  } >"$dir/$DESCRIPTOR_FILE_NAME"
}

# expect_reject NAME FILE PATTERN: parsing FILE must fail with PATTERN in the
# error text.
expect_reject() {
  local name="$1"
  local file="$2"
  local pattern="$3"
  local output
  if output="$(parse_descriptor "$file" 2>&1)"; then
    fail "$name: descriptor was accepted"
  fi
  [[ "$output" == *"$pattern"* ]] ||
    fail "$name: error did not mention '$pattern': $output"
}

# --- parser ---------------------------------------------------------------

valid="$TEST_TMP_DIR/valid"
write_descriptor "$valid" 'ic2_max_heap=12G' 'export_name=Test.Iface:code/x.ML'
parse_descriptor "$valid/$DESCRIPTOR_FILE_NAME"
[[ "${PROJECT_CONF[build_session]}" == "Test" ]] || fail "valid: build_session"
[[ "${PROJECT_CONF[export_name]}" == "Test.Iface:code/x.ML" ]] ||
  fail "valid: value after first '=' must be kept whole"
[[ -z "${PROJECT_CONF[tooling_revision]+set}" ]] || fail "valid: unset optional key present"

# Values are data: shell syntax must survive literally and never execute.
inject="$TEST_TMP_DIR/inject"
marker="$TEST_TMP_DIR/injection-ran"
write_descriptor "$inject" "export_name=\$(touch '$marker') \`touch '$marker'\` \$HOME ; touch '$marker'"
parse_descriptor "$inject/$DESCRIPTOR_FILE_NAME"
[[ ! -e "$marker" ]] || fail "inject: a descriptor value was executed"
[[ "${PROJECT_CONF[export_name]}" == "\$(touch '$marker') \`touch '$marker'\` \$HOME ; touch '$marker'" ]] ||
  fail "inject: value was not preserved literally"

bad="$TEST_TMP_DIR/bad"
mkdir -p "$bad"
write_descriptor "$bad/duplicate" 'build_session=Again'
expect_reject duplicate "$bad/duplicate/$DESCRIPTOR_FILE_NAME" "duplicate key: build_session"
write_descriptor "$bad/unknown" 'colour=blue'
expect_reject unknown "$bad/unknown/$DESCRIPTOR_FILE_NAME" "unknown key: colour"
mkdir -p "$bad/missing"
grep -v '^isabelle_version=' "$valid/$DESCRIPTOR_FILE_NAME" >"$bad/missing/$DESCRIPTOR_FILE_NAME"
expect_reject missing "$bad/missing/$DESCRIPTOR_FILE_NAME" "missing required key: isabelle_version"
mkdir -p "$bad/version"
sed 's/^format_version=1$/format_version=2/' "$valid/$DESCRIPTOR_FILE_NAME" >"$bad/version/$DESCRIPTOR_FILE_NAME"
expect_reject version "$bad/version/$DESCRIPTOR_FILE_NAME" "unsupported format_version: 2"
mkdir -p "$bad/absolute"
sed 's|^formal_rel=formal$|formal_rel=/etc|' "$valid/$DESCRIPTOR_FILE_NAME" >"$bad/absolute/$DESCRIPTOR_FILE_NAME"
expect_reject absolute "$bad/absolute/$DESCRIPTOR_FILE_NAME" "formal_rel must be relative"
mkdir -p "$bad/dotdot"
sed 's|^source_rel=.$|source_rel=../elsewhere|' "$valid/$DESCRIPTOR_FILE_NAME" >"$bad/dotdot/$DESCRIPTOR_FILE_NAME"
expect_reject dotdot "$bad/dotdot/$DESCRIPTOR_FILE_NAME" "must not contain a '..' component"
write_descriptor "$bad/dotdot-nested" 'model_dispatch=differential/../../x.ML'
expect_reject dotdot-nested "$bad/dotdot-nested/$DESCRIPTOR_FILE_NAME" "must not contain a '..' component"
write_descriptor "$bad/noequals" 'just some words'
expect_reject noequals "$bad/noequals/$DESCRIPTOR_FILE_NAME" "expected key=value"
write_descriptor "$bad/badkey" 'Build-Session=x'
expect_reject badkey "$bad/badkey/$DESCRIPTOR_FILE_NAME" "malformed key"
expect_reject nofile "$bad/does-not-exist" "descriptor not found"

# model_kind: code or theory, absent meaning code; the differential keys are
# allowed in either kind.
kinds="$TEST_TMP_DIR/kinds"
write_descriptor "$kinds/code" 'model_kind=code'
parse_descriptor "$kinds/code/$DESCRIPTOR_FILE_NAME"
[[ "${PROJECT_CONF[model_kind]}" == code ]] || fail "model_kind=code"
write_descriptor "$kinds/theory" 'model_kind=theory' 'export_name=Test.Iface:code/x.ML' \
  'model_dispatch=differential/model_dispatch.ML' 'audit_collection=export_audit'
parse_descriptor "$kinds/theory/$DESCRIPTOR_FILE_NAME"
[[ "${PROJECT_CONF[model_kind]}" == theory ]] || fail "model_kind=theory"
parse_descriptor "$valid/$DESCRIPTOR_FILE_NAME"
[[ "${PROJECT_CONF[model_kind]:-code}" == code && -z "${PROJECT_CONF[model_kind]+set}" ]] ||
  fail "absent model_kind"
write_descriptor "$bad/kind" 'model_kind=plain'
expect_reject kind "$bad/kind/$DESCRIPTOR_FILE_NAME" "unknown model_kind: plain (expected code theory)"
write_descriptor "$bad/kind-empty" 'model_kind='
expect_reject kind-empty "$bad/kind-empty/$DESCRIPTOR_FILE_NAME" "unknown model_kind"
write_descriptor "$bad/kind-case" 'model_kind=Theory'
expect_reject kind-case "$bad/kind-case/$DESCRIPTOR_FILE_NAME" "unknown model_kind: Theory"
write_descriptor "$bad/kind-twice" 'model_kind=code' 'model_kind=theory'
expect_reject kind-twice "$bad/kind-twice/$DESCRIPTOR_FILE_NAME" "duplicate key: model_kind"

# The Python parser behind bin/isabelle-tooling accepts and refuses exactly
# what this one does, with the same message for a kind.
python_parse() {
  python3 -B - "$TEST_DIR/../scripts" "$1" <<'PY_PARSE'
import sys
sys.path.insert(0, sys.argv[1])
import isabelle_tooling
try:
    values = isabelle_tooling.parse_descriptor(open(sys.argv[2], encoding='utf-8').read())
except isabelle_tooling.Refused as exc:
    print(exc)
    sys.exit(1)
print(values.get('model_kind', ''))
PY_PARSE
}
for descriptor in "$valid" "$inject" "$kinds"/* "$bad"/*; do
  [[ -f "$descriptor/$DESCRIPTOR_FILE_NAME" ]] || continue
  shell=accepted python=accepted
  (parse_descriptor "$descriptor/$DESCRIPTOR_FILE_NAME") >/dev/null 2>&1 || shell=refused
  python_output="$(python_parse "$descriptor/$DESCRIPTOR_FILE_NAME")" || python=refused
  [[ "$shell" == "$python" ]] ||
    fail "parsers disagree on ${descriptor##*/}: shell $shell, Python $python ($python_output)"
done
[[ "$(python_parse "$kinds/theory/$DESCRIPTOR_FILE_NAME")" == theory ]] || fail "Python: model_kind=theory"
[[ "$(python_parse "$bad/kind/$DESCRIPTOR_FILE_NAME")" == *"unknown model_kind: plain (expected code theory)" ]] ||
  fail "Python: the kind message"

# --- resolver ----------------------------------------------------------------

# Layout A/B with a space in the path, resolved by bare invocation from deep
# inside, and by --project-root from elsewhere.
spaced="$TEST_TMP_DIR/with space/project one"
write_descriptor "$spaced"
mkdir -p "$spaced/src/deep"
(cd "$spaced/src/deep" && resolve_project "" &&
  [[ "$PROJECT_CHECKOUT_ROOT" == "$spaced" ]] &&
  [[ "$PROJECT_FORMAL_ROOT" == "$spaced/formal" ]] &&
  [[ "$PROJECT_SOURCE_ROOT" == "$spaced" ]]) || fail "spaced: bare resolution"
(cd / && resolve_project "$spaced/src/.." &&
  [[ "$PROJECT_CHECKOUT_ROOT" == "$spaced" ]]) || fail "spaced: --project-root canonicalization"

# Layout C: descriptor at the top, code in X, session at the top; resolved from
# inside X, which carries no descriptor of its own.
assurance="$TEST_TMP_DIR/assurance"
mkdir -p "$assurance/X/src/inner"
{
  printf 'format_version=1\nsource_rel=X\nformal_rel=.\nbuild_session=A\n'
  printf 'session_dir=A\nic2_base_session=HOL\nisabelle_version=Isabelle2025-2\n'
} >"$assurance/$DESCRIPTOR_FILE_NAME"
(cd "$assurance/X/src/inner" && resolve_project "" &&
  [[ "$PROJECT_CHECKOUT_ROOT" == "$assurance" ]] &&
  [[ "$PROJECT_SOURCE_ROOT" == "$assurance/X" ]] &&
  [[ "$PROJECT_FORMAL_ROOT" == "$assurance" ]]) || fail "layout C: resolution from inside X"

# Nested descriptors: X inside the assurance repo carries its own; the nearest
# wins by bare invocation and --project-root overrides it.
write_descriptor "$assurance/X"
(cd "$assurance/X/src/inner" && resolve_project "" &&
  [[ "$PROJECT_CHECKOUT_ROOT" == "$assurance/X" ]]) || fail "nested: nearest descriptor must win"
(cd "$assurance/X/src/inner" && resolve_project "$assurance" &&
  [[ "$PROJECT_CHECKOUT_ROOT" == "$assurance" ]] &&
  [[ "$PROJECT_SOURCE_ROOT" == "$assurance/X" ]]) || fail "nested: --project-root must override"

# No descriptor on the ancestor path.
bare="$TEST_TMP_DIR/bare/dir"
mkdir -p "$bare"
if output="$(cd "$bare" && resolve_project "" 2>&1)"; then
  fail "no descriptor: resolution succeeded"
fi
[[ "$output" == *"--project-root"* ]] || fail "no descriptor: error must name --project-root: $output"
if output="$(resolve_project "$bare" 2>&1)"; then
  fail "--project-root without descriptor: resolution succeeded"
fi
[[ "$output" == *"no $DESCRIPTOR_FILE_NAME in"* ]] || fail "--project-root without descriptor: $output"

# formal_rel must exist.
write_descriptor "$TEST_TMP_DIR/noformal"
rm -rf "$TEST_TMP_DIR/noformal/formal"
if output="$(resolve_project "$TEST_TMP_DIR/noformal" 2>&1)"; then
  fail "missing formal dir: resolution succeeded"
fi
[[ "$output" == *"formal_rel does not name a directory"* ]] || fail "missing formal dir: $output"

# --- server name ----------------------------------------------------------------

expected_hash="$(printf '%s' "$spaced" | openssl dgst -sha256 | awk '{print substr($NF, 1, 8)}')"
[[ "$(derive_server_name "$spaced")" == "ic2-project-one-$expected_hash" ]] ||
  fail "server name: $(derive_server_name "$spaced")"
# Two checkouts with the same basename get different names.
twin="$TEST_TMP_DIR/twin/project one"
write_descriptor "$twin"
[[ "$(derive_server_name "$twin")" != "$(derive_server_name "$spaced")" ]] ||
  fail "server name: same-basename checkouts must differ"
# A long basename is cut, so the socket path stays within ic2's limit, and a
# separator left at the cut is dropped.
long="$TEST_TMP_DIR/formal-offer-exchange-demo-proof"
long_hash="$(printf '%s' "$long" | openssl dgst -sha256 | awk '{print substr($NF, 1, 8)}')"
[[ "$(derive_server_name "$long")" == "ic2-formal-offer-exchange-de-$long_hash" ]] ||
  fail "server name: long basename: $(derive_server_name "$long")"
cut="$TEST_TMP_DIR/aaaaaaaaaaaaaaaaaaaaaaa-bbbb"
cut_hash="$(printf '%s' "$cut" | openssl dgst -sha256 | awk '{print substr($NF, 1, 8)}')"
[[ "$(derive_server_name "$cut")" == "ic2-aaaaaaaaaaaaaaaaaaaaaaa-$cut_hash" ]] ||
  fail "server name: separator at the cut: $(derive_server_name "$cut")"
long_name="$(derive_server_name "$long")"
(( ${#long_name} <= IC2_NAME_MAX )) || fail "server name: longer than IC2_NAME_MAX: $long_name"

# --- project wrapper ----------------------------------------------------------------

name_from_wrapper="$(cd "$spaced/src/deep" && "$WRAPPER" name)"
[[ "$name_from_wrapper" == "$(derive_server_name "$spaced")" ]] ||
  fail "wrapper: bare name from a subdirectory: $name_from_wrapper"
name_from_flag="$(cd / && "$WRAPPER" --project-root "$twin" name)"
[[ "$name_from_flag" == "$(derive_server_name "$twin")" ]] ||
  fail "wrapper: --project-root name: $name_from_flag"
name_from_eq="$(cd / && "$WRAPPER" "--project-root=$twin" name)"
[[ "$name_from_eq" == "$name_from_flag" ]] || fail "wrapper: --project-root=DIR form"
if output="$(cd "$bare" && "$WRAPPER" name 2>&1)"; then
  fail "wrapper: name without a descriptor succeeded"
fi
[[ "$output" == *"--project-root"* ]] || fail "wrapper: error must name --project-root"
# --help needs no project.
(cd "$bare" && "$WRAPPER" --help >/dev/null) || fail "wrapper: --help must not need a descriptor"
# The dry-run start passes the descriptor's formal root and base session.
start_out="$(cd "$spaced/src" && "$WRAPPER" start --dry-run)"
[[ "$start_out" == *"Session dir:  $spaced/formal"* ]] || fail "wrapper: start project: $start_out"
[[ "$start_out" == *"Session:      HOL"* ]] || fail "wrapper: start session"
[[ "$start_out" == *"Server:       $(derive_server_name "$spaced")"* ]] || fail "wrapper: start server"

echo "descriptor tests passed"

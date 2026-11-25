#!/usr/bin/env bash
set -euo pipefail

# setup-pide-ai.sh in a copy of the tooling scripts whose pin is a local
# commit, against a mock Isabelle2026 that keeps its user components file in
# the test directory.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test_lib.sh disable=SC1091
source "$TEST_DIR/test_lib.sh"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

tooling="$TEST_TMP_DIR/tooling"
mkdir -p "$tooling/scripts" "$tooling/.pide-ai"
cp "$TEST_DIR/../scripts/common.sh" "$TEST_DIR/../scripts/pide-ai-common.sh" \
  "$TEST_DIR/../scripts/setup-pide-ai.sh" "$tooling/scripts/"
SCRIPT="$tooling/scripts/setup-pide-ai.sh"

# The pin: the component layout of PIDE AI, with its JARs already built.
stage="$tooling/.pide-ai/stage"
for component in AI MCP Symbols; do
  mkdir -p "$stage/$component/lib"
done
mkdir "$stage/etc"
printf 'Symbols\nAI\nMCP\n' >"$stage/etc/components"
printf 'mock-2026\n' >"$stage/ISABELLE_VERSION"
: >"$stage/AI/lib/isabelle_pide_ai.jar"
: >"$stage/MCP/lib/isabelle_pide_mcp.jar"
: >"$stage/Symbols/lib/symbols.jar"
git -C "$stage" init -q
git -C "$stage" add -A
git -C "$stage" commit -qm pin
revision="$(git -C "$stage" rev-parse HEAD)"
pin="$tooling/.pide-ai/$revision"
mv "$stage" "$pin"
sed -i "s/^PIDE_AI_REVISION=.*/PIDE_AI_REVISION=$revision/" "$tooling/scripts/pide-ai-common.sh"

home_user="$TEST_TMP_DIR/isabelle-home-user"
components_file="$home_user/etc/components"
mkdir -p "$home_user/etc" "$TEST_TMP_DIR/isabelle2026/bin"
mock="$TEST_TMP_DIR/isabelle2026/bin/isabelle"
cat >"$mock" <<EOF
#!/usr/bin/env bash
set -euo pipefail
components_file=$(printf '%q' "$components_file")
EOF
cat >>"$mock" <<'EOF'
case "$1 ${2:-}" in
  "version -i") echo mock-2026 ;;
  "version ") echo Isabelle2026 ;;
  "getenv -b")
    case "$3" in
      ISABELLE_HOME_USER) dirname "$(dirname "$components_file")"; exit 0 ;;
      PIDE_AI_HOME) sub=AI ;;
      PIDE_MCP_HOME) sub=MCP ;;
      SYMBOLS_HOME) sub=Symbols ;;
      *) exit 64 ;;
    esac
    value=""
    if [[ -f "$components_file" ]]; then
      while read -r entry; do
        [[ ! -d "$entry/$sub" ]] || value="$entry/$sub"
      done <"$components_file"
    fi
    printf '%s\n' "$value" ;;
  "components -u")
    grep -qxF -- "$3" "$components_file" 2>/dev/null || printf '%s\n' "$3" >>"$components_file" ;;
  "components -x")
    # Isabelle trims each line and writes back the lines it keeps.
    while read -r entry; do
      [[ "$entry" == "$3" ]] || printf '%s\n' "$entry"
    done <"$components_file" >"$components_file.new"
    mv "$components_file.new" "$components_file" ;;
  "scala_build ") ;;
  *) echo "unexpected mock isabelle2026 command: $*" >&2; exit 64 ;;
esac
EOF
chmod +x "$mock"
export ISABELLE_TOOLING_ISABELLE2026="$TEST_TMP_DIR/isabelle2026"

pin_dir() {
  local dir="$1/.pide-ai/$2"
  mkdir -p "$dir/AI" "$dir/MCP" "$dir/Symbols"
  printf '%s\n' "$dir"
}

# An earlier pin of this clone, and a pin of a clone that moved away, are
# replaced; other components stay registered.
earlier="$(pin_dir "$tooling" "$(printf '1%.0s' {1..40})")"
moved="$TEST_TMP_DIR/moved-clone/.pide-ai/$(printf 'a%.0s' {1..40})"
printf '/opt/other-component\n%s\n  %s\n' "$earlier" "$moved" >"$components_file"
run_and_capture 0 replace "$SCRIPT"
assert_output_contains replace "Unregistering the earlier PIDE AI pin $earlier"
assert_output_contains replace "Unregistering the earlier PIDE AI pin $moved"
assert_output_contains replace "PIDE AI $revision is ready"
[[ "$(cat "$components_file")" == "/opt/other-component"$'\n'"$pin" ]] ||
  fail "replace: components file: $(cat "$components_file")"

run_and_capture 0 rerun "$SCRIPT"
[[ "$(cat "$components_file")" == "/opt/other-component"$'\n'"$pin" ]] ||
  fail "rerun: components file: $(cat "$components_file")"

# Another clone's pin is refused, naming the registered root, not the
# subcomponent Isabelle reports.
other="$(pin_dir "$TEST_TMP_DIR/other-clone" "$(printf 'b%.0s' {1..40})")"
printf '%s\n' "$other" >"$components_file"
run_and_capture 2 other-clone "$SCRIPT"
assert_output_contains other-clone "Another PIDE AI component is registered at $other. Unregister it"
assert_output_contains other-clone "components -x $other "
[[ "$(cat "$components_file")" == "$other" ]] || fail "other-clone: components file changed"

echo "setup-pide-ai.sh tests passed"

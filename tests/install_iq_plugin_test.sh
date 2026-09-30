#!/usr/bin/env bash
set -euo pipefail

# install-iq-plugin.sh against a stand-in AutoCorrode checkout whose install
# target ends, like upstream's, with steps that start a plain `isabelle jedit`.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=test_lib.sh disable=SC1091
source "$TEST_DIR/test_lib.sh"

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
autocorrode="$TEST_TMP_DIR/AutoCorrode"
mkdir -p "$autocorrode/iq"
cat >"$autocorrode/iq/Makefile" <<'EOF'
.RECIPEPREFIX = >
install:
> @mkdir -p "$(INSTALL_DIR)" && : >"$(INSTALL_DIR)/iq_plugin.jar"
> @echo "Plugin built and installed successfully!"
> @echo ""
> @echo "To use the plugin:"
> @echo "1. Start Isabelle/jEdit: $(ISABELLE_HOME)/bin/isabelle jedit"
> @echo "2. Go to Utilities -> Global Options -> Plugin Manager"
> @echo "After the steps."
> @test -z "$(FAIL)"
EOF
git -C "$autocorrode" init -q
git -C "$autocorrode" add -A
git -C "$autocorrode" commit -qm fixture

SCRIPT="$TEST_DIR/../scripts/install-iq-plugin.sh"
jars="$MOCK_ISABELLE_STATE_DIR/isabelle-home-user/jedit/jars"

run_and_capture 0 install "$SCRIPT" --isabelle "$TEST_TMP_DIR/bin/isabelle" --autocorrode "$autocorrode"
assert_output_contains install "Plugin built and installed successfully!"
assert_output_contains install "After the steps."
assert_output_contains install "scripts/launch_jedit.sh"
if grep -Eq 'To use the plugin|isabelle jedit$|Plugin Manager' "$TEST_TMP_DIR/install.out"; then
  fail "install relayed the plain isabelle jedit steps"
fi
grep -Fqx "autocorrode_revision=$(git -C "$autocorrode" rev-parse HEAD)" "$jars/iq_plugin.jar.stamp" ||
  fail "stamp does not name the AutoCorrode revision"

# The output filter does not hide a failed build.
rm -f -- "$jars/iq_plugin.jar.stamp"
run_and_capture 2 failed_build env FAIL=1 "$SCRIPT" --isabelle "$TEST_TMP_DIR/bin/isabelle" --autocorrode "$autocorrode"
[[ ! -e "$jars/iq_plugin.jar.stamp" ]] || fail "a failed build wrote a stamp"

echo "install-iq-plugin tests passed"

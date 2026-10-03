#!/usr/bin/env bash
# Needs a real Isabelle: renders each kind's session from this working tree's
# templates and builds it, then builds the theory session again with a theory
# that imports HOL-Library.FSet, which its ROOT must make importable.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$TEST_DIR/../.." && pwd -P)"
OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/isabelle-template-build-test.XXXXXX")"
HEAPS="$(isabelle getenv -b ISABELLE_HEAPS)"
SESSIONS=(Template_Build_Code Template_Build_Theory)
# The builds leave only their logs in the user's heap directory; remove them.
cleanup() {
  rm -rf -- "$OUT_DIR"
  local log session
  for log in "$HEAPS"/*/log; do
    for session in "${SESSIONS[@]}"; do
      rm -f -- "$log/$session" "$log/$session.gz" "$log/$session.db"
    done
  done
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# The renderer reads templates from a commit; a scratch repository holds this
# working tree's scripts and templates.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
runtime="$OUT_DIR/runtime"
mkdir -p "$runtime"
cp -R "$ROOT/scripts" "$ROOT/templates" "$runtime/"
git -C "$runtime" init -q
git -C "$runtime" add -A
git -C "$runtime" commit -qm scratch
revision="$(git -C "$runtime" rev-parse HEAD)"

# build KIND SESSION: render the session and build it.
build() {
  local kind="$1" session="$2" stage="$OUT_DIR/$1"
  mkdir "$stage"
  "$runtime/scripts/new-project.sh" --revision "$revision" --stage "$stage" --session "$session" \
    --project-name "the $kind template" --kind "$kind"
  isabelle build -D "$stage/formal" >"$OUT_DIR/$kind.log" 2>&1 ||
    { tail -40 "$OUT_DIR/$kind.log" >&2; fail "$kind: the rendered session does not build"; }
  echo "template_build_test: $kind ok"
}
build code Template_Build_Code
build theory Template_Build_Theory

session="$OUT_DIR/theory/formal/Template_Build_Theory"
cat >"$session/Finite_Sets.thy" <<'THY'
theory Finite_Sets
  imports Template_Build_Theory "HOL-Library.FSet"
begin

lemma "fcard {||} = 0"
  by simp

end
THY
sed -i 's/^    Template_Build_Theory$/    Template_Build_Theory\n    Finite_Sets/' "$session/ROOT"
grep -q '^    Finite_Sets$' "$session/ROOT" || fail "could not add the theory to ROOT"
isabelle build -D "$OUT_DIR/theory/formal" >"$OUT_DIR/fset.log" 2>&1 ||
  { tail -40 "$OUT_DIR/fset.log" >&2; fail "theory: a HOL-Library import does not build"; }
echo "template_build_test: theory with HOL-Library.FSet ok"

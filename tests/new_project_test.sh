#!/usr/bin/env bash
set -euo pipefail

# The session renderer behind `isabelle-tooling init`: it renders the
# templates of a given commit, never the working tree. A scratch repository
# holds this working tree's scripts and templates at one commit.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEST_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/isabelle-tooling-newproject.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
runtime="$TEST_TMP_DIR/runtime"
mkdir -p "$runtime"
cp -R "$TEST_DIR/../scripts" "$TEST_DIR/../templates" "$runtime/"
git -C "$runtime" init -q
git -C "$runtime" add -A
git -C "$runtime" commit -qm scratch
revision="$(git -C "$runtime" rev-parse HEAD)"
# An uncommitted template edit must not be rendered.
printf 'uncommitted\n' >>"$runtime/templates/formal/ROOTS"
SCRIPT="$runtime/scripts/new-project.sh"

stage="$TEST_TMP_DIR/stage"
mkdir "$stage"
"$SCRIPT" --revision "$revision" --stage "$stage" --session Demo_Session --project-name "my project"
for f in isabelle-tooling.conf formal/ROOTS formal/AGENTS.md formal/README.md formal/Demo_Session/ROOT formal/Demo_Session/Demo_Session.thy; do
  [[ -f "$stage/$f" ]] || fail "missing $f"
done
[[ "$(readlink "$stage/formal/CLAUDE.md")" == "AGENTS.md" ]] || fail "CLAUDE.md is not a symlink to AGENTS.md"
grep -rq '@[A-Z_]*@' "$stage" && fail "unsubstituted placeholder"
grep -q uncommitted "$stage/formal/ROOTS" && fail "rendered the working tree, not the commit"
grep -q "^tooling_revision=$revision\$" "$stage/isabelle-tooling.conf" || fail "tooling_revision"
grep -q '^session Demo_Session = HOL +' "$stage/formal/Demo_Session/ROOT" || fail "ROOT session line"
grep -q '^theory Demo_Session$' "$stage/formal/Demo_Session/Demo_Session.thy" || fail "theory name"
grep -q 'my project' "$stage/formal/README.md" || fail "project name substitution"
find "$stage" -name '*.template' | grep -q . && fail "left a template file behind"

# Layout C: formal at the top, code in X.
assurance="$TEST_TMP_DIR/assurance"
mkdir "$assurance"
"$SCRIPT" --revision "$revision" --stage "$assurance" --session Model --formal-rel . --source-rel X --project-name "The X project"
[[ -f "$assurance/Model/ROOT" && -f "$assurance/AGENTS.md" ]] || fail "layout C files"
grep -q '^source_rel=X$' "$assurance/isabelle-tooling.conf" || fail "layout C source_rel"

# Rejections.
empty="$TEST_TMP_DIR/empty"
mkdir "$empty"
reject() { "$SCRIPT" "$@" >/dev/null 2>&1 && fail "accepted: $*"; return 0; }
reject --revision "$revision" --stage "$empty" --session 'bad name' --project-name p
reject --revision "$revision" --stage "$empty" --session Ok --project-name p --formal-rel ../up
reject --revision "$revision" --stage "$empty" --session Ok --project-name 'a|b'
reject --revision "$revision" --stage "$stage" --session Ok --project-name p
reject --revision HEAD --stage "$empty" --session Ok --project-name p
reject --revision "$(printf '0%.0s' {1..40})" --stage "$empty" --session Ok --project-name p
reject --revision "$revision" --stage "$TEST_TMP_DIR/missing" --session Ok --project-name p
[[ -z "$(ls -A "$empty")" ]] || fail "a rejected run wrote into the stage"

echo "new-project.sh tests passed"

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

# A code project, with or without --kind: no model_kind, the code-level scaffold.
code="$TEST_TMP_DIR/code"
mkdir "$code"
"$SCRIPT" --revision "$revision" --stage "$code" --session Demo_Session --project-name "my project" --kind code
diff -r "$stage" "$code" >/dev/null || fail "--kind code renders differently from the default"
grep -q '^model_kind=' "$stage/isabelle-tooling.conf" && fail "a code descriptor names its kind"
grep -q '"HOL-Library.Word"' "$stage/formal/Demo_Session/Demo_Session.thy" || fail "code: Word import"
grep -q '^## Conventions$' "$stage/formal/AGENTS.md" || fail "code: conventions block"

# A theory project: a blank session importing Main, HOL-Library importable, no conventions.
theory="$TEST_TMP_DIR/theory"
mkdir "$theory"
"$SCRIPT" --revision "$revision" --stage "$theory" --session Notes --project-name "my paper" --kind theory
for f in isabelle-tooling.conf formal/ROOTS formal/AGENTS.md formal/README.md formal/Notes/ROOT formal/Notes/Notes.thy; do
  [[ -f "$theory/$f" ]] || fail "theory: missing $f"
done
[[ "$(readlink "$theory/formal/CLAUDE.md")" == "AGENTS.md" ]] || fail "theory: CLAUDE.md symlink"
grep -rq '@[A-Z_]*@' "$theory" && fail "theory: unsubstituted placeholder"
[[ "$(cat "$theory/formal/Notes/Notes.thy")" == "$(printf 'theory Notes\n  imports Main\nbegin\n\nend')" ]] ||
  fail "theory: the entry theory is not the blank theory: $(cat "$theory/formal/Notes/Notes.thy")"
grep -q '^session Notes = HOL +$' "$theory/formal/Notes/ROOT" || fail "theory: ROOT session line"
grep -A1 '^  sessions$' "$theory/formal/Notes/ROOT" | grep -q '^    "HOL-Library"$' || fail "theory: ROOT lacks HOL-Library"
grep -q 'Conventions\|code-level\|differential' "$theory/formal/AGENTS.md" && fail "theory: AGENTS.md names the code method"
grep -q 'my paper' "$theory/formal/README.md" || fail "theory: project name substitution"
grep -q '^model_kind=theory$' "$theory/isabelle-tooling.conf" || fail "theory: model_kind"
grep -q 'export_name' "$theory/isabelle-tooling.conf" && fail "theory: the differential block"
(
  # shellcheck source=../scripts/common.sh disable=SC1091
  source "$runtime/scripts/common.sh"
  parse_descriptor "$theory/isabelle-tooling.conf"
  [[ "${PROJECT_CONF[model_kind]}" == theory ]]
) || fail "theory: the descriptor does not parse as a theory project"

# Rejections.
empty="$TEST_TMP_DIR/empty"
mkdir "$empty"
reject() { "$SCRIPT" "$@" >/dev/null 2>&1 && fail "accepted: $*"; return 0; }
reject --revision "$revision" --stage "$empty" --session Ok --project-name p --kind other
reject --revision "$revision" --stage "$empty" --session Ok --project-name p --kind
reject --revision "$revision" --stage "$empty" --session 'bad name' --project-name p
reject --revision "$revision" --stage "$empty" --session Ok --project-name p --formal-rel ../up
reject --revision "$revision" --stage "$empty" --session Ok --project-name 'a|b'
reject --revision "$revision" --stage "$stage" --session Ok --project-name p
reject --revision HEAD --stage "$empty" --session Ok --project-name p
reject --revision "$(printf '0%.0s' {1..40})" --stage "$empty" --session Ok --project-name p
reject --revision "$revision" --stage "$TEST_TMP_DIR/missing" --session Ok --project-name p
[[ -z "$(ls -A "$empty")" ]] || fail "a rejected run wrote into the stage"

# A revision from before theory projects: code renders, theory is refused by name.
git -C "$runtime" rm -rq templates/theory
git -C "$runtime" commit -qm "no theory templates"
older="$(git -C "$runtime" rev-parse HEAD)"
"$SCRIPT" --revision "$older" --stage "$empty" --session Ok --project-name p
rm -rf "$empty" && mkdir "$empty"
if output="$("$SCRIPT" --revision "$older" --stage "$empty" --session Ok --project-name p --kind theory 2>&1)"; then
  fail "--kind theory accepted at a revision without templates/theory/"
fi
[[ "$output" == *"$older has no templates/theory/"* ]] || fail "--kind theory refusal: $output"
[[ -z "$(ls -A "$empty")" ]] || fail "the refused theory render wrote into the stage"

echo "new-project.sh tests passed"

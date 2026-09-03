#!/usr/bin/env bash
# Mechanical part of the Phase 4 acceptance on a project produced by
# phase4-fixture.sh: setup, conventions block, clean build, export check,
# differential run, the named property. The structural side-by-side review of
# the model against src/fee.c is done by a reader (the isabelle-modeling skill,
# section 4); this script only lists the theories for it.
#
# Usage: phase4-check.sh PROJECT
set -uo pipefail

PROJECT="${1:-}"
[[ -d "$PROJECT" ]] || { echo "usage: $0 PROJECT" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd -P)"
[[ -n "${ISABELLE_TOOLING_ROOT:-}" ]] || { echo "ISABELLE_TOOLING_ROOT is not set" >&2; exit 2; }
TOOLING="$ISABELLE_TOOLING_ROOT"

failures=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; failures=$((failures + 1)); }
check() { # check NAME COMMAND...
  local name="$1"; shift
  if "$@" >"/tmp/phase4-check.$$.out" 2>&1; then pass "$name"; else fail "$name"; sed -n '1,40p' "/tmp/phase4-check.$$.out" | sed 's/^/      /'; fi
}
trap 'rm -f /tmp/phase4-check.$$.out' EXIT

cd "$PROJECT" || exit 2

# 1. Setup
check "descriptor present" test -f isabelle-tooling.conf
check "descriptor names the export" grep -q '^export_name=' isabelle-tooling.conf
check "descriptor names the dispatch" grep -q '^model_dispatch=' isabelle-tooling.conf
check "doctor green" "$TOOLING/scripts/doctor.sh" --project-root "$PROJECT"
formal_rel="$(sed -n 's/^formal_rel=//p' isabelle-tooling.conf | head -1)"
session="$(sed -n 's/^build_session=//p' isabelle-tooling.conf | head -1)"
FORMAL="$PROJECT/${formal_rel:-formal}"

# 2. Conventions block, settled
check "AGENTS.md has a Conventions block" grep -q '^## Conventions' "$FORMAL/AGENTS.md"
check "no convention left unsettled" bash -c "! grep -q '(unsettled)' '$FORMAL/AGENTS.md'"
check "CLAUDE.md is a symlink to AGENTS.md" test -L "$FORMAL/CLAUDE.md"
check "INTERVIEW.md was written in turn 1" test -f INTERVIEW.md

# 3. Clean build and proof hygiene
check "no quick_and_dirty in ROOT files" bash -c "! grep -rq 'quick_and_dirty' '$FORMAL' --include=ROOT"
check "no sorry/oracle/axiomatization in theories" bash -c "! grep -rnE '^\s*(sorry|oracle|axiomatization)\b|\bsorry\b' '$FORMAL' --include='*.thy'"
check "isabelle build passes" isabelle build -D "$FORMAL"
check "property fee_ceil_ok_bounded is stated" grep -rqE '(lemma|theorem|corollary) +fee_ceil_ok_bounded\b' "$FORMAL" --include='*.thy'

# 4. The link and the differential run
check "export check passes" "$TOOLING/scripts/export-check.sh" --project-root "$PROJECT"
check "run.sh exists" test -x "$FORMAL/differential/run.sh"
check "model_dispatch.ML exists" test -f "$FORMAL/$(sed -n 's/^model_dispatch=//p' isabelle-tooling.conf | head -1)"
check "differential run passes" env ISABELLE_TOOLING_ROOT="$TOOLING" "$FORMAL/differential/run.sh"
check "a golden file is committed" bash -c "git -C '$PROJECT' ls-files '$FORMAL/differential' | grep -qiE 'golden|expected'"
check "an Assurance section exists" grep -qi '^## Assurance' "$FORMAL/README.md"
check "working tree committed" bash -c "[[ -z \"\$(git -C '$PROJECT' status --porcelain)\" ]]"

echo
echo "Theories for the side-by-side review (isabelle-modeling, section 4):"
find "$FORMAL/$session" -name '*.thy' | sort | sed 's/^/  /'
echo "Source: $PROJECT/src/fee.c"
echo
if [[ "$failures" -eq 0 ]]; then echo "phase4-check: all mechanical checks passed"; else echo "phase4-check: $failures check(s) failed"; exit 1; fi

#!/usr/bin/env bash
# Phase 4 host fixture: a fresh project holding one small C function, driven
# end to end by an agent host that has only the installed extension and the
# tooling clone. Two turns: the host holds the conventions interview and
# stops; the fixture answers as the user; the host then models, tests, and
# proves. Afterwards phase4-check.sh verifies the artifacts. Run separately
# per host; one host consuming the other's artifacts is not a parity test.
#
# Usage: phase4-fixture.sh claude|codex WORKDIR [--session NAME] [--turn 1|2|both]
#
# Needs ISABELLE_TOOLING_ROOT in the environment (the hosts read it too), a
# real Isabelle, and the extension installed in the chosen host. Costs two
# model runs of the host; expect tens of minutes.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FIXTURE_SRC="$HERE/../fixtures/host/fee"
HOST="${1:-}"; WORKDIR="${2:-}"
[[ "$HOST" == claude || "$HOST" == codex ]] || { echo "usage: $0 claude|codex WORKDIR" >&2; exit 2; }
[[ -n "$WORKDIR" ]] || { echo "usage: $0 claude|codex WORKDIR" >&2; exit 2; }
shift 2
SESSION="Fee"
TURN="both"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    --turn) TURN="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ -n "${ISABELLE_TOOLING_ROOT:-}" ]] || { echo "ISABELLE_TOOLING_ROOT is not set" >&2; exit 2; }

mkdir -p "$WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd -P)"
PROJECT="$WORKDIR/fee"
LOGS="$WORKDIR/logs"
mkdir -p "$LOGS"

if [[ "$TURN" == both || "$TURN" == 1 ]]; then
  [[ ! -e "$PROJECT" ]] || { echo "refusing to overwrite $PROJECT" >&2; exit 2; }
  mkdir -p "$PROJECT"
  cp -R "$FIXTURE_SRC/." "$PROJECT/"
  git -C "$PROJECT" init -q
  git -C "$PROJECT" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false add -A
  git -C "$PROJECT" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -q -m "fee: initial C source"
fi

TURN1="$(cat <<PROMPT
You are in a fresh checkout of a small C project (src/fee.h, src/fee.c) with no
formal artifacts yet. Use the skills of the installed isabelle-formal-modeling
extension throughout; the tooling clone is \$ISABELLE_TOOLING_ROOT.

Do these two things, then stop and report:

1. Set up Isabelle formal modelling for this checkout with the isabelle-setup
   skill: session name $SESSION, formal artifacts under formal/, source at the
   checkout root. Run doctor and make sure the empty session builds. Every
   step that would touch the home directory is already done on this machine;
   report if doctor disagrees.

2. Begin the isabelle-modeling skill for the two functions in src/fee.c, but
   only as far as the conventions interview: write the interview questions, with
   the default you propose for each and the reason, to INTERVIEW.md at the
   checkout root, and stop. The user will answer in the next turn. Do not write
   any definition, corpus, or harness before the answers arrive.

Commit what you created. Never push, never open issues or pull requests.
PROMPT
)"

TURN2="$(cat <<PROMPT
Here are the user's answers to INTERVIEW.md. Record them in the Conventions
block of formal/AGENTS.md, then finish the work.

- Source in scope: both functions of src/fee.c, mul_u64_checked and fee_ceil,
  modelled separately with the same boundaries. Nothing is opaque.
- Detected failures: use the default lightweight result type with a bind
  operator and do notation. The error enumeration has one constructor per
  non-OK fee_status value (negative amount, bad rate, overflow), raised in the
  order the C checks them. fee_ceil's C return value is exactly that status.
- Out-parameters and unassigned values: the default. An out-parameter plus a
  Boolean return becomes a pair (bool x value): mul_u64_checked keeps its
  Boolean, and fee_ceil's line that turns a false return into FEE_OVERFLOW
  stays in fee_ceil. fee_ceil's status plus *fee is Ok fee / Err status, since
  *fee is assigned exactly on the OK path. Where the C leaves an out-parameter
  unchanged, the model returns zero and the definition's text block says so.
- Casts and promotions: write every cast out and annotate each in the text
  block. (uint64_t)rate_bps converts a signed value modulo 2^64, so it is scast
  (ucast would agree only because of the preceding range check; if you prefer
  ucast, say that justification). Same-width casts are a change of reading,
  recorded in the text. The comparison scaled > (uint64_t)INT64_MAX is
  unsigned; say so.
- Unreachable defensive checks: model as written, and prove a lemma when one
  is unreachable. Decide reachability yourself by reading the arithmetic; do
  not take my word for which checks are live.
- Undefined behaviour: state the definedness precondition per definition; this
  code has none (unsigned arithmetic, guarded division), and the text says so.
- Naming: keep the C names (already snake_case) and the argument order.

Then, in this order:

1. The code-level model, one definition per C function, with source comments,
   text blocks, and by-eval examples, following the isabelle-modeling skill.
2. A test-interface theory exporting both functions through integer transports,
   and the differential test following the isabelle-differential skill: the
   descriptor keys, the export_audit collection, model_dispatch.ML, a corpus
   generator with hand-designed extrema (include the inputs on which each
   failure fires, the largest amount whose fee still fits, and the product
   window just under UINT64_MAX - 9999), a C adapter compiled from src/fee.c
   that PRODUCES its own result file from the same corpus, a comparison with
   per-tag OK and ERR mutations, and a committed golden file. The entry point
   must be formal/differential/run.sh and it must exit 0 only when everything
   passed. Run the export check before the differential run.
3. One proved property, named fee_ceil_ok_bounded: whenever fee_ceil returns Ok
   with a fee, the fee is non-negative and at most the amount (as signed
   integers). Use quickcheck or nitpick first, then prove it with no sorry; the
   session must build without quick_and_dirty.
4. An Assurance section in formal/README.md following the isabelle-assurance
   skill.

Finish with isabelle build -D formal, the export check, and run.sh all
passing, and commit. Report what passed, what you could not finish, and every
place where the model is not a literal transcription of the C.
PROMPT
)"

run_claude() {
  local turn="$1" prompt="$2" session_file="$WORKDIR/claude-session-id"
  local args=(-p --dangerously-skip-permissions --output-format json)
  if [[ "$turn" == 1 ]]; then
    local sid; sid="$(python3 -c 'import uuid; print(uuid.uuid4())')"
    echo "$sid" >"$session_file"
    args+=(--session-id "$sid")
  else
    args+=(--resume "$(cat "$session_file")")
  fi
  (cd "$PROJECT" && claude "${args[@]}" "$prompt") >"$LOGS/claude-turn$turn.json" 2>"$LOGS/claude-turn$turn.err"
  python3 - "$LOGS/claude-turn$turn.json" >"$LOGS/claude-turn$turn.md" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("result",""))
print("\n---\ncost_usd=%s duration_ms=%s turns=%s" % (d.get("total_cost_usd"), d.get("duration_ms"), d.get("num_turns")))
PY
}

run_codex() {
  local turn="$1" prompt="$2" session_file="$WORKDIR/codex-session-id"
  local common=(-c model_reasoning_effort=medium --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check)
  if [[ "$turn" == 1 ]]; then
    (cd "$PROJECT" && codex exec "${common[@]}" --json -o "$LOGS/codex-turn1.md" "$prompt") >"$LOGS/codex-turn1.jsonl" 2>"$LOGS/codex-turn1.err"
    python3 - "$LOGS/codex-turn1.jsonl" >"$session_file" <<'PY'
import json,sys
for line in open(sys.argv[1]):
    try: e=json.loads(line)
    except Exception: continue
    if e.get("type")=="thread.started" and e.get("thread_id"):
        print(e["thread_id"]); break
PY
    [[ -s "$session_file" ]] || echo "warning: no thread id captured; turn 2 will use --last" >&2
  else
    local sid; sid="$(cat "$session_file" 2>/dev/null || true)"
    if [[ -n "$sid" ]]; then
      (cd "$PROJECT" && codex exec resume "${common[@]}" -o "$LOGS/codex-turn2.md" "$sid" "$prompt") >"$LOGS/codex-turn2.out" 2>"$LOGS/codex-turn2.err"
    else
      (cd "$PROJECT" && codex exec resume "${common[@]}" -o "$LOGS/codex-turn2.md" --last "$prompt") >"$LOGS/codex-turn2.out" 2>"$LOGS/codex-turn2.err"
    fi
  fi
}

run_turn() {
  local turn="$1" prompt="$2"
  echo "phase4-fixture: $HOST turn $turn starting $(date -Is)"
  if [[ "$HOST" == claude ]]; then run_claude "$turn" "$prompt"; else run_codex "$turn" "$prompt"; fi
  echo "phase4-fixture: $HOST turn $turn finished $(date -Is); report in $LOGS/$HOST-turn$turn.md"
}

if [[ "$TURN" == both || "$TURN" == 1 ]]; then
  run_turn 1 "$TURN1"
  [[ -f "$PROJECT/INTERVIEW.md" ]] || echo "phase4-fixture: warning: INTERVIEW.md was not written" >&2
fi
if [[ "$TURN" == both || "$TURN" == 2 ]]; then
  run_turn 2 "$TURN2"
fi
echo "phase4-fixture: project at $PROJECT; now run: $HERE/phase4-check.sh $PROJECT"

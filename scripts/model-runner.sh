#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh disable=SC1091
source "$SCRIPT_DIR/common.sh"

RUNNER_ML="$(cd "$SCRIPT_DIR/.." && pwd -P)/model-runner/runner.ML"

usage() {
  cat <<'EOF'
Usage: model-runner.sh [--project-root DIR] [OPTIONS] batch INPUT OUTPUT
       model-runner.sh [--project-root DIR] [OPTIONS] resident

Evaluate a project's exported Isabelle model over records. The runner owns the
generic plumbing: building the session, exporting the code named by the
descriptor's export_name, loading it with the project's model_dispatch file
into `isabelle ML_process`, line framing, failure handling, and keeping input
and output rows aligned. The project's dispatch ML owns the meaning of a
record: it parses the fields, checks ranges, calls the exported function, and
formats the result suffix. Records are opaque to the runner.

Modes:
  batch INPUT OUTPUT   Answer every record of INPUT; install OUTPUT atomically
                       once every row has been answered. Each output line is
                       the input line, a tab, and the dispatch result; blank
                       and `#` lines are echoed unchanged. A rejected record
                       or a dispatch failure aborts the run and leaves OUTPUT
                       untouched.
  resident             Keep the model loaded and answer one record per line
                       of standard input on standard output. The first line
                       printed is `#ready`; a rejected record answers
                       `#reject<TAB>LINE<TAB>MESSAGE`, a dispatch failure
                       `#error<TAB>LINE<TAB>MESSAGE`. Ends at end of input.

Options:
  --no-build           Do not run `isabelle build` first (the session must be
                       up to date; the export is still re-extracted)
  -o OPTION            Extra `isabelle build` option, repeatable
  --logic NAME         Logic for ML_process (default HOL); the exported code
                       is self-contained SML and needs no project heap
  --work-dir DIR       Keep the export and logs in DIR instead of a temporary
                       directory removed on success
  --dry-run            Print the commands instead of running them

Descriptor keys used: build_session, session_dir, export_name
(Session.Theory:path as listed by `isabelle export -l`), model_dispatch
(path of the dispatch ML file, relative to the formal root).
EOF
}

case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac

{ read -r requested_root; read -r consumed; } < <(parse_project_root_option "$@")
shift "$consumed"

BUILD=true
DRY_RUN=false
LOGIC="HOL"
WORK_DIR=""
BUILD_OPTIONS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) BUILD=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --logic) [[ -n "${2:-}" ]] || die "--logic requires an argument"; LOGIC="$2"; shift 2 ;;
    --work-dir) [[ -n "${2:-}" ]] || die "--work-dir requires an argument"; WORK_DIR="$2"; shift 2 ;;
    -o) [[ -n "${2:-}" ]] || die "-o requires an argument"; BUILD_OPTIONS+=(-o "$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

MODE="${1:-}"
case "$MODE" in
  batch)
    [[ $# -eq 3 ]] || die "batch takes exactly INPUT and OUTPUT"
    INPUT="$2"
    OUTPUT="$3"
    ;;
  resident)
    [[ $# -eq 1 ]] || die "resident takes no arguments"
    ;;
  "") usage >&2; exit 2 ;;
  *) die "unknown mode: $MODE (expected batch or resident)" ;;
esac

resolve_project "$requested_root"
require_isabelle

SESSION="${PROJECT_CONF[build_session]}"
SESSION_PATH="$PROJECT_FORMAL_ROOT/${PROJECT_CONF[session_dir]}"
EXPORT_NAME="${PROJECT_CONF[export_name]:-}"
DISPATCH_REL="${PROJECT_CONF[model_dispatch]:-}"
[[ -n "$EXPORT_NAME" ]] ||
  die "$PROJECT_DESCRIPTOR: export_name is not set.
Add export_name=SESSION.THEORY:PATH as listed by 'isabelle export -l -d SESSION_DIR SESSION'."
[[ -n "$DISPATCH_REL" ]] ||
  die "$PROJECT_DESCRIPTOR: model_dispatch is not set.
Add model_dispatch=PATH, the dispatch ML file relative to the formal root."
DISPATCH_ML="$PROJECT_FORMAL_ROOT/$DISPATCH_REL"
[[ -f "$DISPATCH_ML" ]] || die "model_dispatch file not found: $DISPATCH_ML"
[[ -f "$RUNNER_ML" ]] || die "runner ML not found: $RUNNER_ML"
[[ "$EXPORT_NAME" == *.*:* ]] ||
  die "$PROJECT_DESCRIPTOR: export_name must look like SESSION.THEORY:PATH, found: $EXPORT_NAME"
EXPORT_THEORY="${EXPORT_NAME%%:*}"
EXPORT_PATH="${EXPORT_NAME#*:}"
[[ "$EXPORT_THEORY" == "$SESSION".* ]] ||
  die "$PROJECT_DESCRIPTOR: export_name must belong to session $SESSION, found: $EXPORT_THEORY"

if [[ "$MODE" == "batch" ]]; then
  [[ -f "$INPUT" ]] || die "input file not found: $INPUT"
  INPUT="$(canonical_file "$INPUT")"
  output_dir="$(dirname -- "$OUTPUT")"
  [[ -d "$output_dir" ]] || die "output directory does not exist: $output_dir"
  OUTPUT="$(cd "$output_dir" && pwd -P)/$(basename -- "$OUTPUT")"
fi

run() {
  if $DRY_RUN; then
    print_command "$@"
  else
    "$@"
  fi
}

if [[ -n "$WORK_DIR" ]]; then
  mkdir -p -- "$WORK_DIR"
  WORK_DIR="$(cd "$WORK_DIR" && pwd -P)"
  KEEP_WORK=true
else
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/isabelle-model-runner.XXXXXX")"
  KEEP_WORK=false
fi
cleanup() {
  local status=$?
  if [[ "$status" -eq 0 && "$KEEP_WORK" == false ]]; then
    rm -rf -- "$WORK_DIR"
  elif [[ "$status" -ne 0 ]]; then
    echo "model-runner: work directory preserved at $WORK_DIR" >&2
  fi
}
trap cleanup EXIT

if $BUILD; then
  echo "model-runner: building session $SESSION" >&2
  run "$ISABELLE_CMD" build "${BUILD_OPTIONS[@]}" -D "$SESSION_PATH" >&2
fi

if ! $DRY_RUN; then
  export_count="$(
    "$ISABELLE_CMD" export -l -d "$SESSION_PATH" "$SESSION" |
      awk -v expected="$EXPORT_NAME" '$0 == expected { count += 1 } END { print count + 0 }'
  )"
  [[ "$export_count" -eq 1 ]] ||
    die "expected exactly one export named $EXPORT_NAME in session $SESSION, found $export_count"
fi

EXPORT_DIR="$WORK_DIR/export"
mkdir -p -- "$EXPORT_DIR"
run "$ISABELLE_CMD" export -n -d "$SESSION_PATH" -O "$EXPORT_DIR" -x "$EXPORT_NAME" "$SESSION" >&2
MODEL_ML="$EXPORT_DIR/$EXPORT_THEORY/$EXPORT_PATH"
if ! $DRY_RUN; then
  [[ -f "$MODEL_ML" ]] || die "Isabelle did not extract the expected model file: $MODEL_ML"
fi

count_records() {
  awk 'length($0) > 0 && substr($0, 1, 1) != "#" { count += 1 } END { print count + 0 }' "$1"
}
count_lines() {
  awk 'END { print NR }' "$1"
}

case "$MODE" in
  batch)
    partial_output="$OUTPUT.partial.$$"
    rm -f -- "$partial_output"
    ml_log="$WORK_DIR/ml_process.log"
    echo "model-runner: evaluating $(count_records "$INPUT") records" >&2
    if $DRY_RUN; then
      print_command env ISABELLE_MODEL_RUNNER_MODE=batch \
        "ISABELLE_MODEL_RUNNER_INPUT=$INPUT" "ISABELLE_MODEL_RUNNER_OUTPUT=$partial_output" \
        "$ISABELLE_CMD" ML_process -l "$LOGIC" -f "$MODEL_ML" -f "$DISPATCH_ML" -f "$RUNNER_ML"
      exit 0
    fi
    if ! ISABELLE_MODEL_RUNNER_MODE=batch \
        ISABELLE_MODEL_RUNNER_INPUT="$INPUT" \
        ISABELLE_MODEL_RUNNER_OUTPUT="$partial_output" \
        "$ISABELLE_CMD" ML_process -l "$LOGIC" -f "$MODEL_ML" -f "$DISPATCH_ML" -f "$RUNNER_ML" \
          >"$ml_log" 2>&1
    then
      tail -n 80 "$ml_log" >&2
      rm -f -- "$partial_output"
      die "model evaluation failed (full log: $ml_log)"
    fi
    [[ -f "$partial_output" ]] || die "model evaluation produced no output file"
    # ML_process may print compiler warnings while loading; those go to the
    # log, never into the result. The result must answer every input line.
    input_lines="$(count_lines "$INPUT")"
    output_lines="$(count_lines "$partial_output")"
    if [[ "$input_lines" -ne "$output_lines" ]]; then
      rm -f -- "$partial_output"
      die "model produced $output_lines lines for $input_lines input lines"
    fi
    input_records="$(count_records "$INPUT")"
    output_records="$(count_records "$partial_output")"
    if [[ "$input_records" -ne "$output_records" ]]; then
      rm -f -- "$partial_output"
      die "model produced $output_records rows for $input_records input records"
    fi
    mv -f -- "$partial_output" "$OUTPUT"
    echo "model-runner: wrote $output_records rows to $OUTPUT" >&2
    ;;
  resident)
    input_fifo="$WORK_DIR/input.fifo"
    if $DRY_RUN; then
      print_command env ISABELLE_MODEL_RUNNER_MODE=resident "ISABELLE_MODEL_RUNNER_INPUT=$input_fifo" \
        "$ISABELLE_CMD" ML_process -l "$LOGIC" -f "$MODEL_ML" -f "$DISPATCH_ML" -f "$RUNNER_ML"
      exit 0
    fi
    # `isabelle ML_process` closes the ML process's standard input, so records
    # travel through a FIFO that a forwarder fills from this script's standard
    # input. Standard output is the protocol channel: everything before
    # `#ready` is loader noise the client discards; standard error stays
    # diagnostic. End of input on our side closes the FIFO and ends the loop;
    # if the ML process dies first, the forwarder is stopped.
    mkfifo -- "$input_fifo"
    # A background job's stdin defaults to /dev/null; hand it ours explicitly.
    exec 3<&0
    cat <&3 >"$input_fifo" &
    forwarder_pid=$!
    status=0
    ISABELLE_MODEL_RUNNER_MODE=resident \
      ISABELLE_MODEL_RUNNER_INPUT="$input_fifo" \
      "$ISABELLE_CMD" ML_process -l "$LOGIC" -f "$MODEL_ML" -f "$DISPATCH_ML" -f "$RUNNER_ML" || status=$?
    kill "$forwarder_pid" 2>/dev/null || true
    wait "$forwarder_pid" 2>/dev/null || true
    exit "$status"
    ;;
esac

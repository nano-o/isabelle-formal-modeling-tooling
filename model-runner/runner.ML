(*  Generic model runner: the plumbing every differential harness needs and
    every project gets subtly wrong on its own.

    Loaded by `isabelle ML_process` after the exported code and the project's
    dispatch file, which must define

      structure Model_Dispatch : sig
        exception Reject of string
        val dispatch : string -> string
      end

    `dispatch` receives one non-comment input line, opaque to the runner, and
    returns the result suffix; the runner echoes the line, a tab, and the
    suffix. `Reject` reports a malformed record (a parse or range failure).
    Any other exception is a dispatch or model crash.

    Framing: lines end in LF, optionally CR LF; a trailing CR is stripped.
    Blank lines and lines starting with `#` are comments and are echoed
    unchanged, so comment structure survives into the result file and the
    row count of the two files can be compared by the caller.

    Modes, chosen by ISABELLE_MODEL_RUNNER_MODE:

      batch     read ISABELLE_MODEL_RUNNER_INPUT, write
                ISABELLE_MODEL_RUNNER_OUTPUT. A rejected record or a crash
                aborts the whole run with a message naming the line: the
                output is never a partial answer that looks complete.

      resident  print `#ready`, then answer one line of input per line of
                standard output until end of file. Input is the file named by
                ISABELLE_MODEL_RUNNER_INPUT (a FIFO the driver fills from its
                own standard input, because `isabelle ML_process` closes the
                ML process's standard input), or standard input if unset. A
                rejected record answers `#reject<TAB>LINE<TAB>MESSAGE`, a
                crash answers `#error<TAB>LINE<TAB>MESSAGE`; a blank line
                answers `#`. All keep the one-line-per-line alignment.
                Clients discard everything before `#ready`.
*)

structure Model_Runner =
struct

fun message text = TextIO.output (TextIO.stdErr, "model-runner: " ^ text ^ "\n")

fun fail text = (message text; OS.Process.exit OS.Process.failure)

fun strip_line_end line =
  let
    val without_lf =
      if String.size line > 0 andalso
          String.sub (line, String.size line - 1) = #"\n"
      then String.substring (line, 0, String.size line - 1)
      else line
  in
    if String.size without_lf > 0 andalso
        String.sub (without_lf, String.size without_lf - 1) = #"\r"
    then String.substring (without_lf, 0, String.size without_lf - 1)
    else without_lf
  end

fun is_comment line = line = "" orelse String.isPrefix "#" line

datatype answer =
    Row of string
  | Rejected of string
  | Crashed of string

fun answer line =
  if is_comment line then Row line
  else
    Row (line ^ "\t" ^ Model_Dispatch.dispatch line)
      handle Model_Dispatch.Reject text => Rejected text
           | exn => Crashed (General.exnMessage exn)

fun located line_number text = "line " ^ Int.toString line_number ^ ": " ^ text

fun batch input_path output_path =
  let
    val input = TextIO.openIn input_path
      handle IO.Io _ => fail ("cannot open input: " ^ input_path)
    val output = TextIO.openOut output_path
      handle IO.Io _ => fail ("cannot open output: " ^ output_path)
    fun loop line_number =
      (case TextIO.inputLine input of
        NONE => ()
      | SOME raw_line =>
          (case answer (strip_line_end raw_line) of
            Row text => (TextIO.output (output, text ^ "\n"); loop (line_number + 1))
          | Rejected text => fail (located line_number ("rejected record: " ^ text))
          | Crashed text => fail (located line_number ("dispatch failed: " ^ text))))
  in
    loop 1;
    TextIO.closeIn input;
    TextIO.closeOut output
  end

fun resident input_path =
  let
    fun emit text = (TextIO.output (TextIO.stdOut, text ^ "\n"); TextIO.flushOut TextIO.stdOut)
    val _ = emit "#ready"
    val input =
      (case input_path of
        NONE => TextIO.stdIn
      | SOME path => TextIO.openIn path
          handle IO.Io _ => fail ("cannot open input: " ^ path))
    fun loop line_number =
      (case TextIO.inputLine input of
        NONE => ()
      | SOME raw_line =>
          let
            val _ =
              (case answer (strip_line_end raw_line) of
                (* The ML_process wrapper drops empty output lines; keep
                   one line per line by answering a blank line with `#`. *)
                Row text => emit (if text = "" then "#" else text)
              | Rejected text =>
                  emit ("#reject\t" ^ Int.toString line_number ^ "\t" ^ text)
              | Crashed text =>
                  emit ("#error\t" ^ Int.toString line_number ^ "\t" ^ text))
          in loop (line_number + 1) end)
  in
    loop 1
  end

val _ =
  (case OS.Process.getEnv "ISABELLE_MODEL_RUNNER_MODE" of
    SOME "batch" =>
      (case (OS.Process.getEnv "ISABELLE_MODEL_RUNNER_INPUT",
             OS.Process.getEnv "ISABELLE_MODEL_RUNNER_OUTPUT") of
        (SOME input_path, SOME output_path) => batch input_path output_path
      | (NONE, _) => fail "ISABELLE_MODEL_RUNNER_INPUT is not set"
      | (_, NONE) => fail "ISABELLE_MODEL_RUNNER_OUTPUT is not set")
  | SOME "resident" => resident (OS.Process.getEnv "ISABELLE_MODEL_RUNNER_INPUT")
  | SOME other => fail ("unknown ISABELLE_MODEL_RUNNER_MODE: " ^ other)
  | NONE => fail "ISABELLE_MODEL_RUNNER_MODE is not set")

end

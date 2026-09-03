(* Fixture dispatch for the model runner: converts and routes, never decides.
   Record: v1<TAB>succ_bounded<TAB>CASE_ID<TAB>N  ->  OK<TAB>RESULT *)
structure Model_Dispatch =
struct

exception Reject of string

fun parse_nat text =
  (case IntInf.fromString text of
    SOME value => if value < 0 then raise Reject ("negative nat: " ^ text) else value
  | NONE => raise Reject ("invalid decimal: " ^ text))

fun dispatch line =
  (case String.fields (fn c => c = #"\t") line of
    ["v1", "succ_bounded", _, n_text] =>
      let
        val n = Fixture.nat_of_integer (parse_nat n_text)
        val result = Fixture.integer_of_nat (Fixture.succ_bounded n)
      in "OK\t" ^ IntInf.toString result end
  | ["v1", "crash", _, _] => raise Fail "deliberate dispatch crash"
  | "v1" :: tag :: _ => raise Reject ("unknown tag: " ^ tag)
  | _ => raise Reject "malformed record")

end

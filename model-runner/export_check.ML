(*  Export check: is the executable code-level model the proved one?

    Run by scripts/export-check.sh inside `isabelle ML_process -l SESSION`
    after the session is built, so every session theory is loaded; the file
    is evaluated in the export theory's ML context so that HOL's tool
    structures (Code_Preproc, Code_Symbol, Typedef) are visible, and it uses
    no antiquotations. Parameters come from the environment:

      ISABELLE_EXPORT_CHECK_SESSION      the project's build session
      ISABELLE_EXPORT_CHECK_EXPORT_NAME  Session.Theory:path of the export
      ISABELLE_EXPORT_CHECK_AUDIT        named_theorems collection to audit
      ISABELLE_EXPORT_CHECK_ALLOWLIST    space-separated code symbols whose
                                         project-declared code_printing or
                                         code_reserved is accepted
      ISABELLE_EXPORT_CHECK_VERBOSE      set to list every audited theorem

    Part one, the dependency audit: for every code equation of every constant
    in the exported program, and for every fact of the audit collection,
    collect the oracles and the named theorems the derivation depends on.
    Any oracle fails (a `sorry` is the skip_proof oracle). Any dependency on
    an axiom declared by a project theory fails unless the axiom is
    definitional: a `definition`-style axiom registered in the theory's Defs,
    the type_definition axiom of a typedef registered with the Typedef
    package (datatypes and records included), or the contentless arity axiom
    HOL adds for every new type in class `type`. Axioms of theories outside the
    project session are the trusted baseline: the pinned Isabelle
    distribution and any library the session imports.

    Part two, the source check: no `code_printing` or `code_reserved`
    declaration in a project theory may name a symbol of the exported
    program (constant, type constructor, class, class relation, instance) or
    inject a module, unless allowlisted. These overrides never appear as
    theorem dependencies, so only the source can reveal them. Standard
    library mappings live in distribution theories, which are not scanned.

    Limits, stated rather than hidden: the check cannot vouch for the code
    generator, Poly/ML, or the project's dispatch ML. Heaps are built with
    record_proofs at its default, which records theorem names and oracles
    but not full proof terms; an axiom used from ML without ever being
    stored as a named fact is invisible at that level.
*)

structure Export_Check =
struct

fun getenv name = OS.Process.getEnv name

fun require_env name =
  (case getenv name of
    SOME value => value
  | NONE => error (name ^ " is not set"))

val session = require_env "ISABELLE_EXPORT_CHECK_SESSION"
val export_name = require_env "ISABELLE_EXPORT_CHECK_EXPORT_NAME"
val audit_collection = require_env "ISABELLE_EXPORT_CHECK_AUDIT"
val allowlist =
  (case getenv "ISABELLE_EXPORT_CHECK_ALLOWLIST" of
    SOME text => String.tokens Char.isSpace text
  | NONE => [])
val verbose = is_some (getenv "ISABELLE_EXPORT_CHECK_VERBOSE")

val (export_theory_name, export_path) =
  (case space_explode ":" export_name of
    [theory_name, path] => (theory_name, path)
  | _ => error ("export_name must be Session.Theory:path, found " ^ export_name))

val export_file_prefix =
  let
    val base = List.last (space_explode "/" export_path)
  in
    (case space_explode "." base of
      [] => base
    | parts => space_implode "." (take (length parts - 1) parts))
  end

fun out text = Output.physical_stdout (text ^ "\n")

(* Session theories and the merged context *)

val project_theory_names =
  filter (fn name => Resources.theory_qualifier name = session) (Thy_Info.get_names ())

val _ =
  null project_theory_names andalso
    error ("no loaded theory belongs to session " ^ session ^
      " (is the heap built and -l " ^ session ^ " in effect?)")

val project_theories = map Thy_Info.get_theory project_theory_names

val export_theory =
  (case Thy_Info.lookup_theory export_theory_name of
    SOME thy => thy
  | NONE => error ("export theory not loaded: " ^ export_theory_name))

(* One theory importing every session theory, finished so theorems can be
   transferred into it: the audit collection may be spread over branches of
   the import graph that no single session theory sees. *)
val merged_theory =
  Theory.end_theory
    (Theory.begin_theory (session ^ ".Export_Check", Position.none) project_theories)

val ctxt = Proof_Context.init_global merged_theory

val project_base_names =
  Symtab.make_set (map Context.theory_base_name project_theories)

fun is_project_name name =
  (case Long_Name.explode name of
    base :: _ :: _ => Symtab.defined project_base_names base
  | _ => false)

(* Theory sources, tokenized with the theory's own keywords *)

fun theory_source thy =
  let
    val path =
      Path.append (Resources.master_directory thy)
        (Resources.thy_path (Path.basic (Context.theory_base_name thy)))
  in
    (path, File.read path)
  end

fun command_spans thy =
  let
    val (path, text) = theory_source thy
    val keywords = Thy_Header.get_keywords thy
    val tokens = Token.explode keywords (Position.file (Path.implode path)) text
  in
    map_filter (fn span =>
      let
        val content = filter Token.is_proper (Command_Span.content span)
      in
        (case content of
          command :: rest =>
            if Token.is_command command
            then SOME (Token.content_of command, rest, Token.pos_of command)
            else NONE
        | [] => NONE)
      end) (Outer_Syntax.parse_spans tokens)
  end

fun is_keyword word token = Token.keyword_with (fn x => x = word) token

(* The exported constants: the export_code command whose file_prefix matches *)

fun export_code_consts () =
  let
    val spans = command_spans export_theory
    fun const_exprs tokens =
      let
        val tokens' =
          (case tokens of
            first :: rest => if is_keyword "open" first then rest else tokens
          | [] => [])
        val exprs =
          take_prefix (fn token => not (is_keyword "in" token orelse is_keyword "checking" token))
            tokens'
      in
        map Token.content_of exprs
      end
    fun file_prefix_of tokens =
      let
        fun find (token :: value :: rest) =
              if is_keyword "file_prefix" token then SOME (Token.content_of value) else find (value :: rest)
          | find _ = NONE
      in find tokens end
    val candidates =
      map_filter (fn (command, tokens, pos) =>
        if command = "export_code" andalso file_prefix_of tokens = SOME export_file_prefix
        then SOME (const_exprs tokens, pos) else NONE) spans
  in
    (case candidates of
      [(exprs, _)] => Code_Thingol.read_const_exprs ctxt exprs
    | [] =>
        error ("no export_code command with file_prefix " ^ quote export_file_prefix ^
          " in " ^ export_theory_name)
    | _ => error ("several export_code commands with file_prefix " ^ quote export_file_prefix))
  end

(* Dependency audit *)

val axiom_names =
  Symtab.make_set (map #1 (Theory.all_axioms_of merged_theory))

val definitional_axioms =
  Symtab.make_set
    (map_filter #def (maps #2 (Defs.all_specifications_of (Theory.defs_of merged_theory))))

(* A typedef's axiom reads
     OFCLASS(?'a, type_class) ... ==> EX x. x : A ==> type_definition Rep Abs A
   and is accepted only when the Typedef package registered it under that
   very name for the abstract type; datatypes and records go through it. *)
fun typedef_axiom name =
  (case AList.lookup (op =) (Theory.all_axioms_of merged_theory) name of
    SOME prop =>
      (case try (HOLogic.dest_Trueprop o Logic.strip_imp_concl) prop of
        SOME (Const ("Typedef.type_definition", _) $ _ $ abs $ _) =>
          (case try (dest_Type o range_type o fastype_of) abs of
            SOME (tyco, _) =>
              exists (fn ({axiom_name, ...}, _) => axiom_name = name)
                (Typedef.get_info_global merged_theory tyco)
          | NONE => false)
      | _ => false)
  | NONE => false)

(* HOL declares every new type constructor in the trivial class `type`:
     OFCLASS(?'a, type_class) ... ==> OFCLASS(?'a t, type_class)
   These arity axioms carry no content and are accepted as such. *)
fun type_class_arity_axiom name =
  (case AList.lookup (op =) (Theory.all_axioms_of merged_theory) name of
    SOME prop =>
      let
        val of_type_class = fn t =>
          (case try Logic.dest_of_class t of
            SOME (_, class) => class = "HOL.type"
          | NONE => false)
      in
        of_type_class (Logic.strip_imp_concl prop) andalso
        forall of_type_class (Logic.strip_imp_prems prop)
      end
  | NONE => false)

datatype axiom_status =
  Trusted_Baseline | Definitional | Typedef_Axiom | Type_Class_Arity | Unjustified

fun classify_axiom name =
  if not (is_project_name name) then Trusted_Baseline
  else if Symtab.defined definitional_axioms name then Definitional
  else if typedef_axiom name then Typedef_Axiom
  else if type_class_arity_axiom name then Type_Class_Arity
  else Unjustified

fun dependency_names thm =
  let
    val bodies = Thm.proof_bodies_of [thm]
    val own = Thm_Name.short (Thm.derivation_name thm)
    val names =
      Proofterm.fold_body_thms
        (fn {thm_name, ...} => Symtab.insert_set (Thm_Name.short thm_name)) bodies Symtab.empty
  in
    (if own = "" then names else Symtab.insert_set own names) |> Symtab.keys
  end

fun audit_thm (label, raw_thm) =
  let
    (* Stored theorems carry a trimmed certificate; give them the theory back. *)
    val thm = Thm.transfer merged_theory raw_thm
    val oracles = map (#1 o #1) (Thm_Deps.all_oracles [thm])
    val axioms = filter (Symtab.defined axiom_names) (dependency_names thm)
    val bad_axioms = filter (fn name => classify_axiom name = Unjustified) axioms
    val problems =
      map (fn oracle => label ^ ": depends on oracle " ^ oracle) oracles @
      map (fn name => label ^ ": depends on unjustified axiom " ^ name ^
        " (declared by a project theory; not a definition, typedef, or type-class arity)")
        bad_axioms
    val _ =
      if verbose then
        out ("  audited " ^ label ^ ": " ^ string_of_int (length axioms) ^ " axioms" ^
          (if null oracles then "" else ", oracles: " ^ commas oracles))
      else ()
  in problems end

fun code_equation_thms eqngr =
  maps (fn const =>
    (case Code.equations_of_cert merged_theory (Code_Preproc.cert eqngr const) of
      (_, SOME eqns) =>
        map_filter (fn (_, (SOME thm, _)) => SOME ("code equation of " ^ const, thm) | _ => NONE) eqns
    | (_, NONE) => [])) (Code_Preproc.all eqngr)

fun audit_collection_thms () =
  let
    val name = Named_Theorems.check ctxt (audit_collection, Position.none)
      handle ERROR msg =>
        error ("audit collection " ^ quote audit_collection ^ " not found in session " ^
          session ^ ": declare it with named_theorems, or set audit_collection.\n" ^ msg)
    val thms = Named_Theorems.get ctxt name
  in
    map (fn thm =>
      (audit_collection ^ " fact " ^ Thm_Name.short (Thm.derivation_name thm), thm)) thms
  end

(* Source check *)

fun program_symbols consts =
  let
    val program = Code_Thingol.consts_program ctxt consts
  in Code_Symbol.Graph.keys program end

fun symbol_string (Code_Symbol.Constant c) = "constant " ^ c
  | symbol_string (Code_Symbol.Type_Constructor tyco) = "type_constructor " ^ tyco
  | symbol_string (Code_Symbol.Type_Class class) = "type_class " ^ class
  | symbol_string (Code_Symbol.Class_Relation (sub, super)) = "class_relation " ^ sub ^ " < " ^ super
  | symbol_string (Code_Symbol.Class_Instance (tyco, class)) = "class_instance " ^ tyco ^ " :: " ^ class
  | symbol_string (Code_Symbol.Module name) = "code_module " ^ name

fun symbol_key (Code_Symbol.Constant c) = c
  | symbol_key (Code_Symbol.Type_Constructor tyco) = tyco
  | symbol_key (Code_Symbol.Type_Class class) = class
  | symbol_key (Code_Symbol.Class_Relation (sub, super)) = sub ^ "<" ^ super
  | symbol_key (Code_Symbol.Class_Instance (tyco, class)) = tyco ^ "::" ^ class
  | symbol_key (Code_Symbol.Module name) = name

val symbol_kinds =
  ["constant", "type_constructor", "type_class", "class_relation", "class_instance", "code_module"]

fun is_arrow token = is_keyword "\<rightharpoonup>" token orelse is_keyword "=>" token

fun read_tyco name = (case Proof_Context.read_type_name {proper = true, strict = false} ctxt name of
    Type (tyco, _) => tyco
  | _ => error ("not a type constructor: " ^ name))

fun read_symbol kind names =
  (case (kind, names) of
    ("constant", [c]) => SOME (Code_Symbol.Constant (Code.read_const ctxt c))
  | ("type_constructor", [t]) => SOME (Code_Symbol.Type_Constructor (read_tyco t))
  | ("type_class", [c]) => SOME (Code_Symbol.Type_Class (Proof_Context.read_class ctxt c))
  | ("class_relation", [sub, "<", super]) =>
      SOME (Code_Symbol.Class_Relation (Proof_Context.read_class ctxt sub, Proof_Context.read_class ctxt super))
  | ("class_instance", [t, "::", c]) =>
      SOME (Code_Symbol.Class_Instance (read_tyco t, Proof_Context.read_class ctxt c))
  | ("code_module", [m]) => SOME (Code_Symbol.Module m)
  | _ => NONE)
  handle ERROR _ => NONE

(* Each pragma is KIND SYMBOL (rightharpoonup | =>) targets, separated by `|`. *)
fun printing_symbols tokens =
  let
    fun collect [] acc = rev acc
      | collect (token :: rest) acc =
          (case find_first (fn kind => is_keyword kind token) symbol_kinds of
            SOME kind =>
              let
                val (names, rest') = chop_prefix (not o is_arrow) rest
                val symbol = read_symbol kind (map Token.content_of names)
              in collect rest' (the_list symbol @ acc) end
          | NONE => collect rest acc)
  in collect tokens [] end

fun is_name_like token =
  exists (fn kind => Token.is_kind kind token)
    [Token.Ident, Token.Long_Ident, Token.Sym_Ident, Token.String, Token.Alt_String, Token.Cartouche]

fun source_problems program_keys =
  let
    val exported = Symtab.make_set (map symbol_key program_keys)
    val allowed = Symtab.make_set allowlist
    fun theory_problems thy =
      maps (fn (command, tokens, pos) =>
        let
          val where_ = Context.theory_base_name thy ^ Position.here pos
        in
          if command = "code_printing" then
            map_filter (fn symbol =>
              let val key = symbol_key symbol in
                if Symtab.defined allowed key then NONE
                else if (case symbol of Code_Symbol.Module _ => true | _ => false) then
                  SOME (where_ ^ ": code_printing injects " ^ symbol_string symbol ^
                    " into the exported program")
                else if Symtab.defined exported key then
                  SOME (where_ ^ ": code_printing overrides " ^ symbol_string symbol ^
                    " of the exported program")
                else NONE
              end) (printing_symbols tokens)
          else if command = "code_reserved" then
            map_filter (fn word =>
              if Symtab.defined allowed word then NONE
              else SOME (where_ ^ ": code_reserved " ^ word ^
                " in a project theory (allowlist it if intended)"))
              (filter is_name_like tokens |> map Token.content_of)
          else []
        end) (command_spans thy)
  in maps theory_problems project_theories end

(* Main *)

val _ =
  let
    val _ = out ("export check: session " ^ session ^ ", export " ^ export_name)
    val consts = export_code_consts ()
    val _ = out ("  exported constants: " ^ string_of_int (length consts))
    val {eqngr, ...} = Code_Preproc.obtain true {ctxt = ctxt, consts = consts, terms = []}
    val equation_thms = code_equation_thms eqngr
    val _ = out ("  code equations audited: " ^ string_of_int (length equation_thms) ^
      " over " ^ string_of_int (length (Code_Preproc.all eqngr)) ^ " constants")
    val audit_thms = audit_collection_thms ()
    val _ = out ("  " ^ audit_collection ^ " facts audited: " ^ string_of_int (length audit_thms))
    val dependency_problems = maps audit_thm (equation_thms @ audit_thms)
    val program_keys = program_symbols consts
    val _ = out ("  program symbols: " ^ string_of_int (length program_keys))
    val printing_problems = source_problems program_keys
    val problems = dependency_problems @ printing_problems
  in
    if null problems then
      out "export check: OK (no oracles, no unjustified project axioms, no overriding code_printing)"
    else
      (List.app (fn p => out ("  FAIL " ^ p)) (distinct (op =) problems);
       out ("export check: FAILED with " ^ string_of_int (length (distinct (op =) problems)) ^ " problem(s)");
       OS.Process.exit OS.Process.failure)
  end

end

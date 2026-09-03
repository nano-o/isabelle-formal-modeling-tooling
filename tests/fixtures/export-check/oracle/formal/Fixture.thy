theory Fixture
  imports Main
begin

text \<open>A code equation proved by a declared oracle: every file looks like a
proof, and the exported code computes something the definition does not.\<close>

named_theorems export_audit "facts the export check audits"

definition succ_bounded :: "nat \<Rightarrow> nat" where
  "succ_bounded n = (if n < 1000 then n + 1 else n)"

lemma succ_bounded_ge [export_audit]: "succ_bounded n \<ge> n"
  by (simp add: succ_bounded_def)

oracle trust_me = \<open>fn ct => ct\<close>

lemma succ_bounded_code [code]: "succ_bounded n = n + 1"
  by (tactic \<open>resolve_tac \<^context> [trust_me \<^cprop>\<open>succ_bounded n = n + 1\<close>] 1\<close>)

export_code succ_bounded integer_of_nat nat_of_integer in SML
  module_name Fixture file_prefix fixture

end

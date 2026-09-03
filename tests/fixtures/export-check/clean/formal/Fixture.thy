theory Fixture
  imports Main
begin

text \<open>A clean export: a definition, an audited fact proved from it, no overrides.\<close>

named_theorems export_audit "facts the export check audits"

definition succ_bounded :: "nat \<Rightarrow> nat" where
  "succ_bounded n = (if n < 1000 then n + 1 else n)"

lemma succ_bounded_ge [export_audit]: "succ_bounded n \<ge> n"
  by (simp add: succ_bounded_def)

export_code succ_bounded integer_of_nat nat_of_integer in SML
  module_name Fixture file_prefix fixture

end

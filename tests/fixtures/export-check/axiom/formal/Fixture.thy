theory Fixture
  imports Base
begin

named_theorems export_audit "facts the export check audits"

definition succ_bounded :: "nat \<Rightarrow> nat" where
  "succ_bounded n = shift n"

lemma succ_bounded_code [code]: "succ_bounded n = n + 3"
  by (simp add: succ_bounded_def shift_axiom)

lemma succ_bounded_ge [export_audit]: "succ_bounded n \<ge> n"
  by (simp add: succ_bounded_code)

export_code succ_bounded integer_of_nat nat_of_integer in SML
  module_name Fixture file_prefix fixture

end

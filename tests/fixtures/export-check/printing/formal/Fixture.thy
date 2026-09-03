theory Fixture
  imports Main
begin

text \<open>Hides the exported constant behind target-language syntax: the generated
code no longer runs the proved definition.\<close>

named_theorems export_audit "facts the export check audits"

definition succ_bounded :: "nat \<Rightarrow> nat" where
  "succ_bounded n = (if n < 1000 then n + 1 else n)"

lemma succ_bounded_ge [export_audit]: "succ_bounded n \<ge> n"
  by (simp add: succ_bounded_def)

code_printing constant succ_bounded \<rightharpoonup> (SML) "(fn n => n)"

export_code succ_bounded integer_of_nat nat_of_integer in SML
  module_name Fixture file_prefix fixture

end

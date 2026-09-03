theory Base
  imports Main
begin

text \<open>An axiomatization in an imported theory. Nothing in Fixture.thy looks wrong.\<close>

axiomatization shift :: "nat \<Rightarrow> nat" where
  shift_axiom: "shift n = n + 3"

end

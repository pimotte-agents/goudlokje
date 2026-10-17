import Goudlokje.Linter
import Verbose.English.All

/-! Probes see the goal as it was before the step, not with assignments made by later steps. -/

set_option linter.unusedTactic false
set_option goudlokje.probes "decide"
set_option linter.goudlokje.rawTactic false
set_option linter.goudlokje.typeAscription false

/-
:::input
-/

-- Step 2 works on the goal `?w + 0 = 2`, whose `?w` only step 3 assigns. Before step 2 the goal
-- still contains `?w`, so `decide` cannot close it there.
#guard_msgs in
Exercise "later assignment"
  Given:
  Assume:
  Conclusion: ∃ n : ℕ, n + 0 = 2 ∧ n = 2
Proof:
  refine ⟨?w, ?h₁, ?h₂⟩
  case h₁ =>
    show _ + 0 = 2
    exact (rfl : 2 + 0 = 2)
  case h₂ => rfl
QED

/-
:::
-/

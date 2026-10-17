-- The typeAscription check reports type annotations in Verbose proofs as warnings, recorded as
-- expected in .test.json by `update`. It only looks at the syntax of the proof steps: binders in
-- statements and Verbose tactics that elaborate to type ascriptions internally are not reported.
--
-- Findings with the fixture probes (`decide`, `tauto`, `omega`, `norm_num`, `simp`, `ring`) are in
-- expected/TypeAscription.test.json; raw-tactic errors in expected/errors.txt. The last three
-- examples contain no typeAscription entry.
import Goudlokje
import Verbose.English.All
import WaterproofGenre
open WaterproofGenre

set_option linter.unusedTactic false

#doc (WaterproofGenre) "typeAscription check" =>

::::multilean
:::input
```lean
set_option linter.unusedTactic false

-- `Fix n : ℕ` is a type annotation (step 2).
example : (∀ n : ℕ, n + 0 = n) ∧ True := by
  Let's first prove that ∀ n : ℕ, n + 0 = n
  Fix n : ℕ
  ring
  Let's now prove that True
  trivial

-- `(trivial : True)` is a type annotation (step 2).
example : True ∧ True := by
  Let's first prove that True
  exact (trivial : True)
  Let's now prove that True
  trivial
```
:::
::::

::::multilean
:::input
```lean
set_option linter.unusedTactic false

-- `∀ n : ℕ` is a binder in the statement, and `Fix n` has no type.
example : ∀ n : ℕ, n + 0 = n := by
  Fix n
  ring

-- `Let's prove that 2 works` elaborates to a type ascription internally.
example : ∃ k : ℕ, 4 = 2 * k := by
  Let's prove that 2 works
  rfl

-- `Let's first/now prove that` state goals, without type annotations.
example : 1 + 1 = 2 ∧ 2 + 2 = 4 := by
  Let's first prove that 1 + 1 = 2
  norm_num
  Let's now prove that 2 + 2 = 4
  norm_num
```
:::
::::

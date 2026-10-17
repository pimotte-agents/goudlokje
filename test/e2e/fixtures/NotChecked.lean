-- Proofs without Lean Verbose are not checked at all: the rawTactic check, the sorry check and the
-- typeAscription check do not apply to them, even in an input area (`decide` could shortcut some of
-- these proofs). Nothing outside input areas is checked either. No .test.json, no errors.
import Goudlokje
import Verbose.English.All
import WaterproofGenre
import Mathlib.Tactic.NormNum
open WaterproofGenre

set_option linter.unusedTactic false

#doc (WaterproofGenre) "Proofs without Verbose" =>

::::multilean
:::input
```lean
set_option linter.unusedTactic false

-- Not a Verbose proof: not checked.
example : True ∧ True := by
  constructor
  · trivial
  · trivial
```
:::
::::

::::multilean
:::input
```lean
set_option warn.sorry false

-- Not a Verbose proof: the `sorry` is not reported.
example : True := by
  sorry

-- Not a Verbose proof: `(trivial : True)` is not reported.
example : True ∧ True := by
  exact And.intro (trivial : True) trivial
```
:::
::::

::::multilean
:::input
```lean
-- It imports nothing beyond the core Lean 4 prelude.

/-- A one-step proof: never a shortcut, and not a Verbose proof anyway. -/
theorem onePlusOneEqTwo : 1 + 1 = 2 := by
  rfl

/-- `decide` could close the goal at `constructor`, but this is not a Verbose proof. -/
theorem twoStepAnd : True ∧ True := by
  constructor
  · trivial
  · trivial
```
:::
::::

```lean
-- Not checked (no Verbose, no input area).
example : 1 + 1 = 2 := by
  norm_num
```

```lean
-- Not checked (no Verbose, no input area).
example : 2 + 2 = 4 ∧ 3 + 3 = 6 := by
  constructor
  · norm_num
  · norm_num
```

```lean
set_option linter.unusedTactic false
-- Not in an input area: not checked.
example : 1 + 1 = 2 ∧ 2 + 2 = 4 := by
  Let's first prove that 1 + 1 = 2
  norm_num
  Let's now prove that 2 + 2 = 4
  norm_num
```

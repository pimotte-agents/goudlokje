import Goudlokje
import Verbose.English.All

/-! Tests for `Alternative solution:`, and for how the linters treat alternative solutions. -/

set_option linter.unusedTactic false
set_option linter.unusedVariables false

-- An alternative solution that proves the goal is accepted, and the reference solution continues
-- from the same goal.
#guard_msgs in
example (p q : Prop) (hp : p) (hq : q) : p ∧ q := by
  Alternative solution:
    exact ⟨hp, hq⟩
  constructor
  · exact hp
  · exact hq

-- An alternative solution that leaves goals open is an error; the reference solution still runs.
/--
error: the alternative solution does not prove the goal; unsolved goals:
case right
p q : Prop
hp : p
hq : q
⊢ q
-/
#guard_msgs in
example (p q : Prop) (hp : p) (hq : q) : p ∧ q := by
  Alternative solution:
    constructor
    · exact hp
  exact ⟨hp, hq⟩

-- An error in an alternative solution is reported; the reference solution still runs.
/--
error: Type mismatch
  hq
has type
  q
but is expected to have type
  p
-/
#guard_msgs in
example (p q : Prop) (hp : p) (hq : q) : p := by
  Alternative solution:
    exact hq
  exact hp

/-
:::input
-/

-- In input areas, the steps of an alternative solution are checked like the others: they count
-- in the step numbering (`Alternative solution:` itself is not a step, its steps are 1 and 2),
-- raw Lean tactics and `sorry` in them are reported, and probes run on them, separately from the
-- reference solution.
set_option goudlokje.probes "decide" in
/--
error: `decide` closes the goal at step 1 of exercise "alternatives", so the rest of this part of the proof can be skipped

If this is intended, record it with `goudlokje update`.

Note: This linter can be disabled with `set_option linter.goudlokje.shortcut false`
---
error: `decide` closes the goal at step 3 of exercise "alternatives", so the rest of this part of the proof can be skipped

If this is intended, record it with `goudlokje update`.

Note: This linter can be disabled with `set_option linter.goudlokje.shortcut false`
---
error: raw Lean tactic `norm_num` at step 2 of exercise "alternatives"; use a Lean Verbose tactic instead

Tactics can be allowed for a whole project with the option `goudlokje.allowedTactics`.

Note: This linter can be disabled with `set_option linter.goudlokje.rawTactic false`
---
error: raw Lean tactic `norm_num` at step 4 of exercise "alternatives"; use a Lean Verbose tactic instead

Tactics can be allowed for a whole project with the option `goudlokje.allowedTactics`.

Note: This linter can be disabled with `set_option linter.goudlokje.rawTactic false`
-/
#guard_msgs in
Exercise "alternatives"
  Given:
  Assume:
  Conclusion: 1 + 1 = 2
Proof:
  Alternative solution:
    Let's prove that 1 + 1 = 2
    norm_num
  Let's prove that 1 + 1 = 2
  norm_num
QED

/--
error: `sorry` at step 1 of exercise "alternative with sorry"

If this exercise may contain `sorry`, allow it with `goudlokje update`.

Note: This linter can be disabled with `set_option linter.goudlokje.sorry false`
-/
#guard_msgs in
Exercise "alternative with sorry"
  Given: (p : Prop) (hp : p)
  Assume:
  Conclusion: p
Proof:
  Alternative solution:
    sorry
  We conclude by hypothesis
QED

/-
:::
-/

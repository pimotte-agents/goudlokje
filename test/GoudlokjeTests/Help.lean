import Goudlokje.Linter
import Verbose.English.All

/-! Tests for the help check. -/

set_option linter.unusedTactic false
set_option linter.unusedVariables false
set_option goudlokje.help "help"

open Goudlokje.Checks in
#guard containsHint #["nothing to say"] ["I have nothing to say about this goal.", "Try this"]
open Goudlokje.Checks in
#guard !containsHint #["nothing to say"] ["I have nothing to say about this goal."]
open Goudlokje.Checks in
#guard !containsHint #["nothing to say"] []

-- Outside input areas nothing is checked.
#guard_msgs in
example (p : Prop) (hp : p) : p := by
  We conclude by hypothesis

/-
:::input
-/

-- `help` has a hint for the implication (step 1), but nothing to say about the atom `p` (step 2).
/--
error: `help` gives no hint at step 2 of exercise "atom"

If this is intended, record it with `goudlokje update`.

Note: This linter can be disabled with `set_option linter.goudlokje.help false`
-/
#guard_msgs in
Exercise "atom"
  Given: (p : Prop)
  Assume:
  Conclusion: p → p
Proof:
  Assume that p
  We conclude by hypothesis
QED

-- A help tactic that fails gives no hint.
set_option goudlokje.help "fail" in
/--
error: `fail` gives no hint at step 1 of exercise "failing help"

If this is intended, record it with `goudlokje update`.

Note: This linter can be disabled with `set_option linter.goudlokje.help false`
-/
#guard_msgs in
Exercise "failing help"
  Given: (p : Prop)
  Assume: (hp : p)
  Conclusion: p
Proof:
  We conclude by hypothesis
QED

-- A finding recorded in `Help.test.json` is not reported.
#guard_msgs in
Exercise "recorded"
  Given: (p : Prop)
  Assume: (hp : p)
  Conclusion: p
Proof:
  We conclude by hypothesis
QED

-- Any information message other than the no-hint messages is a hint.
set_option goudlokje.help "trace \"look at the hypotheses\"" in
#guard_msgs in
Exercise "custom help"
  Given: (p : Prop)
  Assume: (hp : p)
  Conclusion: p
Proof:
  We conclude by hypothesis
QED

-- The help check is off without a help tactic.
set_option goudlokje.help "" in
#guard_msgs in
Exercise "no help tactic"
  Given: (p : Prop)
  Assume: (hp : p)
  Conclusion: p
Proof:
  We conclude by hypothesis
QED

/-
:::
-/

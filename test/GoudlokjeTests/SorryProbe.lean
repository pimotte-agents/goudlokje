import Goudlokje.Linter
import Verbose.English.All

/-! A probe only closes a goal if it does so without errors and without `sorry`. -/

set_option linter.unusedTactic false
set_option linter.goudlokje.rawTactic false

/-
:::input
-/

-- `exact foo` fails to elaborate (`foo` is unknown); Lean recovers with `sorry`, which must not
-- count as closing the goal. `sorry` itself does not count either.
set_option goudlokje.probes "exact foo;; sorry;; exact sorry" in
#guard_msgs in
Exercise "probes with errors"
  Given:
  Assume:
  Conclusion: 1 + 1 = 2
Proof:
  show 1 + 1 = 2
  norm_num
QED

/-
:::
-/

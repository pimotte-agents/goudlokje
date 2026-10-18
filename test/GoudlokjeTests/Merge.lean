import Goudlokje.Linter
import Verbose.English.All

/-! Tests for the `mergeableSince` check. -/

set_option linter.unusedTactic false
set_option linter.unusedVariables false

open Goudlokje.Checks in
#guard joinFacts #["a", "b", "c"] == "a, b and c"
open Goudlokje.Checks in
#guard joinFacts #["a"] == "a"
open Goudlokje.Checks in
#guard mergeFacts #["a"] #["b", "c"] #["b", "d", "a"] == some #["a", "d"]
open Goudlokje.Checks in
#guard mergeFacts #["a", "b"] #["c"] #["d", "e", "f"] == none

-- Outside input areas nothing is checked.
#guard_msgs in
example (p q : Prop) (h : p ∧ q) : q ∧ p := by
  Since p ∧ q we get that p and q
  Since p and q we conclude that q ∧ p

/-
:::input
-/

-- A `get that` step followed by a `conclude that` step that the merged step proves.
/--
error: steps 1 and 2 of exercise "conclude" can be merged into one step: `Since p ∧ q we conclude that q ∧ p`

If this is intended, record it with `goudlokje update`.

Note: This linter can be disabled with `set_option linter.goudlokje.mergeableSince false`
-/
#guard_msgs in
Exercise "conclude"
  Given: (p q : Prop)
  Assume: (h : p ∧ q)
  Conclusion: q ∧ p
Proof:
  Since p ∧ q we get that p and q
  Since p and q we conclude that q ∧ p
QED

-- The merged step `Since x ≤ 1 and 0 ≤ x we conclude that 0 ≤ x ∧ x ≤ 2` fails.
#guard_msgs in
Exercise "conclude, not mergeable"
  Given: (x : ℝ)
  Assume: (h : x ≤ 1) (h0 : 0 ≤ x)
  Conclusion: 0 ≤ x ∧ x ≤ 2
Proof:
  Since x ≤ 1 we get that x ≤ 2
  Since 0 ≤ x and x ≤ 2 we conclude that 0 ≤ x ∧ x ≤ 2
QED

-- Two `get that` steps whose merge succeeds, where the rest of the proof does not use what the
-- first step got.
/--
error: steps 1 and 2 of exercise "get that" can be merged into one step: `Since p ∧ q and q → r we get that r`

If this is intended, record it with `goudlokje update`.

Note: This linter can be disabled with `set_option linter.goudlokje.mergeableSince false`
-/
#guard_msgs in
Exercise "get that"
  Given: (p q r : Prop)
  Assume: (h : p ∧ q) (hr : q → r)
  Conclusion: r
Proof:
  Since p ∧ q we get that q
  Since q → r and q we get that r
  We conclude by hypothesis
QED

-- The merged step `Since p → q, p and q → r we get that r` succeeds, but a later step uses `q`,
-- which the first step got.
#guard_msgs in
Exercise "get that, used later"
  Given: (p q r : Prop)
  Assume: (hpq : p → q) (hp : p) (hr : q → r)
  Conclusion: q ∧ r
Proof:
  Since p → q and p we get that q
  Since q → r and q we get that r
  Let's first prove that q
  · We conclude by hypothesis
  Let's now prove that r
  · We conclude by hypothesis
QED

-- When the first step adds no facts, the merged step is the second step: the first is not needed.
/--
error: step 1 of exercise "not needed" can be left out: step 2 does not need it

If this is intended, record it with `goudlokje update`.

Note: This linter can be disabled with `set_option linter.goudlokje.mergeableSince false`
-/
#guard_msgs in
Exercise "not needed"
  Given: (p q : Prop)
  Assume: (h : p ∧ q)
  Conclusion: q
Proof:
  Since p ∧ q we get that p
  Since p ∧ q we conclude that q
QED

-- Steps with `hence` are not merged.
#guard_msgs in
Exercise "hence"
  Given: (p q r : Prop)
  Assume: (h : p ∧ q) (hr : q → r)
  Conclusion: r
Proof:
  Since p ∧ q we get that p and q hence q ∧ p
  Since q → r and q we conclude that r
QED

-- A finding recorded in `Merge.test.json` is not reported.
#guard_msgs in
Exercise "recorded"
  Given: (p q : Prop)
  Assume: (h : p ∧ q)
  Conclusion: q ∧ p
Proof:
  Since p ∧ q we get that p and q
  Since p and q we conclude that q ∧ p
QED

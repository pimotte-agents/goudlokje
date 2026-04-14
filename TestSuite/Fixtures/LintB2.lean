-- Fixture for CheckB2 (type annotation detection) tests.
-- Contains type annotations in proof bodies that CheckB2 should flag.
import Verbose.English.All

set_option linter.unusedTactic false

-- Fix with explicit type annotation: CheckB2 should flag the `Fix n : ℕ` line.
example : ∀ n : ℕ, n + 0 = n := by
  Fix n : ℕ
  ring

-- Type-cast annotation `(expr : T)` in a proof body:
-- CheckB2 should flag `(trivial : True)`.
example : True ∧ True := by
  exact And.intro (trivial : True) trivial

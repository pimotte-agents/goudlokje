-- Fixture for testing that filterVerboseSteps resets per declaration.
-- Declaration 1 uses Verbose step boundaries; Declaration 2 does not.
import Verbose.English.All

set_option linter.unusedTactic false

-- Decl 1: two Verbose steps, each with a noop `show` before `norm_num`.
-- filterVerboseSteps keeps only `show` per step → 2 decide shortcuts.
example : 1 + 1 = 2 ∧ 2 + 2 = 4 := by
  Let's first prove that 1 + 1 = 2
  show 1 + 1 = 2
  norm_num
  Let's now prove that 2 + 2 = 4
  show 2 + 2 = 4
  norm_num

-- Decl 2: no step boundaries; filterVerboseSteps must not suppress this.
-- decide is a shortcut at the `norm_num` position → 1 decide shortcut.
example : 1 + 1 = 2 := by
  norm_num

-- Fixture: VerboseMultiDecl — one Verbose-style declaration and one plain declaration.
-- Expected `decide` shortcuts: line 11 (Decl 1, with filter) and line 21 (Decl 2, always).
import Verbose.English.All

set_option linter.unusedTactic false

-- Decl 1 (Verbose, 2 steps): filterVerboseSteps keeps first non-boundary tactic per step
-- (`show` at lines 11 and 14); skip-last drops line 14 → 1 shortcut: `decide` at line 11.
example : 1 + 1 = 2 ∧ 2 + 2 = 4 := by
  Let's first prove that 1 + 1 = 2
  show 1 + 1 = 2
  norm_num
  Let's now prove that 2 + 2 = 4
  show 2 + 2 = 4
  norm_num

-- Decl 2 (plain, no step boundaries): filterVerboseSteps must not suppress tactics here.
-- 2 tactic positions: line 21 `constructor` (decide closes `1+1=2 ∧ 2+2=4`, 1 shortcut) and
-- line 22 `all_goals norm_num` (last tactic per declaration → dropped by skip-last, 0 shortcuts).
example : 1 + 1 = 2 ∧ 2 + 2 = 4 := by
  constructor
  all_goals norm_num

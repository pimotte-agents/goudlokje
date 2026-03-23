-- Fixture: VerboseMultiDecl — one Verbose-style declaration followed by one plain declaration.
-- Total `decide` shortcuts (filterVerboseSteps := true): 2 — at line 11 (Decl 1) and line 21 (Decl 2).
import Verbose.English.All

set_option linter.unusedTactic false

-- Decl 1 (Verbose, 2 steps): filterVerboseSteps keeps FIRST non-boundary tactic per step
-- (`show` at line 11 and line 14); skip-last drops line 14 → 1 shortcut: `decide` at line 11.
example : 1 + 1 = 2 ∧ 2 + 2 = 4 := by
  Let's first prove that 1 + 1 = 2  -- step boundary (line 10); introduces goal `1 + 1 = 2`
  show 1 + 1 = 2                    -- line 11: SHORTCUT — first non-boundary tactic of step 1; `decide` closes it
  norm_num                           -- line 12: 2nd tactic in step 1; filtered out by filterVerboseSteps
  Let's now prove that 2 + 2 = 4    -- step boundary (line 13); introduces goal `2 + 2 = 4`
  show 2 + 2 = 4                    -- line 14: first non-boundary tactic of step 2; kept by filter but last overall → dropped by skip-last
  norm_num                           -- line 15: 2nd tactic in step 2; filtered out by filterVerboseSteps

-- Decl 2 (plain, no step boundaries): filterVerboseSteps must NOT suppress tactics here.
-- 2 tactic positions: line 21 `constructor` (`decide` closes `1+1=2 ∧ 2+2=4` → 1 shortcut)
-- and line 22 `all_goals norm_num` (last tactic of the declaration → dropped by skip-last, 0 shortcuts).
example : 1 + 1 = 2 ∧ 2 + 2 = 4 := by
  constructor        -- line 21: SHORTCUT — `decide` closes the full conjunction goal
  all_goals norm_num -- line 22: last tactic of Decl 2 → dropped by skip-last

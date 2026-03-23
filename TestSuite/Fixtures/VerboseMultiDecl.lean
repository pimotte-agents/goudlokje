-- Fixture: VerboseMultiDecl — one Verbose-style declaration followed by one plain declaration.
-- Purpose: verify that filterVerboseSteps per-step deduplication does not leak across
-- declarations; Decl 2 (no step boundaries) must keep ALL its shortcuts.
--
-- Shortcut summary with `decide` probe:
--
--   filterVerboseSteps := false (probe all, no step grouping):
--     Decl 1: show@29, norm_num@30, show@32 probed (norm_num@33 is last → skip-last)  → 3 shortcuts
--     Decl 2: constructor@40 probed (all_goals@41 is last → skip-last)                → 1 shortcut
--     Total: 4 shortcuts
--
--   filterVerboseSteps := true (probe all per step, report first shortcut per step):
--     Decl 1, step 1 [show@29, norm_num@30]: show@29 → shortcut (decide closes 1+1=2) → 1 shortcut
--     Decl 1, step 2 [show@32]:              show@32 → shortcut (decide closes 2+2=4) → 1 shortcut
--       (norm_num@33 dropped by skip-last before grouping)
--     Decl 2, no boundaries, singleton groups: constructor@40 → shortcut              → 1 shortcut
--       (all_goals@41 dropped by skip-last)
--     Total: 3 shortcuts (at lines 29, 32, 40)
import Verbose.English.All

set_option linter.unusedTactic false

-- Decl 1 (Verbose, 2 steps):
-- Skip-last drops norm_num@33 (last tactic of Decl 1).
-- Step 1 group [show@29, norm_num@30]: probe show@29 → shortcut → stop step.
-- Step 2 group [show@32]:              probe show@32 → shortcut.
example : 1 + 1 = 2 ∧ 2 + 2 = 4 := by
  Let's first prove that 1 + 1 = 2  -- step boundary (line 28); introduces goal `1 + 1 = 2`
  show 1 + 1 = 2                    -- line 29: SHORTCUT — first tactic of step 1; `decide` closes it
  norm_num                           -- line 30: 2nd tactic in step 1; step already done → not probed
  Let's now prove that 2 + 2 = 4    -- step boundary (line 31); introduces goal `2 + 2 = 4`
  show 2 + 2 = 4                    -- line 32: SHORTCUT — only remaining tactic of step 2; `decide` closes it
  norm_num                           -- line 33: last tactic of Decl 1 → dropped by skip-last before grouping

-- Decl 2 (plain, no step boundaries): filterVerboseSteps must NOT suppress tactics here.
-- Each tactic becomes a singleton group → all shortcuts reported.
-- Skip-last drops all_goals@41 (last tactic of Decl 2).
-- Singleton group [constructor@40]: probe → shortcut (decide closes the full conjunction).
example : 1 + 1 = 2 ∧ 2 + 2 = 4 := by
  constructor        -- line 40: SHORTCUT — `decide` closes the full conjunction goal
  all_goals norm_num -- line 41: last tactic of Decl 2 → dropped by skip-last

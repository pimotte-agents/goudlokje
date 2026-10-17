import Lean.Elab.Tactic.BuiltinTactic

/-!
# Alternative solutions

`Alternative solution:` records another way to prove the current goal, next to the reference
solution:

```lean
Exercise "1.1.1"
  …
Proof:
  Alternative solution:
    Assume that p
    We conclude by hypothesis
  Assume that p
  …
QED
```

The indented block must close all current goals; otherwise it is an error. Afterwards the proof
state is restored, so the reference solution continues as if the block were not there. Errors in
the block are reported without stopping the rest of the proof.

Goudlokje checks the steps of an alternative solution like the other steps: the lint checks, the
shortcut probes and the step numbering include them. Placed in a student input area, the
alternative is removed together with the reference solution when the student version is made.
-/

namespace Goudlokje

open Lean Elab Tactic

/-- `Alternative solution:` followed by an indented proof of the current goals, which is checked
    and then discarded; see the module documentation. -/
syntax (name := alternativeSolution) "Alternative" " solution:" ppIndent(colGt tacticSeq) : tactic

/-- A fresh goal with the same context, type and name as `goal`. -/
private def copyGoal (goal : MVarId) : MetaM MVarId := do
  let decl ← goal.getDecl
  let copy ← Meta.mkFreshExprMVarAt decl.lctx decl.localInstances decl.type .syntheticOpaque
    decl.userName
  return copy.mvarId!

/- The block runs on copies of the goals, so that its steps work on goals of their own (Goudlokje
   groups steps working on the same goal into chains, see `goalChains`); afterwards all
   metavariable assignments it made are undone. -/
@[tactic alternativeSolution]
def evalAlternativeSolution : Tactic := fun stx => do
  let goals ← getGoals
  let mctx ← getMCtx
  try
    setGoals (← goals.mapM (liftM <| copyGoal ·))
    evalTactic stx[2]
    let unsolved ← getUnsolvedGoals
    unless unsolved.isEmpty do
      logErrorAt stx[0] m!"the alternative solution does not prove the goal; unsolved goals:\n\
        {goalsToMessageData unsolved}"
  catch e =>
    logException e
  setMCtx mctx
  setGoals goals

end Goudlokje

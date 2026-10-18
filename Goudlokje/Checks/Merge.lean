import Goudlokje.Exercise
import Goudlokje.Finding
import Goudlokje.Probe

/-!
# Mergeable `Since` steps

Finds pairs of consecutive `Since` steps that Lean Verbose can do in one step (check
`mergeableSince`), so reference solutions are not finer-grained than needed and students cannot
skip steps unnoticed.

A pair is a step A `Since F₁ we get that N₁` in a student input area, followed by the step B that
works on A's successor goal, either `Since F₂ we get that N₂` or `Since F₂ we conclude that C`. The
merged step is B's source text with its facts replaced by F₁ followed by the facts of F₂ that are
not among N₁ (matched by source text), without duplicates; pairs with more than 4 merged facts
are skipped, as Verbose's `facts` syntax allows at most 4. The merged step runs on A's goal, with
the probe heartbeat budget:

* If B is `we conclude that`, the pair can be merged when the merged step closes the goal.
* If B is `we get that`, the merged step must succeed, and the proof of B's successor goal (the
  rest of the proof) must not use the hypotheses A introduced, which the merged step drops.

Only the English `Since` syntax (`Verbose.English`) is recognised.
-/

namespace Goudlokje.Checks

open Lean Elab Command Meta

private def sinceGetThatKind : SyntaxNodeKind := `Verbose.English.tacticSince_WeGetThat_Hence_
private def sinceConcludeKind : SyntaxNodeKind := `Verbose.English.tacticSince_WeConcludeThat_

/-- The source text of `stx`, without surrounding whitespace. -/
private def sourceText? (stx : Syntax) : Option String :=
  (stx.getSubstring? (withLeading := false) (withTrailing := false)).map (·.toString)

/-- The terms of a Verbose `facts` node (`a`, `a and b`, `a, b and c`, `a, b, c and d`): its
    arguments at even positions, between the `,` and `and` separators. -/
private def factTerms (facts : Syntax) : Array Syntax :=
  (facts.getArgs.zipIdx.filter (·.2 % 2 == 0)).map (·.1)

/-- The source texts of the terms of `facts`, or `none` if some term has no source text. -/
private def factTexts? (facts : Syntax) : Option (Array String) :=
  (factTerms facts).mapM sourceText?

/-- Joins facts as Verbose's `facts` syntax writes them: `a`, `a and b`, `a, b and c`, … -/
def joinFacts (facts : Array String) : String :=
  match facts.back? with
  | none => ""
  | some last =>
    if facts.size == 1 then last else s!"{", ".intercalate facts.pop.toList} and {last}"

/-- The facts of the merged step: `f₁`, then the facts of `f₂` that are not among `n₁`, without
    duplicates; `none` if there are more than 4 (more than Verbose's `facts` syntax allows). -/
def mergeFacts (f₁ n₁ f₂ : Array String) : Option (Array String) :=
  let merged := (f₁ ++ f₂.filter (!n₁.contains ·)).foldl (init := #[]) fun acc fact =>
    if acc.contains fact then acc else acc.push fact
  if merged.size ≤ 4 then some merged else none

/-- For a step `Since F we get that N` (a single `N`, without `hence` or `finally we conclude
    that`): the facts `F` and the new facts `N`. -/
private def getThatParts? (stx : Syntax) : Option (Syntax × Syntax) := do
  guard <| stx.isOfKind sinceGetThatKind
  let news := stx[3].getSepArgs
  guard <| news.size == 1 && stx[4].isNone
  return (stx[1], news[0]!)

/-- The source text of step `b` with its facts (the `facts` node `facts`) replaced by
    `merged`. -/
private def replaceFacts? (b facts : Syntax) (merged : String) : Option String := do
  let s ← b.getSubstring? (withLeading := false) (withTrailing := false)
  let f ← facts.getSubstring? (withLeading := false) (withTrailing := false)
  return { s with stopPos := f.startPos }.toString ++ merged ++
    { s with startPos := f.stopPos }.toString

/-- Whether the rest of the proof after step `b` uses a hypothesis that step `a` introduced: the
    hypotheses in `a`'s successor goal that are not in its main goal, and the proof of `b`'s
    successor goal after all steps. Unknown (e.g. an unassigned proof) counts as used. -/
private def usesIntroduced (a b : Step) : IO Bool := do
  let (some goalA, some nextA, some nextB) := (a.mainGoal?, a.successorGoal?, b.successorGoal?)
    | return true
  let mctxA := a.info.mctxAfter
  let (some before, some after) := (mctxA.findDecl? goalA, mctxA.findDecl? nextA) | return true
  let introduced := after.lctx.foldl (init := #[]) fun acc hyp =>
    if before.lctx.contains hyp.fvarId then acc else acc.push hyp.fvarId
  -- `b.ctx` holds the metavariable assignments made by all steps of the command.
  b.ctx.runMetaM after.lctx do
    unless ← nextB.isAssigned do return true
    let proof ← instantiateMVars (.mvar nextB)
    return proof.hasMVar || introduced.any proof.containsFVar

/-- The merged step for the pair `a`, `b`, if `b` is a `Since` step of the right form and the
    merge leaves at least one fact. Returns its text and whether it concludes. -/
private def mergedStep? (a b : Step) : Option (String × Bool) := do
  let (f₁, n₁) ← getThatParts? a.stx
  let (concludes, f₂) ← if b.stx.isOfKind sinceConcludeKind then pure (true, b.stx[1])
    else (getThatParts? b.stx).map fun (f₂, _) => (false, f₂)
  let merged ← mergeFacts (← factTexts? f₁) (← factTexts? n₁) (← factTexts? f₂)
  return (← replaceFacts? b.stx f₂ (joinFacts merged), concludes)

/-- Check `mergeableSince`: pairs of consecutive `Since` steps in `e` that can be merged, reported
    at the first step. -/
def mergeableSinces (e : Exercise) : CommandElabM (Array Issue) := do
  let env ← getEnv
  let heartbeats := probeHeartbeats (← getOptions)
  let mut issues : Array Issue := #[]
  for a in e.inputSteps do
    let some next := a.successorGoal? | continue
    let some b := e.steps.find? fun b => b.pos > a.pos && b.mainGoal? == some next | continue
    let some (text, concludes) := mergedStep? a b | continue
    let .ok code := Parser.runParserCategory env `tactic text | continue
    let some goal := a.mainGoal? | continue
    let outcome ← runTacticOnGoal a goal code heartbeats
    let mergeable ← if concludes then pure (outcome == .closed)
      else if outcome == .progress then (!·) <$> usesIntroduced a b
      else pure false
    unless mergeable do continue
    -- When F₁ adds nothing to F₂, the merged step is B itself: A is not needed at all.
    let message := if some text == sourceText? b.stx then
        m!"step {e.stepNumber a} of exercise {repr e.name} can be left out: step \
          {e.stepNumber b} does not need it"
      else
        m!"steps {e.stepNumber a} and {e.stepNumber b} of exercise {repr e.name} can be merged \
          into one step: `{text}`"
    issues := issues.push { check := .mergeableSince, step := a, ref := a.stx, message }
  return issues

end Goudlokje.Checks

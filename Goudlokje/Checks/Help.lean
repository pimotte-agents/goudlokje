import Goudlokje.Exercise
import Goudlokje.Finding
import Goudlokje.Probe

/-!
# Help

Checks that the help tactic (`goudlokje.help`, e.g. Verbose's `help`) gives a hint at every step in
a student input area: wherever a student may be stuck, asking for help should tell them something.

The help tactic runs on the goal before each step, like a probe (see `runOnGoal`). It gives a hint
if it logs an information message that is not one of the messages meaning "no hint"
(`goudlokje.noHelpMessages`). A help tactic that fails or runs out of heartbeats gives no hint.
-/

namespace Goudlokje.Checks

open Lean Elab Command

/-- Whether the information messages `texts` contain a hint, i.e. a message that contains none of
    the no-hint messages `noHelp`. -/
def containsHint (noHelp : Array String) (texts : List String) : Bool :=
  texts.any fun text => !noHelp.any fun msg => (text.splitOn msg).length > 1

/-- Whether the help tactic `help` gives a hint on `goal`, one of the goals before `step`, with a
    budget of `heartbeats` (in thousands). -/
def givesHint (step : Step) (goal : MVarId) (help : Probe) (noHelp : Array String)
    (heartbeats : Nat) : CommandElabM Bool := do
  let termCtx ← liftTermElabM read
  let termState ← liftTermElabM get
  runOnGoal step goal fun goal =>
    Core.withCurrHeartbeats <|
    withTheReader Core.Context ({ · with maxHeartbeats := heartbeats * 1000 }) do
      tryCatchRuntimeEx
        (do
          modifyThe Core.State ({ · with messages := {} })
          discard <| runTacticCode goal help.code termCtx termState
          let infos := (← getThe Core.State).messages.toList.filter (·.severity == .information)
          return containsHint noHelp (← infos.mapM (·.data.toString)))
        (fun _ => return false)

/-- The steps in `e` at which the help tactic gives no hint, or `none` if no help tactic is
    configured. -/
def helpless (e : Exercise) : CommandElabM (Option (Array Issue)) := do
  let opts ← getOptions
  let source := goudlokje.help.get opts
  if source.trimAscii.isEmpty then return none
  let help ← match parseProbes (← getEnv) source with
    | .ok #[help] => pure help
    | .ok _ => logErrorAt e.stx m!"`goudlokje.help` must be a single tactic"; return none
    | .error msg => logErrorAt e.stx msg; return none
  let noHelp := splitListOption (goudlokje.noHelpMessages.get opts)
  let heartbeats := probeHeartbeats opts
  let mut issues : Array Issue := #[]
  -- Identical goals (e.g. in an alternative solution) get the same answer.
  let mut cache : Std.HashMap GoalFingerprint Bool := {}
  for step in e.inputSteps do
    let some goal := step.mainGoal? | continue
    let key? ← goalFingerprint? step goal
    let hint ← match key?.bind (cache[·]?) with
      | some hint => pure hint
      | none => givesHint step goal help noHelp heartbeats
    if let some key := key? then cache := cache.insert key hint
    unless hint do
      issues := issues.push {
        check := .help, step, ref := step.stx
        message := m!"`{help.name}` gives no hint at step {e.stepNumber step} of exercise \
          {repr e.name}" }
  return issues

end Goudlokje.Checks

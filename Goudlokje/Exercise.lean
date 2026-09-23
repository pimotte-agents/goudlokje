import Goudlokje.Steps
import Goudlokje.Scope
import Goudlokje.Expectations

/-!
# Exercises

The unit Goudlokje checks: one command (a Verbose `Exercise`, an `example`, a theorem, …) together
with everything the checks need about it, computed once per command.
-/

namespace Goudlokje

open Lean Elab Command

/-- A command that Goudlokje checks. -/
structure Exercise where
  /-- The command. -/
  stx          : Syntax
  /-- The name identifying the exercise in `.test.json` (see `exerciseName`). -/
  name         : String
  /-- The proof steps, in source order. -/
  steps        : Array Step
  /-- The first step; step numbers are relative to it. -/
  first        : Step
  fileMap      : FileMap
  /-- The student input areas of the file. -/
  inputAreas   : Array LineRange
  /-- What `.test.json` expects in this exercise. -/
  expectations : ExerciseExpectations

namespace Exercise

/-- The number of step `s` in the exercise, as used in `.test.json`. -/
def stepNumber (e : Exercise) (s : Step) : Nat :=
  Goudlokje.stepNumber e.fileMap e.first s

/-- Whether step `s` lies in a student input area. -/
def inInputArea (e : Exercise) (s : Step) : Bool :=
  e.inputAreas.any (·.contains (s.line e.fileMap))

/-- The steps in student input areas: the steps that are checked. -/
def inputSteps (e : Exercise) : Array Step :=
  e.steps.filter e.inInputArea

end Exercise

/-- The exercise declared by the command `stx`, if Goudlokje checks it: the command elaborated
    without errors, it is written with Lean Verbose (a Verbose command, or a proof using Verbose
    tactics), and some of its steps lie in a student input area. An unreadable `.test.json` is
    reported as an error. -/
def getExercise? (stx : Syntax) : CommandElabM (Option Exercise) := do
  if (← get).messages.hasErrors then return none
  let steps := collectSteps stx (← getInfoTrees)
  let some first := steps[0]? | return none
  let env ← getEnv
  unless isVerboseKind env stx.getKind || steps.any (·.isVerbose env) do return none
  let fileMap ← getFileMap
  let inputAreas ← getInputAreas
  unless steps.any (fun s => inputAreas.any (·.contains (s.line fileMap))) do return none
  let name := exerciseName env stx
  let expectations ← match ← getExpectations with
    | .ok expectations => pure (expectations.get name)
    | .error msg => logErrorAt stx msg; return none
  return some { stx, name, steps, first, fileMap, inputAreas, expectations }

end Goudlokje

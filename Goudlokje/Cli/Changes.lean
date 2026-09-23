import Goudlokje.Expectations
import Goudlokje.Report
import Goudlokje.Finding

/-!
# Changes to `.test.json`

Given a worksheet's current `.test.json` and the results of checking it (the records the linter
writes to the results file), `proposeChanges` computes the changes `goudlokje update` proposes:
record new findings as expected, and remove expectations that are stale.
-/

namespace Goudlokje.Cli

open Lean

/-- The results of checking one module, read from its results file. -/
structure ModuleResults where
  /-- The exercises that were checked, with the names of the checks that ran on them. -/
  exercises : Std.HashMap String (Array String) := {}
  /-- Exercises that could not be checked because of elaboration errors. -/
  skipped   : Std.HashSet String := {}
  findings  : Array Finding := #[]

/-- Adds the record `r` to the results. -/
def ModuleResults.add (acc : ModuleResults) : ResultRecord → ModuleResults
  | .exercise name checks => { acc with exercises := acc.exercises.insert name checks }
  | .skipped name => { acc with skipped := acc.skipped.insert name }
  | .finding f => { acc with findings := acc.findings.push f }

/-- Parses the lines of a results file into (source file, record) pairs. -/
def parseResultLines (contents : String) : Except String (Array (String × ResultRecord)) :=
  (contents.splitOn "\n").toArray.filterMapM fun line => do
    if line.trimAscii.isEmpty then return none
    let json ← Json.parse line
    return some (← json.getObjValAs? String "file", ← fromJson? json)

/-- A change to a `.test.json` file. -/
inductive Change where
  | recordShortcut (exercise : String) (entry : ExpectedShortcut)
  | recordLint (exercise : String) (entry : ExpectedLint)
  | allowSorry (exercise : String)
  | removeShortcut (exercise : String) (entry : ExpectedShortcut)
  | removeLint (exercise : String) (entry : ExpectedLint)
  | disallowSorry (exercise : String)
  /-- Remove all expectations of an exercise that no longer exists. -/
  | removeExercise (exercise : String)
  deriving Repr, BEq

namespace Change

/-- The exercise the change is about. -/
def exercise : Change → String
  | recordShortcut e _ | recordLint e _ | allowSorry e | removeShortcut e _ | removeLint e _
  | disallowSorry e | removeExercise e => e

/-- A description of the change, as a question. -/
def describe : Change → String
  | recordShortcut e s => s!"Record shortcut `{s.tactic}` at step {s.step} of {e.quote} as expected"
  | recordLint e l => s!"Record `{l.check}` at step {l.step} of {e.quote} as expected"
  | allowSorry e => s!"Allow `sorry` in {e.quote}"
  | removeShortcut e s =>
    s!"Remove the stale expected shortcut `{s.tactic}` at step {s.step} of {e.quote}"
  | removeLint e l => s!"Remove the stale expected `{l.check}` at step {l.step} of {e.quote}"
  | disallowSorry e => s!"Remove the stale `sorry` allowance of {e.quote}"
  | removeExercise e => s!"Remove the expectations of {e.quote}, which no longer exists"

/-- Whether the change is made without asking: removing entries that are invalid anyway. -/
def automatic : Change → Bool
  | removeLint _ l => l.check != "typeAscription"
  | _ => false

/-- Applies the change to `e`. -/
def apply (c : Change) (e : Expectations) : Expectations :=
  let modify (f : ExerciseExpectations → ExerciseExpectations) : Expectations :=
    let updated := f (e.get c.exercise)
    { exercises :=
        if updated == {} then e.exercises.erase c.exercise
        else e.exercises.insert c.exercise updated }
  match c with
  | recordShortcut _ s => modify fun x => { x with shortcuts := x.shortcuts.push s }
  | recordLint _ l => modify fun x => { x with lint := x.lint.push l }
  | allowSorry _ => modify ({ · with allowSorry := true })
  | removeShortcut _ s => modify fun x => { x with shortcuts := x.shortcuts.erase s }
  | removeLint _ l => modify fun x => { x with lint := x.lint.erase l }
  | disallowSorry _ => modify ({ · with allowSorry := false })
  | removeExercise name => { exercises := e.exercises.erase name }

end Change

/-- The changes to `old` that the results `r` call for:

* unexpected findings are recorded as expected, except raw tactics, which cannot be;
* expectations of checked exercises that no findings match are stale and removed, but only for
  checks that ran (without probes, expected shortcuts cannot be confirmed);
* `rawTactic` and unknown lint entries are removed automatically;
* expectations of exercises that were neither checked nor skipped are removed. -/
def proposeChanges (old : Expectations) (r : ModuleResults) : Array Change := Id.run do
  let mut changes : Array Change := #[]
  for (name, checks) in r.exercises.toArray.qsort (·.1 < ·.1) do
    let expected := old.get name
    let findings := r.findings.filter (·.exercise == name)
    let ran (check : Check) := checks.contains check.name
    -- New findings.
    for f in findings do
      if f.expected then continue
      let change? : Option Change :=
        if f.check == Check.shortcut.name then
          f.tactic?.map fun tactic => .recordShortcut name { step := f.step, tactic }
        else if f.check == Check.typeAscription.name then
          some (.recordLint name { check := f.check, step := f.step })
        else if f.check == Check.sorry.name then some (.allowSorry name)
        else none
      if let some change := change? then
        unless changes.contains change do changes := changes.push change
    -- Stale expectations.
    if ran .shortcut then
      for s in expected.shortcuts do
        unless findings.any fun f => f.check == Check.shortcut.name && f.step == s.step &&
            f.tactic? == some s.tactic do
          changes := changes.push (.removeShortcut name s)
    for l in expected.lint do
      if l.check == Check.typeAscription.name then
        if ran .typeAscription && !findings.any (fun f => f.check == l.check && f.step == l.step) then
          changes := changes.push (.removeLint name l)
      else
        changes := changes.push (.removeLint name l)
    if ran .sorry && expected.allowSorry && !findings.any (·.check == Check.sorry.name) then
      changes := changes.push (.disallowSorry name)
  -- Exercises that no longer exist.
  for (name, _) in old.exercises do
    unless r.exercises.contains name || r.skipped.contains name do
      changes := changes.push (.removeExercise name)
  return changes

end Goudlokje.Cli

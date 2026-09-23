import Lean.Linter.Basic
import Goudlokje.Checks.Shortcut
import Goudlokje.Checks.Lint
import Goudlokje.Report

/-!
# The Goudlokje linter

Runs all enabled checks (`Check`) on every exercise and reports what they find. For each command
the exercise context (`getExercise?`) is computed once and shared by the checks.

Issues that the worksheet's `.test.json` lists as expected are not reported; issues it does not
list are reported with the check's severity (`Check.severity`); expectations that no longer match
an issue are reported as stale. When `goudlokje.resultsFile` is set, every issue, expected or not,
is also written to the results file for `goudlokje update`.
-/

namespace Goudlokje

open Lean Elab Command

/-- Runs `check` on `e`; `none` if the check could not run (e.g. no probes are configured). -/
private def runCheck (e : Exercise) : Check → CommandElabM (Option (Array Issue))
  | .shortcut => Checks.shortcuts e
  | .rawTactic => some <$> Checks.rawTactics e
  | .typeAscription => some <$> Checks.typeAscriptions e
  | .sorry => some <$> Checks.sorries e

/-- Drops issues reported at the same place for the same reason (a nested step is also part of
    the step around it). -/
private def dedup (issues : Array Issue) : Array Issue :=
  let key (i : Issue) := (i.check, i.ref.getPos?.map (·.byteIdx), i.tactic?)
  issues.foldl (init := #[]) fun acc i =>
    if acc.any (key · == key i) then acc else acc.push i

/-- Whether `.test.json` expects `issue` in `e`. -/
private def isExpected (e : Exercise) (issue : Issue) : Bool :=
  let step := e.stepNumber issue.step
  match issue.check with
  | .shortcut => e.expectations.shortcuts.contains { step, tactic := issue.tactic?.getD "" }
  | .rawTactic => false
  | .typeAscription => e.expectations.lint.contains { check := Check.typeAscription.name, step }
  | .sorry => e.expectations.allowSorry

/-- How to record an issue as expected, appended to the message of an unexpected issue. -/
private def hint : Check → MessageData
  | .shortcut | .typeAscription => m!"If this is intended, record it with `goudlokje update`."
  | .sorry => m!"If this exercise may contain `sorry`, allow it with `goudlokje update`."
  | .rawTactic =>
    m!"Tactics can be allowed for a whole project with the option `goudlokje.allowedTactics`."

/-- Reports the expectations of `e` for `check` that no longer match any of its `issues`. -/
private def reportStale (e : Exercise) (check : Check) (issues : Array Issue) :
    CommandElabM Unit := do
  let stale (msg : MessageData) (severity := MessageSeverity.warning) :=
    logFinding check.linterOption e.stx severity msg
  let exercise := repr e.name
  match check with
  | .shortcut =>
    for entry in e.expectations.shortcuts do
      unless issues.any fun i => e.stepNumber i.step == entry.step && i.tactic? == entry.tactic do
        stale m!"expected shortcut `{entry.tactic}` at step {entry.step} of exercise {exercise} \
          no longer occurs; remove it with `goudlokje update`"
  | .rawTactic =>
    for entry in e.expectations.lint do
      if entry.check == check.name then
        stale (severity := .error) m!"`{check.name}` at step {entry.step} of exercise {exercise} \
          cannot be recorded as expected; remove it from `.test.json`"
  | .typeAscription =>
    for entry in e.expectations.lint do
      if entry.check == check.name && !issues.any (e.stepNumber ·.step == entry.step) then
        stale m!"expected `{check.name}` at step {entry.step} of exercise {exercise} no longer \
          occurs; remove it with `goudlokje update`"
  | .sorry =>
    if e.expectations.allowSorry && issues.isEmpty then
      stale m!"exercise {exercise} allows `sorry` but contains none; remove `allowSorry` with \
        `goudlokje update`"

/-- Reports the `issues` each check found in `e`; see the module documentation. -/
private def report (e : Exercise) (results : Array (Check × Array Issue)) : CommandElabM Unit := do
  let resultsFile := goudlokje.resultsFile.get (← getOptions)
  let record (r : ResultRecord) : CommandElabM Unit := do
    unless resultsFile.isEmpty do emitRecord resultsFile r
  record (.exercise e.name)
  for (check, issues) in results do
    for issue in issues do
      let expected := isExpected e issue
      unless expected do
        logFinding check.linterOption issue.ref check.severity m!"{issue.message}\n\n{hint check}"
      let pos := e.fileMap.toPosition (issue.ref.getPos?.getD 0)
      record <| .finding {
        check := check.name, exercise := e.name, step := e.stepNumber issue.step
        line := pos.line, column := pos.column, tactic? := issue.tactic?
        message := ← issue.message.toString, expected }
    reportStale e check issues

/-- The Goudlokje linter; see the module documentation. -/
def goudlokjeLinter : Linter where
  run := withSetOptionIn fun stx => do
    let linterOptions ← Linter.getLinterOptions
    let enabled := Check.all.filter (Linter.getLinterValue ·.linterOption linterOptions)
    if enabled.isEmpty then return
    let some e ← getExercise? stx | return
    let mut results := #[]
    for check in enabled do
      if let some issues ← runCheck e check then
        results := results.push (check, dedup issues)
    report e results

initialize addLinter goudlokjeLinter

end Goudlokje

import Lean.Linter.Basic
import Goudlokje.Options
import Goudlokje.Scope
import Goudlokje.Expectations
import Goudlokje.Probe
import Goudlokje.Report

/-!
# Shortcut linter

Reports *shortcuts*: steps of an exercise where a probe tactic (`goudlokje.probes`) closes the goal
before the proof is over, which suggests the exercise is too easy.

Only steps that do not close their goal themselves are probed (the student has to write a step
there anyway). The probed steps form goal chains (see `goalChains`); per chain only the first step
at which some probe succeeds is reported, together with every probe that succeeds there.

Shortcuts listed in the worksheet's `.test.json` are expected and not reported; listed shortcuts
that no longer occur are reported as stale. Like the other checks, this only covers exercises
written with Lean Verbose (a Verbose `Exercise`/`Example` or a proof using Verbose tactics), in
student input areas.
-/

namespace Goudlokje

open Lean Elab Command

/-- A shortcut: `probe` closes the goal at `step`. -/
private structure Shortcut where
  step  : Step
  probe : Probe

/-- The shortcuts in `steps`: per goal chain, the probes that succeed at the first step in an input
    area where any probe succeeds. -/
private def findShortcuts (steps : Array Step) (probes : Array Probe) (heartbeats : Nat) :
    CommandElabM (Array Shortcut) := do
  let fileMap ← getFileMap
  let mut shortcuts := #[]
  let mut cache : ProbeCache := {}
  for chain in goalChains steps do
    for step in chain do
      unless ← inInputArea (step.line fileMap) do continue
      let mut closing := #[]
      for probe in probes do
        let (outcome, cache') ← (runProbeCached step probe heartbeats).run cache
        cache := cache'
        if outcome == .closed then closing := closing.push probe
      unless closing.isEmpty do
        shortcuts := shortcuts ++ closing.map ({ step, probe := · })
        break
  return shortcuts

/-- Reports shortcuts; see the module documentation. -/
def shortcutLinter : Linter where
  run := withSetOptionIn fun stx => do
    unless Linter.getLinterValue linter.goudlokje.shortcut (← Linter.getLinterOptions) do return
    if (← get).messages.hasErrors then return
    let opts ← getOptions
    let env ← getEnv
    let probes ← match parseProbes env (goudlokje.probes.get opts) with
      | .ok probes => pure probes
      | .error e => logError e; return
    if probes.isEmpty then return
    let steps := collectSteps stx (← getInfoTrees)
    let some first := steps[0]? | return
    unless isVerboseKind env stx.getKind || steps.any (·.isVerbose env) do return
    let fileMap ← getFileMap
    unless ← steps.anyM (inInputArea <| ·.line fileMap) do return
    let exercise := exerciseName env stx
    let expected ← match ← getExpectations with
      | .ok expectations => pure (expectations.get exercise).shortcuts
      | .error e => logErrorAt stx e; return
    let shortcuts ← findShortcuts steps probes (goudlokje.probeHeartbeats.get opts)
    let resultsFile := goudlokje.resultsFile.get opts
    unless resultsFile.isEmpty do emitRecord resultsFile (.exercise exercise)
    let mut found : Array ExpectedShortcut := #[]
    for { step, probe } in shortcuts do
      let entry := { step := stepNumber fileMap first step, tactic := probe.name }
      found := found.push entry
      let isExpected := expected.contains entry
      let msg := m!"`{probe.name}` closes the goal at step {entry.step} of exercise \
        {repr exercise}, so the rest of this part of the proof can be skipped"
      unless isExpected do
        logFinding linter.goudlokje.shortcut step.stx .error
          m!"{msg}\n\nIf this is intended, record it with `goudlokje update`."
      unless resultsFile.isEmpty do
        let pos := fileMap.toPosition (step.stx.getPos?.getD 0)
        emitRecord resultsFile <| .finding {
          check := "shortcut", exercise, step := entry.step, line := pos.line, column := pos.column
          tactic? := probe.name, message := ← msg.toString, expected := isExpected }
    for entry in expected do
      unless found.contains entry do
        logFinding linter.goudlokje.shortcut stx .warning
          m!"expected shortcut `{entry.tactic}` at step {entry.step} of exercise \
            {repr exercise} no longer occurs; remove it with `goudlokje update`"

initialize addLinter shortcutLinter

end Goudlokje

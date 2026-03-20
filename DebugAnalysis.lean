import Lean
import Lean.Elab.Frontend
import Lean.Elab.Tactic
import Lean.Elab.Import
import Lean.Meta
import Goudlokje.Analysis

open Lean Elab Meta Goudlokje

private partial def dumpTree (indent : String) (ci? : Option ContextInfo) (tree : InfoTree) : IO Unit := do
  match tree with
  | .context pci child =>
    let newCi? := pci.mergeIntoOuter? ci?
    IO.println s!"{indent}[context]"
    dumpTree (indent ++ "  ") newCi? child
  | .node info children =>
    match info with
    | .ofTacticInfo ti =>
      IO.println s!"{indent}[TacticInfo] kind={ti.stx.getKind} goalsBefore={ti.goalsBefore.length}"
    | .ofCommandInfo ci =>
      IO.println s!"{indent}[CommandInfo] elab={ci.elaborator}"
    | .ofTermInfo ti =>
      IO.println s!"{indent}[TermInfo] isType={ti.isBinder}"
    | .ofPartialTermInfo _ => IO.println s!"{indent}[PartialTermInfo]"
    | .ofMacroExpansionInfo _ => IO.println s!"{indent}[MacroExpansionInfo]"
    | .ofOptionInfo _ => IO.println s!"{indent}[OptionInfo]"
    | .ofErrorNameInfo _ => IO.println s!"{indent}[ErrorNameInfo]"
    | .ofFieldInfo _ => IO.println s!"{indent}[FieldInfo]"
    | .ofCompletionInfo _ => IO.println s!"{indent}[CompletionInfo]"
    | .ofUserWidgetInfo _ => IO.println s!"{indent}[UserWidgetInfo]"
    | .ofCustomInfo ci => IO.println s!"{indent}[CustomInfo type={ci.value.typeName}]"
    | .ofFVarAliasInfo _ => IO.println s!"{indent}[FVarAliasInfo]"
    | .ofFieldRedeclInfo _ => IO.println s!"{indent}[FieldRedeclInfo]"
    | .ofDelabTermInfo _ => IO.println s!"{indent}[DelabTermInfo]"
    | .ofChoiceInfo _ => IO.println s!"{indent}[ChoiceInfo]"
    | .ofDocInfo _ => IO.println s!"{indent}[DocInfo]"
    | .ofDocElabInfo _ => IO.println s!"{indent}[DocElabInfo]"
    for child in children do
      dumpTree (indent ++ "  ") ci? child
  | .hole id =>
    IO.println s!"{indent}[hole {id.name}] ← should not appear after substituteLazy"

def main (args : List String) : IO Unit := do
  Lean.initSearchPath (← Lean.findSysroot)
  unsafe Lean.enableInitializersExecution
  let filePath : System.FilePath := args.headD "TestSuite/Fixtures/Simple.lean"
  let input ← IO.FS.readFile filePath
  -- Disable async so theorem bodies are elaborated synchronously
  let opts := Elab.async.set Options.empty false
  let inputCtx := Parser.mkInputContext input filePath.toString
  let (header, parserState, _messages) ← Parser.parseHeader inputCtx
  let env ← importModules (Elab.HeaderSyntax.imports header) opts 0
  let env := env.setMainModule Name.anonymous
  IO.println s!"env has OfNat: {env.contains `OfNat}"
  let initCmdState : Command.State :=
    { Command.mkState env {} opts with infoState := { enabled := true } }

  -- Verify async is disabled
  let scope := initCmdState.scopes.head!
  IO.println s!"Elab.async = {Elab.async.get scope.opts}"
  IO.println s!"internal.cmdlineSnapshots = {Lean.internal.cmdlineSnapshots.get scope.opts}"
  IO.println s!"InfoState.enabled = {initCmdState.infoState.enabled}"

  IO.println "=== Using IO.processCommands (enabled=true) ==="
  let state ← IO.processCommands inputCtx parserState initCmdState
  IO.println s!"InfoState.enabled after = {state.commandState.infoState.enabled}"
  IO.println s!"Messages: {state.commandState.messages.toList.length}"
  for msg in state.commandState.messages.toList do
    IO.println s!"  [{msg.severity}] {← msg.data.toString}"
  let trees := state.commandState.infoState.trees.toArray
  IO.println s!"Total trees: {trees.size}"
  for i in [:trees.size] do
    IO.println s!"=== Tree {i} ==="
    dumpTree "" none trees[i]!

  IO.println ""
  IO.println "=== Running analyzeFile (Elab.async=true) ==="
  -- Run analyzeFile's core logic directly to dump trees
  let opts2 := Lean.Elab.async.set Options.empty true
  let (env2, _) ← processHeader header opts2 {} inputCtx
  let initCmdState2 : Lean.Elab.Command.State := Lean.Elab.Command.mkState env2 {} opts2
  let state2 ← IO.processCommands inputCtx parserState initCmdState2
  let trees2 := state2.commandState.infoState.trees.toArray
  IO.println s!"Total trees (async): {trees2.size}"
  for i in [:trees2.size] do
    IO.println s!"=== Tree {i} (async) ==="
    dumpTree "" none trees2[i]!

  IO.println ""
  IO.println "=== Using FrontendM per-command tree collection ==="
  let opts3 := Elab.async.set Options.empty false
  let (env3, _) ← processHeader header opts3 {} inputCtx
  let initCmdState3 : Lean.Elab.Command.State := Lean.Elab.Command.mkState env3 {} opts3
  let initState3 : Lean.Elab.Frontend.State := {
    commandState := initCmdState3
    parserState  := parserState
    cmdPos       := 0
  }
  let ctx3 : Lean.Elab.Frontend.Context := { inputCtx }
  let mut allTrees3 : Array InfoTree := #[]
  let mut fstate := initState3
  let mut cmdIdx := 0
  let mut keepGoing := true
  while keepGoing do
    let (isDone, newState) ← (Lean.Elab.Frontend.processCommand.run ctx3).run fstate
    let cmdTrees := newState.commandState.infoState.trees.toArray
    IO.println s!"Command {cmdIdx}: {cmdTrees.size} trees"
    for i in [:cmdTrees.size] do
      IO.println s!"  Tree {i}:"
      dumpTree "    " none cmdTrees[i]!
    allTrees3 := allTrees3 ++ cmdTrees
    fstate := newState
    cmdIdx := cmdIdx + 1
    if isDone then keepGoing := false
  IO.println s!"Total accumulated trees: {allTrees3.size}"

  let results ← analyzeFile filePath #["decide"]
  IO.println s!"Results: {results.size}"
  for r in results do
    IO.println s!"  {r.file}:{r.line}:{r.column} - {r.tactic}"

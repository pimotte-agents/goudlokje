import Lean
import Lean.Elab.Frontend
import Lean.Elab.Tactic
import Lean.Elab.Import
import Lean.Meta

namespace Goudlokje

open Lean Elab Meta

/-- A position in a source file where a probe tactic succeeded. -/
structure ProbeResult where
  file   : String
  line   : Nat
  column : Nat
  tactic : String
  deriving Repr, BEq, Inhabited

/-- Collect (ContextInfo, TacticInfo) pairs from an InfoTree.
    We use `PartialContextInfo.mergeIntoOuter?` to resolve the full `ContextInfo`. -/
private partial def collectTacticInfos
    (ci? : Option ContextInfo) (tree : InfoTree)
    (acc : Array (ContextInfo × TacticInfo)) : Array (ContextInfo × TacticInfo) :=
  match tree with
  | .context pci child =>
    let newCi? := pci.mergeIntoOuter? ci?
    collectTacticInfos newCi? child acc
  | .node info children =>
    let acc' := match ci?, info with
      | some ci, .ofTacticInfo ti =>
        if !ti.goalsBefore.isEmpty then acc.push (ci, ti) else acc
      | _, _ => acc
    children.foldl (fun a c => collectTacticInfos ci? c a) acc'
  | .hole _ => acc

/-- Try running `tacticStr` in the goal state captured by `ti`, using context `ci`.
    Returns `true` if the tactic closes the first goal. -/
private def tryTacticAt
    (ci : ContextInfo) (mctxBefore : MetavarContext)
    (goal : MVarId) (tacticStr : String) : IO Bool := do
  match Parser.runParserCategory ci.env `tactic tacticStr with
  | .error _ => return false
  | .ok stx =>
    try
      let lctx : LocalContext :=
        (mctxBefore.decls.find? goal).map (·.lctx) |>.getD {}
      ci.runMetaM lctx do
        withMCtx mctxBefore do
          let (goals, _) ← Term.TermElabM.run
            (ctx := { declName? := ci.parentDecl? }) <|
            Tactic.run goal (Tactic.evalTactic stx)
          return goals.isEmpty
    catch _ => return false

/-- Process commands one at a time, accumulating info trees from each command.
    `elabCommandTopLevel` resets `infoState.trees` at the start of each command,
    so we must collect per-command trees before the next command overwrites them. -/
private partial def processCommandsCollectTrees
    (ctx : Frontend.Context)
    (state : Frontend.State)
    (acc : Array InfoTree) : IO (Array InfoTree × Frontend.State) := do
  let (isDone, newState) ← (Frontend.processCommand.run ctx).run state
  let cmdTrees := newState.commandState.infoState.trees.toArray
  let newAcc := acc ++ cmdTrees
  if isDone then
    return (newAcc, newState)
  else
    processCommandsCollectTrees ctx newState newAcc

/-- Analyse a single Lean source file, returning every (position, tactic) pair
    where a probe tactic succeeds.

    Uses `Frontend.FrontendM` with `snap? := none` and `Elab.async = false`
    so theorem bodies are elaborated synchronously and `TacticInfo` nodes are
    accumulated directly in `commandState.infoState.trees`. -/
def analyzeFile
    (filePath : System.FilePath) (probeTactics : Array String) :
    IO (Array ProbeResult) := do
  -- Ensure the Lean stdlib .olean files are findable at runtime
  Lean.initSearchPath (← Lean.findSysroot)
  -- Allow [init] declarations to be executed when importing modules
  unsafe Lean.enableInitializersExecution
  let input ← IO.FS.readFile filePath
  let opts  := Elab.async.set Options.empty false
  let inputCtx := Parser.mkInputContext input filePath.toString
  let (header, parserState, _messages) ← Parser.parseHeader inputCtx
  let (env, _msgs) ← processHeader header opts {} inputCtx
  let initCmdState : Command.State := Command.mkState env {} opts
  let initState : Frontend.State := {
    commandState := initCmdState
    parserState  := parserState
    cmdPos       := 0
  }
  let ctx : Frontend.Context := { inputCtx }
  -- Collect trees from each command (each command's trees are reset before the next)
  let (allTrees, finalState) ← processCommandsCollectTrees ctx initState #[]
  -- Resolve any pending lazy assignments
  let assignment := finalState.commandState.infoState.assignment
  let resolvedTrees := allTrees.map fun t => t.substitute assignment
  let tacticInfos : Array (ContextInfo × TacticInfo) :=
    resolvedTrees.foldl (fun acc t => collectTacticInfos none t acc) #[]
  -- Probe each goal at each tactic step
  let mut results : Array ProbeResult := #[]
  for (ci, ti) in tacticInfos do
    for goal in ti.goalsBefore do
      for tacticStr in probeTactics do
        if ← tryTacticAt ci ti.mctxBefore goal tacticStr then
          let pos := ci.fileMap.toPosition (ti.stx.getPos?.getD 0)
          results := results.push {
            file   := filePath.toString
            line   := pos.line
            column := pos.column
            tactic := tacticStr
          }
  return results

end Goudlokje

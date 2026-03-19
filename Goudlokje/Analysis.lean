import Lean
import Lean.Elab.Frontend
import Lean.Elab.Tactic
import Lean.Elab.Import

namespace Goudlokje

open Lean Elab

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
  let env := ci.env
  match Parser.runParserCategory env `tactic tacticStr with
  | .error _ => return false
  | .ok stx =>
    try
      let ctx : Core.Context := {
        currNamespace := ci.currNamespace
        openDecls     := ci.openDecls
        fileName      := "<probe>"
        fileMap       := ci.fileMap
        options       := ci.options
      }
      let coreState : Core.State := { env := ci.env, ngen := ci.ngen }
      let metaCtx : Meta.Context := {}
      let metaState : Meta.State := { mctx := mctxBefore }
      let termCtx : Term.Context := { declName? := ci.parentDecl? }
      let termState : Term.State := {}
      let action : Term.TermElabM Bool := do
        let goals ← Tactic.run goal (Tactic.evalTactic stx)
        return goals.isEmpty
      let (result, _, _, _) ← Term.TermElabM.toIO action ctx coreState metaCtx metaState termCtx termState
      return result
    catch _ => return false

/-- Analyse a single Lean source file, returning every (position, tactic) pair
    where a probe tactic succeeds. -/
def analyzeFile
    (filePath : System.FilePath) (probeTactics : Array String) :
    IO (Array ProbeResult) := do
  let input ← IO.FS.readFile filePath
  let opts  := Options.empty
  let inputCtx := Parser.mkInputContext input filePath.toString
  let (header, parserState, _messages) ← Parser.parseHeader inputCtx
  let (env, _msgs) ← processHeader header opts {} inputCtx
  -- Enable InfoTree collection
  let cmdState : Command.State := {
    (Command.mkState env {} opts) with
    infoState := { enabled := true }
  }
  let finalState ← IO.processCommands inputCtx parserState cmdState
  -- Extract tactic info nodes
  let trees     := finalState.commandState.infoState.trees
  let tacticInfos : Array (ContextInfo × TacticInfo) :=
    trees.foldl (fun acc t => collectTacticInfos none t acc) #[]
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

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

/-- Return true if the tactic is a Lean Verbose step-boundary tactic.
    These tactics introduce a new sub-goal (the "step goal") in a Verbose proof.
    Kind names discovered empirically by inspecting the Verbose English library. -/
private def isVerboseStepBoundary (ti : TacticInfo) : Bool :=
  let k := ti.stx.getKind.toString
  k == "tacticLet'sFirstProveThat_" ||
  k == "tacticLet'sNowProveThat_"   ||
  k == "tacticLet'sProveThat_Works_"

/-- When `filterVerboseSteps` is true, keep only:
    - Non-boundary tactics that are the FIRST tactic in their Verbose step body.
    Tactics before any step boundary, and step boundary tactics themselves, are dropped.
    This suppresses sub-step noise: shortcuts at intermediate positions within a step. -/
private def applyVerboseStepFilter
    (infos : Array (ContextInfo × TacticInfo)) (fileMap : FileMap) :
    Array (ContextInfo × TacticInfo) :=
  -- Early exit: no step boundaries present → no filtering needed
  if !infos.any (fun (_, ti) => isVerboseStepBoundary ti) then infos
  else
    -- Sort by source position
    let withPos := infos.map fun (ci, ti) =>
      (fileMap.toPosition (ti.stx.getPos?.getD 0), ci, ti)
    let sorted := withPos.toList.mergeSort (fun (p1, _, _) (p2, _, _) =>
      p1.line < p2.line || (p1.line == p2.line && p1.column < p2.column))
    -- Walk the sorted list: keep only the first non-boundary per step.
    -- State: (result, inStep, stepGotFirst)
    let (result, _, _) := sorted.foldl
      (fun (acc : Array (ContextInfo × TacticInfo) × Bool × Bool) (_, ci, ti) =>
        let (result, inStep, stepGotFirst) := acc
        if isVerboseStepBoundary ti then
          -- New step: reset tracking; boundary itself is not kept
          (result, true, false)
        else if inStep && !stepGotFirst then
          -- First tactic in this step body: keep it
          (result.push (ci, ti), true, true)
        else
          -- Before any boundary, or subsequent within step: suppress
          (result, inStep, stepGotFirst))
      (#[], false, false)
    result

/-- Collect all unique syntax kind names from TacticInfo nodes in a file.
    Useful for debugging and discovering kind names for Verbose/Waterproof tactics. -/
def collectTacticKinds (filePath : System.FilePath) : IO (Array String) := do
  Lean.initSearchPath (← Lean.findSysroot)
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
  let (allTrees, finalState) ← processCommandsCollectTrees ctx initState #[]
  let assignment := finalState.commandState.infoState.assignment
  let resolvedTrees := allTrees.map fun t => t.substitute assignment
  let tacticInfos : Array (ContextInfo × TacticInfo) :=
    resolvedTrees.foldl (fun acc t => collectTacticInfos none t acc) #[]
  let kinds := tacticInfos.foldl (fun acc (_, ti) =>
    let k := ti.stx.getKind.toString
    if acc.contains k then acc else acc.push k) #[]
  return kinds

/-- A cache mapping import-header text to compiled environments.
    Reusing environments across files with the same imports avoids redundant
    `.olean` loading (the dominant cost for files that import Mathlib). -/
abbrev EnvCache := IO.Ref (Array (String × Environment))

/-- Create a fresh empty environment cache. -/
def mkEnvCache : IO EnvCache := IO.mkRef #[]

/-- Look up or build the environment for a set of imports.
    `key` uniquely identifies the import set (e.g. the raw header text).
    `build` is called only on a cache miss to produce the `Environment`. -/
private def getOrBuildEnv
    (cache : EnvCache) (key : String) (build : IO Environment) : IO Environment := do
  let cached ← cache.get
  match cached.find? (fun (k, _) => k == key) with
  | some (_, env) => return env
  | none =>
    let env ← build
    cache.modify (fun arr => arr.push (key, env))
    return env

/-- Analyse a single Lean source file, returning every (position, tactic) pair
    where a probe tactic succeeds.

    Uses `Frontend.FrontendM` with `snap? := none` and `Elab.async = false`
    so theorem bodies are elaborated synchronously and `TacticInfo` nodes are
    accumulated directly in `commandState.infoState.trees`.

    If `envCache` is provided, the compiled environment for the file's imports
    is reused across files with identical import lists, avoiding redundant
    `.olean` loading. -/
def analyzeFile
    (filePath : System.FilePath) (probeTactics : Array String)
    (filterVerboseSteps : Bool := false)
    (envCache : Option EnvCache := none) :
    IO (Array ProbeResult) := do
  -- Ensure the Lean stdlib .olean files are findable at runtime
  Lean.initSearchPath (← Lean.findSysroot)
  -- Allow [init] declarations to be executed when importing modules
  unsafe Lean.enableInitializersExecution
  let input ← IO.FS.readFile filePath
  let opts  := Elab.async.set Options.empty false
  let inputCtx := Parser.mkInputContext input filePath.toString
  let (header, parserState, _messages) ← Parser.parseHeader inputCtx
  -- Cache key: all `import` lines at the top of the file (whitespace-terminated).
  -- Files sharing the same import set produce the same key and reuse the same env.
  let headerKey := "\n".intercalate
    (input.splitOn "\n" |>.takeWhile fun l =>
      l.startsWith "import " || l.startsWith "--" || l.isEmpty)
  let env ← match envCache with
    | some cache =>
      getOrBuildEnv cache headerKey do
        let (env, _) ← processHeader header opts {} inputCtx; pure env
    | none => do let (env, _) ← processHeader header opts {} inputCtx; pure env
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
  let allTacticInfos : Array (ContextInfo × TacticInfo) :=
    resolvedTrees.foldl (fun acc t => collectTacticInfos none t acc) #[]
  -- Optionally restrict to first-in-step positions for Lean Verbose proofs
  let tacticInfos :=
    if filterVerboseSteps then
      applyVerboseStepFilter allTacticInfos inputCtx.fileMap
    else
      allTacticInfos
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
  -- Deduplicate: multiple InfoTree nodes can cover the same tactic step,
  -- and each goal in goalsBefore is probed independently, so the same
  -- (file, line, column, tactic) tuple can appear several times.
  return results.foldl (fun acc r => if acc.contains r then acc else acc.push r) #[]

end Goudlokje

import Goudlokje.Expectations

/-!
# Worksheets

Finds the worksheets the CLI works on and their build state, by asking Lake. A worksheet is a Lean
source file that is a module of a library in the Lake workspace.
-/

namespace Goudlokje.Cli

open System

/-- The Lean source files among `paths`; directories are searched recursively, skipping hidden
    directories such as `.lake`. -/
partial def findLeanFiles (paths : Array FilePath) : IO (Array FilePath) :=
  paths.foldlM (init := #[]) fun acc path => do
    if ← path.isDir then
      let entries ← path.readDir
      let children := entries.filterMap fun e =>
        if e.fileName.startsWith "." then none else some e.path
      return acc ++ (← findLeanFiles (children.qsort (·.toString < ·.toString)))
    else if path.extension == some "lean" then
      return acc.push path
    else return acc

/-- The build state of a worksheet. -/
inductive BuildState where
  /-- Built and up to date; the module's `.olean` is at this path. -/
  | upToDate (olean : FilePath)
  /-- Not built, or out of date: the next build elaborates it. -/
  | outdated
  /-- Not a module of the workspace (e.g. the lakefile). -/
  | unknown
  deriving Inhabited

/-- A worksheet and its build state. -/
structure Worksheet where
  source : FilePath
  state  : BuildState
  deriving Inhabited

/-- Runs `lake` with `args`, capturing its output. -/
def lakeOutput (args : Array String) : IO IO.Process.Output :=
  IO.Process.output { cmd := "lake", args }

/-- The `.olean` paths of `files`, if all of them are up to date. -/
private def queryUpToDate (files : Array FilePath) : IO (Option (Array FilePath)) := do
  let out ← lakeOutput (#["query", "--no-build"] ++ files.map (s!"{·}:olean"))
  if out.exitCode != 0 then return none
  let lines := (out.stdout.splitOn "\n").filter (!·.isEmpty)
  if lines.length != files.size then return none
  return some (lines.toArray.map FilePath.mk)

/-- The build state of a single file. -/
private def queryState (file : FilePath) : IO BuildState := do
  let out ← lakeOutput #["query", "--no-build", s!"{file}:olean"]
  if out.exitCode == 0 then
    return .upToDate out.stdout.trimAscii.toString
  else if (out.stderr.splitOn "unknown target").length > 1 then
    return .unknown
  else
    return .outdated

/-- Runs `f` on every element of `xs`, at most `jobs` at a time. -/
def parallelMap (xs : Array α) (f : α → IO β) (jobs := 8) : IO (Array β) := do
  let mut results := #[]
  for chunk in (List.range ((xs.size + jobs - 1) / jobs)).map fun i => xs.extract (i * jobs) ((i + 1) * jobs) do
    let tasks ← chunk.mapM fun x => IO.asTask (f x)
    for task in tasks do
      results := results.push (← IO.ofExcept task.get)
  return results

/-- The worksheets among `paths` (files and directories) with their build state. Files that are
    not modules of the workspace are left out; they are reported if named explicitly. -/
def findWorksheets (paths : Array FilePath) : IO (Array Worksheet) := do
  let files ← findLeanFiles paths
  if files.isEmpty then return #[]
  -- Usually everything is up to date and one query suffices.
  if let some oleans ← queryUpToDate files then
    return files.zipWith (fun source olean => { source, state := .upToDate olean }) oleans
  let states ← parallelMap files queryState
  let mut worksheets := #[]
  for source in files, state in states do
    match state with
    | .unknown =>
      if paths.contains source then
        IO.eprintln s!"warning: {source} is not a module of a library in this Lake workspace; skipped"
    | _ => worksheets := worksheets.push { source, state }
  return worksheets

/-- Makes Lake rebuild `w` on the next build, by removing its trace file. -/
def invalidate (w : Worksheet) : IO Unit := do
  if let .upToDate olean := w.state then
    let trace := olean.withExtension "trace"
    if ← trace.pathExists then IO.FS.removeFile trace

/-- Whether the worksheet's `.test.json` changed after the worksheet was last built, so the build
    result does not reflect it. -/
def expectationsChanged (w : Worksheet) : IO Bool := do
  let .upToDate olean := w.state | return false
  let testJson := testJsonPath w.source
  unless ← testJson.pathExists do return false
  return (← testJson.metadata).modified > (← olean.metadata).modified

/-- Runs `lake build` on the worksheets, with output going to the terminal; returns whether the
    build succeeded. -/
def build (worksheets : Array Worksheet) (env : Array (String × Option String) := #[]) :
    IO Bool := do
  let child ← IO.Process.spawn {
    cmd := "lake", args := #["build"] ++ worksheets.map (·.source.toString), env }
  return (← child.wait) == 0

end Goudlokje.Cli

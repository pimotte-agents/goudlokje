import Goudlokje.Cli.Worksheets
import Goudlokje.Cli.Changes

/-!
# `goudlokje check` and `goudlokje update`

Both work on worksheets: modules of a library in the current Lake workspace that import
`Goudlokje`. The checks themselves run as linters during `lake build`.

* `check` builds the worksheets. Findings that `.test.json` does not expect are errors, so the
  build fails. Worksheets whose `.test.json` changed since they were built are rebuilt, since Lake
  does not track that file.
* `update` rebuilds the worksheets with results requested (see `resultsDirVar`) and updates their
  `.test.json` files: new findings are recorded as expected, stale expectations removed, after
  confirmation or, with `--all`, directly.
-/

namespace Goudlokje.Cli

open System

/-- `goudlokje check`; returns the exit code. -/
def check (paths : Array FilePath) : IO UInt32 := do
  let worksheets ← findWorksheets paths
  if worksheets.isEmpty then
    IO.eprintln "No worksheets found."
    return 1
  for w in worksheets do
    if ← expectationsChanged w then invalidate w
  return if ← build worksheets then 0 else 1

/-- Asks a yes/no question on the terminal; the default is no. -/
private def confirm (question : String) : IO Bool := do
  IO.print s!"{question}? [y/N] "
  (← IO.getStdout).flush
  let answer ← (← IO.getStdin).getLine
  return answer.trimAscii.toString.toLower == "y"

/-- Updates the `.test.json` of worksheet `source` according to `results`. -/
private def updateWorksheet (source : FilePath) (results : ModuleResults) (all : Bool) :
    IO Unit := do
  let path := testJsonPath source
  let old ← match ← loadExpectations path with
    | .ok old => pure old
    | .error e =>
      IO.eprintln s!"error: {e}; not updating it (fix or delete the file first)"
      return
  for name in results.skipped do
    IO.eprintln s!"warning: {source}: exercise {name.quote} has errors; its expectations are kept"
  let mut new := old
  for change in proposeChanges old results do
    if change.automatic || all then
      IO.println s!"{source}: {change.describe}."
      new := change.apply new
    else if ← confirm s!"{source}: {change.describe}" then
      new := change.apply new
  if Lean.toJson new == Lean.toJson old then return
  if new.exercises.isEmpty then
    if ← path.pathExists then IO.FS.removeFile path
  else
    saveExpectations path new

/-- `goudlokje update`; returns the exit code. -/
def update (paths : Array FilePath) (all : Bool) : IO UInt32 := do
  let worksheets ← findWorksheets paths
  if worksheets.isEmpty then
    IO.eprintln "No worksheets found."
    return 1
  IO.FS.withTempDir fun dir => do
    worksheets.forM invalidate
    IO.println s!"Checking {worksheets.size} worksheet(s)..."
    -- Unexpected findings are errors, so the build is expected to fail; its output is only
    -- shown for worksheets that could not be checked.
    let out ← IO.Process.output {
      cmd := "lake", args := #["build"] ++ worksheets.map (·.source.toString)
      env := #[(resultsDirVar, some dir.toString)] }
    let mut results : Std.HashMap FilePath ModuleResults := {}
    for entry in ← dir.readDir do
      match parseResultLines (← IO.FS.readFile entry.path) with
      | .ok records =>
        for (file, record) in records do
          let file ← IO.FS.realPath file
          results := results.insert file ((results.getD file {}).add record)
      | .error e => throw (IO.userError s!"cannot read results file {entry.path}: {e}")
    let mut shownOutput := false
    for w in worksheets do
      match results[← IO.FS.realPath w.source]? with
      | some r => updateWorksheet w.source r all
      | none =>
        -- No exercise was checked: there are none, or the file does not elaborate. Only
        -- worth mentioning if there are expectations that are now not updated.
        unless ← (testJsonPath w.source).pathExists do continue
        if out.exitCode != 0 && !shownOutput then
          shownOutput := true
          IO.eprint (out.stdout ++ out.stderr)
        IO.eprintln s!"warning: {w.source}: no exercises were checked; its .test.json is kept"
    return 0

end Goudlokje.Cli

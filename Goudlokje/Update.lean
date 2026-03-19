import Goudlokje.Config
import Goudlokje.Discovery
import Goudlokje.Analysis
import Goudlokje.TestFile
import Goudlokje.Shortcuts

namespace Goudlokje

/-- Prompt the user for a yes/no answer. Returns true for 'y'/'Y'. -/
private def promptYN (prompt : String) : IO Bool := do
  IO.print prompt
  let line ← (← IO.getStdin).getLine
  return line.trimAscii.toString.toLower == "y"

/-- Run update mode: interactively (or with --all) accept shortcuts and persist them.
    Stale entries are removed (with confirmation unless --all). -/
def runUpdate (paths : Array System.FilePath) (cfg : Config) (acceptAll : Bool) : IO Unit := do
  let worksheets ← discoverWorksheets paths
  for ws in worksheets do
    let found ← analyzeFile ws.sourcePath cfg.tactics
    let testPath := ws.testPath.getD (ws.sourcePath.withExtension "test.json")
    let tf    ← TestFile.load testPath
    let cr    := classify found tf

    let mut newExpected := tf.expected

    -- Handle unexpected shortcuts
    for r in cr.shortcuts do
      if let .unexpected p := r then
        let accept ← do
          if acceptAll then
            IO.println s!"Accepting shortcut at {p.file}:{p.line}:{p.column} — `{p.tactic}`"
            pure true
          else
            promptYN s!"Shortcut at {p.file}:{p.line}:{p.column} — `{p.tactic}`. Accept? [y/N] "
        if accept then
          newExpected := newExpected.push {
            file   := p.file
            line   := p.line
            column := p.column
            tactic := p.tactic
          }

    -- Handle stale entries
    for s in cr.stale do
      let remove ← do
        if acceptAll then
          IO.println s!"Removing stale entry {s.entry.file}:{s.entry.line}:{s.entry.column} — `{s.entry.tactic}`"
          pure true
        else
          promptYN s!"Stale entry at {s.entry.file}:{s.entry.line}:{s.entry.column} — `{s.entry.tactic}`. Remove? [y/N] "
      if remove then
        newExpected := newExpected.filter (· != s.entry)

    let newTf : TestFile := { expected := newExpected }
    newTf.save testPath

end Goudlokje

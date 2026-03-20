import Goudlokje.Config
import Goudlokje.Discovery
import Goudlokje.Analysis
import Goudlokje.TestFile
import Goudlokje.Shortcuts

namespace Goudlokje

/-- Run check mode: analyse worksheets and report any unexpected shortcuts.
    Returns the number of unexpected shortcuts found (non-zero → CI failure).
    When `debug` is true, prints additional analysis statistics per file. -/
def runCheck (paths : Array System.FilePath) (cfg : Config) (debug : Bool := false) : IO Nat := do
  let worksheets ← discoverWorksheets paths
  if debug then
    IO.println s!"Probing with {cfg.tactics.size} tactic(s): {", ".intercalate cfg.tactics.toList}"
  let mut unexpectedCount := 0
  for ws in worksheets do
    IO.println s!"Checking {ws.sourcePath}..."
    let found ← analyzeFile ws.sourcePath cfg.tactics cfg.filterVerboseSteps
    let tf    ← TestFile.load (ws.testPath.getD (ws.sourcePath.withExtension "test.json"))
    let cr    := classify found tf
    if debug then
      IO.println s!"  Found {found.size} probe result(s), {cr.shortcuts.size} shortcut(s), {cr.stale.size} stale entry/entries"
    for r in cr.shortcuts do
      printShortcutResult r
      if let .unexpected _ := r then
        unexpectedCount := unexpectedCount + 1
    for s in cr.stale do
      printStaleEntry s
  return unexpectedCount

end Goudlokje

import Goudlokje.Config
import Goudlokje.Discovery
import Goudlokje.Analysis
import Goudlokje.TestFile
import Goudlokje.Shortcuts

namespace Goudlokje

/-- Run check mode: analyse worksheets and report any unexpected shortcuts.
    Returns the number of unexpected shortcuts found (non-zero → CI failure). -/
def runCheck (paths : Array System.FilePath) (cfg : Config) : IO Nat := do
  let worksheets ← discoverWorksheets paths
  let mut unexpectedCount := 0
  for ws in worksheets do
    let found ← analyzeFile ws.sourcePath cfg.tactics
    let tf    ← TestFile.load (ws.testPath.getD (ws.sourcePath.withExtension "test.json"))
    let cr    := classify found tf
    for r in cr.shortcuts do
      printShortcutResult r
      if let .unexpected _ := r then
        unexpectedCount := unexpectedCount + 1
    for s in cr.stale do
      printStaleEntry s
  return unexpectedCount

end Goudlokje

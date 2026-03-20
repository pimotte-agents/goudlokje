import Goudlokje.Config
import Goudlokje.Discovery
import Goudlokje.Analysis
import Goudlokje.TestFile
import Goudlokje.Shortcuts

namespace Goudlokje

/-- Run check mode: analyse worksheets and report any unexpected shortcuts.
    Returns the number of unexpected shortcuts found (non-zero → CI failure).
    When `debug` is true, prints analysis statistics per file.
    When `verbose` is true, implies `debug` and additionally lists all discovered
    worksheets upfront and logs every individual probe hit per file. -/
def runCheck (paths : Array System.FilePath) (cfg : Config) (debug : Bool := false) (verbose : Bool := false) : IO Nat := do
  let worksheets ← discoverWorksheets paths
  let debugMode := debug || verbose
  if verbose then
    IO.println s!"Discovered {worksheets.size} worksheet(s):"
    for ws in worksheets do
      IO.println s!"  {ws.sourcePath}"
  if debugMode then
    IO.println s!"Probing with {cfg.tactics.size} tactic(s): {", ".intercalate cfg.tactics.toList}"
  let cache ← mkEnvCache
  let mut unexpectedCount := 0
  for ws in worksheets do
    IO.println s!"Checking {ws.sourcePath}..."
    let probeLog : Option (Nat → Nat → String → Bool → IO Unit) :=
      if verbose then
        some fun line col tactic succeeded =>
          let mark := if succeeded then "✓" else "✗"
          IO.println s!"  Probe {mark} {line}:{col} — `{tactic}`"
      else none
    let found ← analyzeFile ws.sourcePath cfg.tactics cfg.filterVerboseSteps (some cache) probeLog
    let tf    ← TestFile.load (ws.testPath.getD (ws.sourcePath.withExtension "test.json"))
    let cr    := classify found tf
    if debugMode then
      IO.println s!"  Found {found.size} probe result(s), {cr.shortcuts.size} shortcut(s), {cr.stale.size} stale entry/entries"
    for r in cr.shortcuts do
      printShortcutResult r
      if let .unexpected _ := r then
        unexpectedCount := unexpectedCount + 1
    for s in cr.stale do
      printStaleEntry s
  return unexpectedCount

end Goudlokje

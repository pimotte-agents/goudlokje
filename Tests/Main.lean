import Tests.Config
import Tests.TestFile
import Tests.Shortcuts
import Tests.Analysis

def main : IO UInt32 := do
  IO.println "=== Config tests ==="
  Tests.Config.runAll
  IO.println ""
  IO.println "=== TestFile tests ==="
  Tests.TestFile.runAll
  IO.println ""
  IO.println "=== Shortcuts tests ==="
  Tests.Shortcuts.runAll
  IO.println ""
  IO.println "=== Analysis integration tests ==="
  Tests.Analysis.runAll
  IO.println ""
  IO.println "All tests passed."
  return 0

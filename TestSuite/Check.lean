import Goudlokje.Check
import Goudlokje.Config

namespace TestSuite.Check

open Goudlokje

/-- End-to-end: `runCheck` must return > 0 when unexpected shortcuts exist.
    `Simple.lean` has no `.test.json`, so all found shortcuts are unexpected. -/
def testCheckNonZeroForUnexpectedShortcuts : IO Unit := do
  let cfg : Config := { tactics := #["decide"] }
  let n ← runCheck #["TestSuite/Fixtures/Simple.lean"] cfg
  unless n > 0 do
    throw (IO.userError
      s!"testCheckNonZero: expected >0 unexpected shortcuts, got {n}")

/-- End-to-end: `runCheck` must return 0 when no tactics are configured. -/
def testCheckZeroWithEmptyTactics : IO Unit := do
  let cfg : Config := { tactics := #[] }
  let n ← runCheck #["TestSuite/Fixtures/Simple.lean"] cfg
  unless n == 0 do
    throw (IO.userError
      s!"testCheckZero: expected 0 with empty tactics, got {n}")

/-- `runCheck` with debug=true must still return the correct non-zero count. -/
def testCheckDebugMode : IO Unit := do
  let cfg : Config := { tactics := #["decide"] }
  let n ← runCheck #["TestSuite/Fixtures/Simple.lean"] cfg (debug := true)
  unless n > 0 do
    throw (IO.userError
      s!"testCheckDebugMode: expected >0 unexpected shortcuts, got {n}")

/-- `runCheck` with verbose=true must still return the correct non-zero count. -/
def testCheckVerboseMode : IO Unit := do
  let cfg : Config := { tactics := #["decide"] }
  let n ← runCheck #["TestSuite/Fixtures/Simple.lean"] cfg (verbose := true)
  unless n > 0 do
    throw (IO.userError
      s!"testCheckVerboseMode: expected >0 unexpected shortcuts, got {n}")

def runAll : IO Unit := do
  testCheckNonZeroForUnexpectedShortcuts;
    IO.println "  ✓ testCheckNonZeroForUnexpectedShortcuts"
  testCheckZeroWithEmptyTactics;
    IO.println "  ✓ testCheckZeroWithEmptyTactics"
  testCheckDebugMode;
    IO.println "  ✓ testCheckDebugMode"
  testCheckVerboseMode;
    IO.println "  ✓ testCheckVerboseMode"

end TestSuite.Check

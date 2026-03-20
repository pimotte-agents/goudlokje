import Goudlokje.Update
import Goudlokje.Config
import Goudlokje.TestFile

namespace TestSuite.Update

open Goudlokje

/-- Set up a temporary workspace containing a single `.lean` file.
    Returns the file path and the expected `.test.json` path. -/
private def setupTempWorkspace (dir : System.FilePath) : IO (System.FilePath × System.FilePath) := do
  try IO.FS.createDir dir catch _ => pure ()
  let leanFile := dir / "Fixture.lean"
  -- A vanilla Lean file with a trivially shortcuttable proof.
  -- `decide` closes the goal `1 + 1 = 2` at the `rfl` step.
  IO.FS.writeFile leanFile
    "theorem simple : 1 + 1 = 2 := by\n  rfl\n"
  let testJson := dir / "Fixture.test.json"
  -- Ensure any leftover from a previous run is removed.
  try IO.FS.removeFile testJson catch _ => pure ()
  return (leanFile, testJson)

/-- `runUpdate --all` must write a `.test.json` listing every found shortcut. -/
def testUpdateAllCreatesTestFile : IO Unit := do
  let dir : System.FilePath := "/tmp/goudlokje_update_create"
  let (leanFile, testJson) ← setupTempWorkspace dir
  let cfg : Config := { tactics := #["decide"] }
  runUpdate #[leanFile] cfg true   -- acceptAll = true
  unless ← testJson.pathExists do
    throw (IO.userError "testUpdateAllCreates: .test.json was not created")
  let tf ← TestFile.load testJson
  unless tf.expected.size ≥ 1 do
    throw (IO.userError
      s!"testUpdateAllCreates: expected ≥1 entries in test file, got {tf.expected.size}")

/-- `runUpdate --all` on a file that already has a `.test.json` must merge
    new shortcuts and not duplicate existing ones. -/
def testUpdateAllIdempotent : IO Unit := do
  let dir : System.FilePath := "/tmp/goudlokje_update_idem"
  let (leanFile, testJson) ← setupTempWorkspace dir
  let cfg : Config := { tactics := #["decide"] }
  -- First pass: write the test file.
  runUpdate #[leanFile] cfg true
  let tf1 ← TestFile.load testJson
  -- Second pass: should not add duplicates.
  runUpdate #[leanFile] cfg true
  let tf2 ← TestFile.load testJson
  unless tf1.expected.size == tf2.expected.size do
    throw (IO.userError
      s!"testUpdateAllIdempotent: size changed from {tf1.expected.size} to {tf2.expected.size}")

/-- `runUpdate --all` with no tactics writes an empty `.test.json`. -/
def testUpdateAllNoTactics : IO Unit := do
  let dir : System.FilePath := "/tmp/goudlokje_update_notactics"
  let (leanFile, testJson) ← setupTempWorkspace dir
  let cfg : Config := { tactics := #[] }
  runUpdate #[leanFile] cfg true
  unless ← testJson.pathExists do
    throw (IO.userError "testUpdateAllNoTactics: .test.json was not created")
  let tf ← TestFile.load testJson
  unless tf.expected.size == 0 do
    throw (IO.userError
      s!"testUpdateAllNoTactics: expected 0 entries, got {tf.expected.size}")

def runAll : IO Unit := do
  testUpdateAllCreatesTestFile;
    IO.println "  ✓ testUpdateAllCreatesTestFile"
  testUpdateAllIdempotent;
    IO.println "  ✓ testUpdateAllIdempotent"
  testUpdateAllNoTactics;
    IO.println "  ✓ testUpdateAllNoTactics"

end TestSuite.Update

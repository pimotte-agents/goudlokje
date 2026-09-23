import Lean.Data.Json
import Lean.Elab.Command
import Goudlokje.FileCache

/-!
# Expectations

The `<worksheet>.test.json` companion file records what is *expected* in a worksheet: shortcuts
that are acceptable and lint findings that are documented, per exercise. Steps are identified by
their line relative to the first step of the exercise, so edits elsewhere in the file do not
invalidate them.

```json
{
  "testJsonVersion": 2,
  "exercises": {
    "1.1.13": {
      "shortcuts": [{ "step": 1, "tactic": "decide" }],
      "lint": [{ "check": "typeAscription", "step": 3 }],
      "allowSorry": true
    }
  }
}
```
-/

namespace Goudlokje

open Lean

/-- The current version of the `.test.json` format. -/
def testJsonVersion : Nat := 2

/-- A probe tactic that is expected to close the goal at a step. -/
structure ExpectedShortcut where
  step   : Nat
  tactic : String
  deriving Repr, BEq, Hashable, Inhabited, ToJson, FromJson

/-- A documented lint finding at a step. -/
structure ExpectedLint where
  check : String
  step  : Nat
  deriving Repr, BEq, Hashable, Inhabited, ToJson, FromJson

/-- What is expected in one exercise. -/
structure ExerciseExpectations where
  shortcuts  : Array ExpectedShortcut := #[]
  lint       : Array ExpectedLint := #[]
  /-- The exercise may contain `sorry`, e.g. a true-or-false exercise whose statement is false. -/
  allowSorry : Bool := false
  deriving Repr, BEq, Inhabited

/-- The contents of a `.test.json` file. -/
structure Expectations where
  exercises : Std.TreeMap String ExerciseExpectations compare := {}
  deriving Inhabited

/-- Reads field `key` of `json`, or returns `default` if the field is absent. -/
private def optField [FromJson α] (json : Json) (key : String) (default : α) : Except String α :=
  match json.getObjVal? key with
  | .ok value => fromJson? value
  | .error _ => pure default

instance : FromJson ExerciseExpectations where
  fromJson? json := do
    return {
      shortcuts  := ← optField json "shortcuts" #[]
      lint       := ← optField json "lint" #[]
      allowSorry := ← optField json "allowSorry" false
    }

instance : ToJson ExerciseExpectations where
  toJson e := Json.mkObj <|
    (if e.shortcuts.isEmpty then [] else [("shortcuts", toJson e.shortcuts)]) ++
    (if e.lint.isEmpty then [] else [("lint", toJson e.lint)]) ++
    (if e.allowSorry then [("allowSorry", toJson true)] else [])

instance : FromJson Expectations where
  fromJson? json := do
    let version : Nat ← json.getObjValAs? Nat "testJsonVersion"
      |>.mapError fun _ => "missing `testJsonVersion`"
    unless version == testJsonVersion do
      throw s!"unsupported `testJsonVersion` {version}, expected {testJsonVersion}"
    let exercises ← (← json.getObjVal? "exercises").getObj?
    exercises.foldlM (init := {}) fun acc name value => do
      let e ← fromJson? value |>.mapError (s!"exercise {name.quote}: " ++ ·)
      return { exercises := acc.exercises.insert name e }

instance : ToJson Expectations where
  toJson e := Json.mkObj [
    ("testJsonVersion", toJson testJsonVersion),
    ("exercises", Json.mkObj <| e.exercises.toList.map fun (name, ex) => (name, toJson ex))
  ]

/-- The expectations for exercise `name` (empty if it is not listed). -/
def Expectations.get (e : Expectations) (name : String) : ExerciseExpectations :=
  e.exercises.getD name {}

/-- The companion `.test.json` path of a worksheet. -/
def testJsonPath (worksheet : System.FilePath) : System.FilePath :=
  worksheet.withExtension "test.json"

/-- The result of reading a `.test.json` file. -/
structure LoadedExpectations where
  expectations : Expectations
  /-- Hash of the file contents (0 if there is no file). Recorded by the linters so that
      `goudlokje check` can detect files that changed since the worksheet was built. -/
  contentHash  : UInt64
  deriving Inhabited

/-- Parses the contents of a `.test.json` file. -/
def parseExpectations (contents : String) : Except String Expectations := do
  fromJson? (← Json.parse contents)

/-- Reads the `.test.json` file at `path`; a missing file means no expectations. -/
def loadExpectations (path : System.FilePath) : IO (Except String LoadedExpectations) := do
  unless ← path.pathExists do return .ok { expectations := {}, contentHash := 0 }
  let contents ← IO.FS.readFile path
  return (parseExpectations contents).map ({ expectations := ·, contentHash := hash contents })
    |>.mapError (s!"{path}: " ++ ·)

/-- Persists expectations as pretty-printed JSON. -/
def saveExpectations (path : System.FilePath) (e : Expectations) : IO Unit :=
  IO.FS.writeFile path ((toJson e).pretty ++ "\n")

private initialize expectationsCache : FileCache (Except String LoadedExpectations) ← IO.mkRef {}

/-- The expectations of the worksheet being elaborated. -/
def getExpectations : Elab.Command.CommandElabM (Except String LoadedExpectations) := do
  let path := testJsonPath (← getFileName)
  expectationsCache.get path (loadExpectations path)

end Goudlokje

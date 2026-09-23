import Lean.Linter.Init
import Lean.Data.Json
import Lean.Elab.Command

/-!
# Reporting

How linters report findings: as messages in the editor and build output, and, when the
environment variable `GOUDLOKJE_RESULTS_DIR` is set, as JSON lines for `goudlokje update`: one
file `<module>.jsonl` per module in that directory.
-/

namespace Goudlokje

open Lean Elab

/-- Logs `msg` at `stx` as a message of the linter `linterOption`, with the given severity.
    Like `Lean.Linter.logLint` (so the message is recognised and persisted as a linter message),
    but findings that must fail the build can be errors. -/
def logFinding [Monad m] [MonadLog m] [AddMessageContext m] [MonadOptions m]
    (linterOption : Lean.Option Bool) (stx : Syntax) (severity : MessageSeverity)
    (msg : MessageData) : m Unit :=
  let disable := .note m!"This linter can be disabled with `set_option {linterOption.name} false`"
  logAt stx (.tagged linterOption.name <| .tagged Linter.linterMessageTag m!"{msg}{disable}")
    severity

/-- A finding, as recorded in the results file. -/
structure Finding where
  /-- The linter that found it, e.g. `shortcut`. -/
  check    : String
  exercise : String
  step     : Nat
  line     : Nat
  column   : Nat
  /-- For shortcuts: the probe tactic that closes the goal. -/
  tactic?  : Option String := none
  message  : String
  /-- Whether `.test.json` lists the finding as expected. -/
  expected : Bool
  deriving Repr, BEq, Inhabited, ToJson, FromJson

/-- A record in the results file. -/
inductive ResultRecord where
  /-- An exercise that was checked by the checks named `checks`, so `update` knows which
      exercises still exist and which expectations could have been confirmed. -/
  | exercise (name : String) (checks : Array String)
  /-- A command that could not be checked because it has errors; `update` keeps its
      expectations. -/
  | skipped (name : String)
  | finding (finding : Finding)
  deriving Repr, BEq

instance : ToJson ResultRecord where
  toJson
    | .exercise name checks => Json.mkObj [("exercise", name), ("checks", toJson checks)]
    | .skipped name => Json.mkObj [("skipped", name)]
    | .finding finding => Json.mkObj [("finding", toJson finding)]

instance : FromJson ResultRecord where
  fromJson? json :=
    (return .exercise (← json.getObjValAs? String "exercise")
      (← json.getObjValAs? (Array String) "checks")) <|>
    (return .skipped (← json.getObjValAs? String "skipped")) <|>
    (return .finding (← json.getObjValAs? Finding "finding"))

/-- The environment variable naming the results directory. -/
def resultsDirVar : String := "GOUDLOKJE_RESULTS_DIR"

/-- The results file of the current module, if results are requested. -/
def resultsFile? : Elab.Command.CommandElabM (Option System.FilePath) := do
  let some dir ← IO.getEnv resultsDirVar | return none
  return some (System.FilePath.mk dir / s!"{← getMainModule}.jsonl")

/-- Appends `record` about source file `file` to the results file `path` as one JSON line, with
    the file in field `file`. Each record is written with a single append, so records of
    concurrently linted commands do not interleave. -/
def emitRecord (path : System.FilePath) (file : String) (record : ResultRecord) : IO Unit := do
  let handle ← IO.FS.Handle.mk path .append
  handle.putStr (((toJson record).setObjVal! "file" file).compress ++ "\n")

end Goudlokje

import Lean.Linter.Init
import Lean.Data.Json

/-!
# Reporting

How linters report findings: as messages in the editor and build output, and, when
`goudlokje.resultsFile` is set, as JSON lines for `goudlokje update`.
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

/-- A record in the results file: `{"exercise": name}` or `{"finding": {...}}`. -/
inductive ResultRecord where
  /-- An exercise that was checked (so `update` knows which exercises still exist). -/
  | exercise (name : String)
  | finding (finding : Finding)
  deriving Repr, BEq

instance : ToJson ResultRecord where
  toJson
    | .exercise name => Json.mkObj [("exercise", name)]
    | .finding finding => Json.mkObj [("finding", toJson finding)]

instance : FromJson ResultRecord where
  fromJson? json :=
    (return .exercise (← json.getObjValAs? String "exercise")) <|>
    (return .finding (← json.getObjValAs? Finding "finding"))

/-- Appends `record` to the results file `path` as one JSON line. Each record is written with a
    single append, so records of concurrently linted commands do not interleave. -/
def emitRecord (path : System.FilePath) (record : ResultRecord) : IO Unit := do
  let handle ← IO.FS.Handle.mk path .append
  handle.putStr ((toJson record).compress ++ "\n")

end Goudlokje

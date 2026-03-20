import Cli
import Goudlokje.Config
import Goudlokje.Check
import Goudlokje.Update

open Cli

private def loadConfig : IO Goudlokje.Config := do
  let path : System.FilePath := ".goudlokje.json"
  if ← path.pathExists then
    Goudlokje.Config.load path
  else
    -- Default: no tactics configured
    return { tactics := #[] }

private def runCheck (p : Parsed) : IO UInt32 := do
  let cfg ← loadConfig
  let rawPaths := p.variableArgsAs! String
  let paths : Array System.FilePath :=
    if rawPaths.isEmpty then #[⟨"."⟩] else rawPaths.map (⟨·⟩)
  let debug := p.hasFlag "debug"
  let n ← Goudlokje.runCheck paths cfg debug
  return if n == 0 then 0 else 1

private def runUpdate (p : Parsed) : IO UInt32 := do
  let cfg ← loadConfig
  let rawPaths := p.variableArgsAs! String
  let paths : Array System.FilePath :=
    if rawPaths.isEmpty then #[⟨"."⟩] else rawPaths.map (⟨·⟩)
  let acceptAll := p.hasFlag "all"
  let debug := p.hasFlag "debug"
  Goudlokje.runUpdate paths cfg acceptAll debug
  return 0

private def checkCmd : Cmd := `[Cli|
  check VIA runCheck;
  "Check Lean worksheets for unexpected shortcuts."

  FLAGS:
    debug; "Print debug information during analysis (probe counts, result statistics)"

  ARGS:
    ...files : String; "Lean files or directories to check (default: current directory)"
]

private def updateCmd : Cmd := `[Cli|
  update VIA runUpdate;
  "Update .test.json files with found shortcuts."

  FLAGS:
    all;   "Accept all shortcuts and remove all stale entries without prompting"
    debug; "Print debug information during analysis (probe counts, result statistics)"

  ARGS:
    ...files : String; "Lean files or directories to update (default: current directory)"
]

private def goudlokjeCmd : Cmd := `[Cli|
  goudlokje NOOP;
  "Worksheet shortcut checker for Lean 4 exercises."

  SUBCOMMANDS:
    checkCmd;
    updateCmd
]

def main (args : List String) : IO UInt32 :=
  goudlokjeCmd.validate args

import Lean.Environment

/-!
# Syntax origin

Classifies syntax kinds by the module that declares their parser. This replaces hand-maintained
lists of kind names: a tactic is a Lean Verbose tactic exactly when its parser lives in a
`Verbose.*` module.
-/

namespace Goudlokje

open Lean

/-- The module that declares the parser for `kind`, if it is imported. -/
def kindModule? (env : Environment) (kind : SyntaxNodeKind) : Option Name :=
  (env.getModuleIdxFor? kind).bind (env.header.moduleNames[·]?)

/-- Whether the parser for `kind` is declared in a Lean Verbose module. -/
def isVerboseKind (env : Environment) (kind : SyntaxNodeKind) : Bool :=
  (kindModule? env kind).any (`Verbose).isPrefixOf

end Goudlokje

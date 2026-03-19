import Lake
open Lake DSL

package "goudlokje" where
  version := v!"0.1.0"

@[default_target]
lean_exe "goudlokje" where
  root := `Main

require "leanprover-community" / "mathlib" @ git "v4.29.0-rc6"

import Lake
open Lake DSL

package "goudlokje" where
  version := v!"0.1.0"

lean_lib "Goudlokje" where
  roots := #[`Goudlokje]

@[default_target]
lean_exe "goudlokje" where
  root := `Main

lean_lib "Tests" where
  roots := #[`Tests]

lean_exe "goudlokje_tests" where
  root := `Tests.Main

require "leanprover-community" / "mathlib" @ git "v4.29.0-rc6"
require "leanprover" / "lean4-cli" @ git "v4.29.0-rc6"

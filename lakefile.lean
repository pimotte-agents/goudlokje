import Lake
open Lake DSL

package "goudlokje" where
  version := v!"0.1.0"

lean_lib "Goudlokje" where
  globs := #[.andSubmodules `Goudlokje]

@[default_target]
lean_exe "goudlokje" where
  root := `Main
  moreLinkArgs := #["-rdynamic"]

lean_lib "TestSuite" where
  roots := #[`TestSuite]

-- FixtureDeps imports Verbose and Waterproof packages so their oleans are compiled.
-- This ensures `analyzeFile` can import them at runtime when processing fixture files.
@[default_target]
lean_lib "FixtureDeps" where
  roots := #[`FixtureDeps]

lean_exe "goudlokje_tests" where
  root := `TestSuite.Main
  moreLinkArgs := #["-rdynamic"]

lean_exe "debug_analysis" where
  root := `DebugAnalysis
  moreLinkArgs := #["-rdynamic"]

require "leanprover" / "lean4-cli" @ git "v4.31.0"
require "waterproof-genre"
      from git "https://github.com/impermeable/waterproof-genre" @ "feature/smaller-genre"
require "verbose-lean4"
      from git "https://github.com/PatrickMassot/verbose-lean4" @ "v4.31.0"

/-- Tests of the linters, run with `lake test`: every module is a test file whose checks
    (`#guard_msgs`, `#guard`) fail the build when they fail. -/
@[test_driver]
lean_lib "Tests" where
  globs := #[.submodules `Tests]

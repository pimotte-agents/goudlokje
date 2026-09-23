import Lake
open Lake DSL

package "goudlokje" where
  version := v!"0.1.0"

@[default_target]
lean_lib "Goudlokje" where
  globs := #[.andSubmodules `Goudlokje]

@[default_target]
lean_exe "goudlokje" where
  root := `Main

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

/-! The end-to-end test `e2e/run.sh` copies worksheets to `e2e/work` and checks them as the
    following libraries. -/

/-- The worksheet used to test the `check` and `update` commands. -/
lean_lib E2EWorksheets where
  srcDir := "e2e/work"
  globs := #[.submodules `Worksheets]
  leanOptions := #[
    ⟨`weak.goudlokje.probes, "decide;; norm_num"⟩,
    ⟨`weak.goudlokje.allowedTactics, "show;; norm_num"⟩
  ]

/-- Regression fixtures, checked with the probes the project used before the linter refactor. -/
lean_lib E2EFixtures where
  srcDir := "e2e/work"
  globs := #[.submodules `Fixtures]
  leanOptions := #[⟨`weak.goudlokje.probes, "decide;; tauto;; omega;; norm_num;; simp;; ring"⟩]

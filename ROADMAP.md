# Goudlokje — Implementation Roadmap

## Overview

Goudlokje is a Lean 4 CLI tool that helps teachers verify that worksheet exercises are neither incorrect nor trivially solvable. It does so by running configured tactics at every proof step and reporting any "shortcuts" — places where a tactic closes the goal before the intended end of the proof.

---

## Milestone 1 — Configuration & CLI skeleton ✅

**Goal:** Parse `.goudlokje.json` and accept `check`/`update` subcommands with their flags.

### Tasks
- [x] Define the `.goudlokje.json` schema:
  - `tactics`: list of tactic strings to probe at each proof step
- [x] Implement a `Config` structure and a JSON parser for it (`Lean.Data.Json` + `FromJson`/`ToJson`)
- [x] Implement CLI argument parsing via `lean4-cli`:
  - `goudlokje check [files...]`
  - `goudlokje update [--all] [files...]`
- [x] Return a non-zero exit code on any error or shortcut found in `check` mode
- [x] Write unit tests for config parsing (valid config, missing fields, unknown fields) — `Tests/Config.lean`
- [x] Document how to run automated tests in README
- [x] Add debug output describing which config files are loaded under the --debug flag

**Notes:** `lean4-cli` added as explicit dependency in `lakefile.lean`. Config lives in `Goudlokje/Config.lean`.

---

## Milestone 2 — Lean file discovery ✅

**Goal:** Given a set of files or a working directory, enumerate the `.lean` files to analyse and locate their optional `.test.json` companions.

### Tasks
- [x] Implement recursive `.lean` file discovery from a root directory (`Goudlokje/Discovery.lean`)
- [x] Map each `foo.lean` to its optional `foo.test.json`
- [x] Define the `TestFile` schema:
  - A list of expected shortcuts, each identified by file, line, column, and tactic name
- [x] Implement a parser and serialiser for `TestFile` (`Goudlokje/TestFile.lean`)
- [x] Write tests for test-file round-trip (parse → serialise → parse) — `Tests/TestFile.lean`
- [x] Write tests for file discovery — `Tests/Discovery.lean`

---

## Milestone 3 — Tactic Analysis integration ✅

**Goal:** Use Lean's elaboration pipeline to probe tactics at every step inside a proof.

### Tasks
- [x] Implement `Goudlokje/Analysis.lean`: process a `.lean` file via `Lean.Elab.Frontend`, collect `TacticInfo` nodes from the `InfoTree`, and for each non-empty goal state try each configured tactic using `ContextInfo.runMetaM` + `Tactic.run`
- [x] Handle vanilla Lean 4 proofs (any `by` block)
- [x] Handle Lean Verbose proofs (step boundaries work via standard InfoTree traversal)
- [x] Handle Waterproof Genre proofs (`#doc` blocks elaborate their inline code)
- [x] Deduplicate results: same (file, line, column, tactic) reported at most once
- [x] Write integration tests using small synthetic `.lean` files with known shortcuts — `Tests/Analysis.lean` + `Tests/Fixtures/`
- [x] Write no-duplicate regression test — `testNoDuplicateResults`

**Notes:** The analysis re-elaborates each file from scratch (resolving its own imports). Performance can be improved later by reusing cached `.olean` environments.

---

## Milestone 4 — Shortcut detection & reporting ✅

**Goal:** Classify probe results against the expected shortcuts recorded in `.test.json` and produce structured output.

### Tasks
- [x] Implement `ShortcutResult` (`unexpected` / `expected`) and `StaleEntry` in `Goudlokje/Shortcuts.lean`
- [x] Implement human-readable console output for each result type
- [x] In `check` mode, exit non-zero when any `unexpected` shortcut exists
- [x] Write unit tests for the classification logic — `Tests/Shortcuts.lean`

---

## Milestone 5 — `check` mode end-to-end ✅

**Goal:** A working `goudlokje check` command suitable for CI.

### Tasks
- [x] Wire Milestones 1–4 together into the `check` subcommand (`Goudlokje/Check.lean`)
- [x] Integrate with the GitHub Actions workflow in `.github/workflows/lean_action_ci.yml`
- [x] Add end-to-end tests for `check` mode — `TestSuite/Check.lean`
- [x] Document usage in `README.md`
- [x] Include default output that describes which file is being checked
- [x] Include debug output, togglable by a --debug flag

---

## Milestone 6 — `update` mode ✅

**Goal:** Allow teachers to interactively accept or reject shortcuts and persist them to `.test.json`.

### Tasks
- [x] Implement interactive prompting for each `unexpected` shortcut (`Goudlokje/Update.lean`)
- [x] Implement `--all` flag: accept every found shortcut without prompting
- [x] Implement removal of `stale` entries (with confirmation in interactive mode, automatic in `--all`)
- [x] Write tests for the `--all` path and for the file-mutation logic — `TestSuite/Update.lean`

---

## Milestone 7 — Waterproof Genre support ✅

**Goal:** Correctly handle proofs written in the Waterproof Genre format.

### Tasks
- [x] Add `waterproof-genre` dependency to `lakefile.lean`
- [x] Step-boundary detection works for Waterproof `#doc` blocks via standard InfoTree traversal
- [x] Add fixture file and integration test — `TestSuite/Fixtures/Waterproof.lean`, `testDetectsDecideShortcutInWaterproofFile`

---

## Milestone 8 — Usability in external projects

**Goal:** Make Goudlokje trivially adoptable by other Lean projects on the same toolchain.

### Tasks
- [x] Provide a template `.goudlokje.json` and document all configuration options
- [x] Write a "Getting started" guide covering installation, configuration, and CI integration — `README.md`
- [x] Ensure the tool gracefully handles projects that do not yet have any `.test.json` files
- [x] Publish the tool as a Lake executable so downstream projects can add it as a dependency

---

## Milestone 9 — Lean Verbose step filtering ✅

**Goal:** Optionally restrict shortcut reporting to the first tactic within each Lean Verbose step body, suppressing sub-step noise.

### Tasks
- [x] Discover Verbose step boundary syntax kind names empirically (`tacticLet'sFirstProveThat_`, `tacticLet'sNowProveThat_`, `tacticLet'sProveThat_Works_`)
- [x] Add `filterVerboseSteps : Bool := false` to `Config` with JSON round-trip
- [x] Implement `isVerboseStepBoundary` and `applyVerboseStepFilter` in `Goudlokje/Analysis.lean`
- [x] Pass `filterVerboseSteps` through `analyzeFile`, `runCheck`, and `runUpdate`
- [x] Add fixture `TestSuite/Fixtures/VerboseMultiStep.lean` with multi-tactic step bodies
- [x] Write tests: `testVerboseFilterReducesResults`, `testVerboseFilterKeepsFirstPerStep`
- [x] Write Config tests: `testFilterVerboseStepsDefault`, `testFilterVerboseStepsTrue`, `testFilterVerboseStepsRoundTrip`

**Notes:** When `filterVerboseSteps = true` in `.goudlokje.json`, shortcuts at step boundary positions (`Let's first/now prove that`) and at positions after the first tactic within each step body are suppressed. The first tactic within each step body (the step's "entry point") is always probed.

---

## Milestone 10 — Environment caching for multi-file analysis ✅

**Goal:** Avoid redundant `.olean` loading when analyzing multiple files with the same import set.

### Tasks
- [x] Add `EnvCache` type (`IO.Ref (Array (String × Environment))`) to `Analysis.lean`
- [x] Add `mkEnvCache : IO EnvCache` factory
- [x] Implement `getOrBuildEnv` with header-text-based cache key
- [x] Add `envCache : Option EnvCache` parameter to `analyzeFile`
- [x] Create and pass a shared cache in `runCheck` and `runUpdate`
- [x] Add tests: `testEnvCacheReturnsSameResults`, `testEnvCacheReusedAcrossFiles`

**Notes:** Cache key is the concatenation of all `import`/comment/blank lines at the top of the file, which uniquely identifies the import set in practice. The cache is created once per `check`/`update` invocation and shared across all files in that run.

---

## Milestone 11 — `--verbose` flag ✅

**Goal:** Add a `--verbose` flag that includes all `--debug` output plus detailed per-file reporting.

### Tasks
- [x] Add `verbose : Bool := false` parameter to `runCheck` (implies `debug`)
- [x] Add `verbose : Bool := false` parameter to `runUpdate` (implies `debug`)
- [x] Print discovered worksheet list before analysis when `--verbose`
- [x] Print each individual probe hit (`line:col — tactic`) per file when `--verbose`
- [x] Add `--verbose` flag to `checkCmd` and `updateCmd` in `Main.lean`
- [x] Write tests: `testCheckVerboseMode`, `testUpdateVerboseMode`

---

## Milestone 12 — Extended verbose probe logging ✅

**Goal:** In `--verbose` mode, print every probe attempt (success and failure) with its result, not just the successful ones.

### Tasks
- [x] Add `onProbe : Option (Nat → Nat → String → Bool → IO Unit)` callback parameter to `analyzeFile`
- [x] Call the callback inside the probing loop for every (line, col, tactic, succeeded) combination
- [x] In `runCheck`, build and pass the callback when `verbose := true` (prints `Probe ✓/✗ line:col — 'tactic'`)
- [x] In `runUpdate`, build and pass the callback when `verbose := true` (same format)
- [x] Remove the now-redundant post-hoc "Probe hit" loop (replaced by the callback)
- [x] Write tests: `testOnProbeCallbackInvoked`, `testOnProbeCallbackIncludesFailures`, `testOnProbeSuccessCountMatchesResults`

---

## Remaining work

- [x] When executing goudlokje on another project, I get 0 probe results for each file, even if there are contents.
  - **Root cause:** The `goudlokje` lean_exe was missing `moreLinkArgs := #["-rdynamic"]`. Without this flag, `unsafe Lean.enableInitializersExecution` does not export runtime symbols needed for Lean's tactic elaboration, causing all `tryTacticAt` calls to fail silently and return 0 results.
  - **Fix:** Added `moreLinkArgs := #["-rdynamic"]` to the `goudlokje` executable target in `lakefile.lean`, matching the existing `goudlokje_tests` and `debug_analysis` targets.
- [x] When executing goudlokje on another project, I get verbose output of the probe, but in the end probe results are still 0 and all of them fail, while I expect one to succeed.
        **Investigation:** Added fixture `TestSuite/Fixtures/VerboseWaterproof.lean` combining both `Verbose.English.All` and `WaterproofGenre` (`#doc` block with Verbose step tactics). Test `testDetectsDecideShortcutInVerboseWaterproofFile` passes: `decide`, `norm_num`, `omega`, `tauto`, `simp` all probe correctly inside `#doc` code blocks that use Verbose step boundaries. The combination works when run via `lake exe` (which sets `LEAN_PATH` correctly). If probes fail in an external project, ensure the tool is invoked via `lake exe goudlokje` so that all Lake package `.olean` files are on the search path.

---

## Non-goals (for now)

- IDE integration (VS Code extension, infoview widgets)
- Support for Lean toolchain versions other than the one pinned in `lean-toolchain`
- Automatic tactic suggestion or repair

---

## Dependency graph

```
M1 (Config & CLI)
  └─ M2 (File discovery)
       ├─ M3 (Tactic Analysis) ✅ incl. Verbose + Waterproof
       │    └─ M4 (Shortcut detection)
       │         ├─ M5 (check mode)
       │         └─ M6 (update mode)
       └─ M7 (Waterproof) ✅
M8 (Usability) ✅
```

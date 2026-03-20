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
- [ ] Publish the tool as a Lake executable so downstream projects can add it as a dependency

---

## Remaining work (priority order)

1. **Publish as Lake dependency** — allow downstream projects to `require "goudlokje"` in their lakefiles
2. **Lean Verbose step filtering** — optionally restrict shortcut reporting to positions that are *between* Verbose step boundaries, so sub-step noise can be suppressed
3. **Performance** — reuse cached `.olean` environments instead of re-elaborating from scratch

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
M8 (Usability) ← in progress
```

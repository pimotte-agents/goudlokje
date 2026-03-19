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
- [ ] Write unit tests for config parsing (valid config, missing fields, unknown fields)

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
- [ ] Write tests for file discovery and test-file round-trip (parse → serialise → parse)

---

## Milestone 3 — Tactic Analysis integration ✅ (skeleton)

**Goal:** Use Lean's elaboration pipeline to probe tactics at every step inside a proof.

### Tasks
- [x] Implement `Goudlokje/Analysis.lean`: process a `.lean` file via `Lean.Elab.Frontend`, collect `TacticInfo` nodes from the `InfoTree`, and for each non-empty goal state try each configured tactic using `ContextInfo.runMetaM` + `Tactic.run`
- [x] Handle vanilla Lean 4 proofs (any `by` block)
- [ ] Handle Lean Verbose proofs (step boundaries may differ)
- [ ] Handle Waterproof Genre proofs
- [ ] Write integration tests using small synthetic `.lean` files with known shortcuts

**Notes:** The analysis re-elaborates each file from scratch (resolving its own imports). Performance can be improved later by reusing cached `.olean` environments. Lean Verbose and Waterproof support is deferred to Milestones 3b and 7.

---

## Milestone 4 — Shortcut detection & reporting ✅

**Goal:** Classify probe results against the expected shortcuts recorded in `.test.json` and produce structured output.

### Tasks
- [x] Implement `ShortcutResult` (`unexpected` / `expected`) and `StaleEntry` in `Goudlokje/Shortcuts.lean`
- [x] Implement human-readable console output for each result type
- [x] In `check` mode, exit non-zero when any `unexpected` shortcut exists
- [ ] Write unit tests for the classification logic

---

## Milestone 5 — `check` mode end-to-end ✅ (skeleton)

**Goal:** A working `goudlokje check` command suitable for CI.

### Tasks
- [x] Wire Milestones 1–4 together into the `check` subcommand (`Goudlokje/Check.lean`)
- [ ] Integrate with the GitHub Actions workflow in `.github/workflows/lean_action_ci.yml`
- [ ] Add an end-to-end test that runs `check` on a fixture project and asserts exit code and output
- [ ] Document usage in `README.md`

---

## Milestone 6 — `update` mode ✅ (skeleton)

**Goal:** Allow teachers to interactively accept or reject shortcuts and persist them to `.test.json`.

### Tasks
- [x] Implement interactive prompting for each `unexpected` shortcut (`Goudlokje/Update.lean`)
- [x] Implement `--all` flag: accept every found shortcut without prompting
- [x] Implement removal of `stale` entries (with confirmation in interactive mode, automatic in `--all`)
- [ ] Write tests for the `--all` path and for the file-mutation logic

---

## Milestone 7 — Waterproof Genre support

**Goal:** Correctly handle proofs written in the Waterproof Genre format.

### Tasks
- [ ] Identify the Waterproof Genre dependency and add it to `lakefile.lean`
- [ ] Extend step-boundary detection to cover Waterproof-specific constructs
- [ ] Add fixture files and integration tests for Waterproof proofs
- [ ] Document any Waterproof-specific configuration in `README.md`

---

## Milestone 8 — Usability in external projects

**Goal:** Make Goudlokje trivially adoptable by other Lean projects on the same toolchain.

### Tasks
- [ ] Publish the tool as a Lake executable library so downstream projects can add it as a dependency
- [ ] Provide a template `.goudlokje.json` and document all configuration options
- [ ] Write a "Getting started" guide covering installation, configuration, and CI integration
- [ ] Ensure the tool gracefully handles projects that do not yet have any `.test.json` files

---

## Remaining work (priority order)

1. **Tests** — unit tests for Config parsing, TestFile round-trip, and Shortcuts classification
2. **Integration test** — fixture `.lean` file with known shortcuts; assert `check` exit code and output
3. **CI integration** — update `.github/workflows/lean_action_ci.yml` to run `goudlokje check`
4. **README** — document installation, `.goudlokje.json` format, and CI usage
5. **Lean Verbose support** — extend Analysis to handle Verbose step boundaries
6. **Waterproof Genre support** (Milestone 7)
7. **External project usability** (Milestone 8)

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
       ├─ M3 (Tactic Analysis)
       │    └─ M4 (Shortcut detection)
       │         ├─ M5 (check mode)
       │         └─ M6 (update mode)
       └─ M7 (Waterproof)  ← can proceed in parallel with M5/M6
M8 (Usability) ← after M5 + M6 + M7
```

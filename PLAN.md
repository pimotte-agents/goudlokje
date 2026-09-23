# Plan: remaining work (Phases 3–5)

Branch `feat/refactor-performance`. Design decisions, spike findings and the results of Phases 0–2
are recorded in [REFACTOR_PLAN.md](REFACTOR_PLAN.md). This file is the working plan for what is
left.

Done so far:

- Phase 0: baseline and spikes.
- Phase 1 (`418ca2b`): `Origin`, `Steps` (syntax-based steps, goal chains), `Scope` (input areas),
  `Expectations` (`.test.json` v2), `FileCache`, the `linter.goudlokje.explain` linter, and the
  `Tests` library (`lake test`).
- Phase 2 (`f41ac53`): `Probe`, `Report` and the shortcut linter.
- Phase 3: `Exercise`, `Finding`, `Checks/Shortcut`, `Checks/Lint` (B1–B3) and a single
  `goudlokjeLinter` (`Goudlokje/Linter.lean`), implemented as described below. On the old
  fixtures it reproduces every old B1/B2/B3 finding at the same position. It also flags
  `norm_num`, `rfl` and `ring` (B1), because nothing is allowed by default.

Invariant for every phase: `lake build` and `lake test` pass, and the old `goudlokje_tests` keep
passing until Phase 5 removes them.

---

## Phase 3: lint checks as linters

*Status: done. Deviations from the text below:* `Report` keeps only the low-level pieces
(`logFinding`, the results-file records); the comparison with expectations and the stale
reporting live in `Goudlokje/Linter.lean`. The checks are in `Goudlokje/Checks/` (not `Check/`,
which would clash with the old `Goudlokje/Check.lean`), with B1–B3 together in `Checks/Lint.lean`.
Issues reported twice because a step is nested inside another step are deduplicated.

### 3.1 Shared exercise context and a single linter

All checks need the same per-command data. Build it **once per command** instead of once per
linter:

- New `Goudlokje/Exercise.lean`:
  - `structure Exercise`: `stx` (the command), `name`, `steps : Array Step`, `first : Step`,
    `fileMap`, and `expectations : ExerciseExpectations`.
  - `Exercise.stepNumber`: the number of a step within the exercise. `Exercise.inInputArea`:
    whether a step is in a student input area.
  - `getExercise? (stx) : CommandElabM (Option Exercise)`. It returns `none` when:
    - the command has errors,
    - it has no steps,
    - it is not a Verbose proof (neither a Verbose command nor using any Verbose step), or
    - none of its steps is in an input area.

    It reports an unreadable `.test.json` once, as an error.
- New `Goudlokje/Linter.lean` (the `goudlokjeLinter`): calls `getExercise?` once, then runs each
  enabled check (`shortcut`, `rawTactic`, `typeAscription`, `sorry`). Each check is a
  `Exercise → CommandElabM (Array Finding)` in its own module under `Goudlokje/Check/`. The linter
  does the reporting, the comparison with expectations and the results-file output centrally, so
  the checks only find things.
- `Report`: a `Finding` gains a severity policy per check. It also gets a helper
  `reportFindings (exercise) (findings)` that
  1. logs unexpected findings (error or warning depending on the check),
  2. logs stale expectations (warning), and
  3. emits the results-file records.
- The shortcut linter from Phase 2 becomes `Goudlokje/Check/Shortcut.lean`, and its reporting moves
  into `reportFindings`. Behaviour is unchanged; `Tests/Shortcut.lean` must still pass unmodified.

### 3.2 B1: raw Lean tactics (`linter.goudlokje.rawTactic`)

- A finding is a step in the input area whose kind is **not** Verbose (`!isVerboseKind`), in an
  exercise that counts as a Verbose proof. `sorry` and `admit` steps are excluded (B3 handles them).
- It is found from syntax only, so macro expansions of Verbose tactics can never be flagged; the
  source-token heuristics are gone. The message names the tactic's first token, e.g.
  ``raw Lean tactic `exact` in a Verbose proof``.
- **Severity: error, and it cannot be suppressed.** A `rawTactic` entry in `.test.json` is itself
  reported as an error ("cannot be documented"), and `update` drops it.
- **Allowed tactics (decided on 2026-09-23):** every non-Verbose tactic is flagged, except those
  named in the option `goudlokje.allowedTactics`. The option is a `;;`-separated list of leading
  tokens, e.g. `"norm_num;; rfl"`, set per project in the lakefile. By default nothing is allowed.

### 3.3 B2: type annotations (`linter.goudlokje.typeAscription`)

- It is found from the syntax of the steps in the input area. There are two cases:
  1. **Type ascriptions** `(e : T)`: `Lean.Parser.Term.typeAscription` nodes with original source
     info inside a step. Binders have other syntax kinds, so a `(x : T)` binder is never matched,
     and synthesised nodes (the reason for the old `(`-character check) have no original info.
  2. **`Fix x : T`**: a Verbose `Fix` step (its parser comes from the `Verbose.*.Fix` module) whose
     binder has a type, i.e. its syntax contains a typed binder or a `:` atom. The `Fix` binder
     syntax is checked when implementing this; there is no source-line matching.
- **Severity: warning.** It is documented per exercise in `.test.json` as
  `"lint": [{ "check": "typeAscription", "step": n }]`. Documented entries that no longer occur are
  stale (warning).
- Regression fixtures: `LintB2` (must fire on `Fix n : ℕ` and on `(trivial : True)`) and
  `LintB2FalsePositive` (must report nothing).

### 3.4 B3: sorry (`linter.goudlokje.sorry`)

- A finding is a `sorry`/`admit` in a step in the input area: the kinds
  `Lean.Parser.Tactic.tacticSorry` and `Lean.Parser.Tactic.tacticAdmit`, and `Lean.Parser.Term.sorry`
  inside a step (e.g. `exact sorry`), found from syntax.
- **Deviation from the Phase 0 plan (S6):** we find sorries from syntax rather than from Lean's
  `hasSorry` warning, because `set_option warn.sorry false` (used in the fixtures) removes that
  warning, and the check would then silently pass. The syntax check is just as precise and cannot
  be turned off by accident.
- **Severity: error**, unless the exercise has `"allowSorry": true`. A stale `allowSorry` (no
  sorry left) is reported as a warning.

### 3.5 Tests

- `Tests/Lint.lean` (with `Tests/Lint.test.json`), using `#guard_msgs` and the comment-wrapped
  `:::input` markers:
  - B1: fires on `exact`/`constructor` in Verbose proofs; not on Verbose tactics (whose macro
    expansions contain `exact`, `refine` and the like); not in non-Verbose proofs; not on
    `sorry`. A documented B1 entry is an error.
  - B2: `Fix n : ℕ`, `(trivial : True)`, and none of the `LintB2FalsePositive` constructs; a
    documented entry is suppressed; a stale entry is a warning.
  - B3: `sorry` (tactic), `exact sorry`, `admit`; `allowSorry` suppresses them and is stale
    without a sorry; B3 still fires with `warn.sorry false`.
- Results-file records for lint findings (`check` is `rawTactic`, `typeAscription` or `sorry`).

---

## Phase 4: CLI (`goudlokje check`, `goudlokje update [--all]`)

Worksheets must be **modules of a `lean_lib`** in the worksheet project, and must import
`Goudlokje` (directly or through a prelude). Probe configuration moves from `.goudlokje.json` into
that library's `leanOptions`:

```lean
lean_lib Worksheets where
  leanOptions := #[⟨`weak.goudlokje.probes, "decide;; tauto;; norm_num"⟩]
```

### 4.1 Worksheet discovery

- From file and directory arguments (default: the current directory), find the `.lean` files.
- Map each file to its module and build artefacts. First choice: ask Lake (`lake query` / the
  module's `olean` facet). Fallback: the path relative to the library's source directory. Check
  the exact Lake v4.31 interface (`lake build <file>` support, `lake query` output) when
  implementing.

### 4.2 `check`

1. For every worksheet whose `.test.json` is **newer than its `.olean`**, delete the module's
   `.trace`, so Lake rebuilds exactly that module (Phase 2 result S4).
2. Run `lake build <worksheet modules>` and pass its output and exit code through. Unexpected
   shortcuts, B1 and B3 are errors, so the build (and CI) fails.
3. Plain `lake build` also works as the CI check. `check` only adds the `.test.json` freshness
   step.

### 4.3 `update [--all]`

1. Create a temporary results directory. Invalidate the target modules (delete their `.trace`), then
   run `lake build <modules>` with the environment variable `GOUDLOKJE_RESULTS_DIR` set.
   - **Change from Phase 2:** the linter writes to `$GOUDLOKJE_RESULTS_DIR/<module>.jsonl` when
     that variable is set, in addition to the `goudlokje.resultsFile` option. `lake env lean` would
     not apply the library's `leanOptions` (so no probes). Going through `lake build` uses exactly
     the project's options and Lake's parallelism.
   - The build may fail on findings (they are errors); that is expected, and `update` ignores the
     exit code.
2. **Skipped exercises must not lose their entries.** The linter emits a `{"skipped": name}` record
   for a command it cannot check (elaboration errors). `update` keeps the entries of skipped
   exercises and warns about them.
3. For each worksheet, compute the new `.test.json`:
   - Unexpected findings: accepted (`--all`) or prompted, except `rawTactic`, which is never
     accepted.
   - Stale entries (the exercise was checked and the finding is gone): removed (`--all`) or
     prompted.
   - Entries of exercises that were neither checked nor skipped (the exercise no longer exists):
     removed (`--all`) or prompted.
   - Write the file only if it changed. Delete it if it becomes empty.
4. Drop the `--debug`/`--verbose` flags; build output and `linter.goudlokje.explain` cover
   debugging.

### 4.4 Tests

- An end-to-end test (a Lean executable or a script run in CI) on a temporary copy of a small
  worksheet library (`Tests/Worksheets/…`, with `leanOptions` setting the probes):
  - `check` fails with unexpected shortcuts;
  - `update --all` writes the expected `.test.json`;
  - `check` then passes (this also exercises the "`.test.json` newer than `.olean`" rebuild);
  - removing an exercise makes `update --all` remove its entries.

---

## Phase 5: clean-up, documentation, benchmark

- **Delete the old implementation:** `Analysis`, `Lint`, `ProbeWorker`, `Check`, the old `Update`,
  `Shortcuts`, `TestFile`, `Config`, `DebugAnalysis`, the `debug_analysis` and `goudlokje_tests`
  executables, `.goudlokje.json`, and the `TestSuite/` tree (after porting whatever it covers
  that `Tests/` does not).
- **Port the fixtures:** move the useful `TestSuite/Fixtures` into the `Tests` worksheet library,
  fix the three that do not elaborate (`VerboseMultiDecl`, `VerboseWaterproofAssumeThatInBullet`,
  `Waterproof`), and generate their `.test.json` with `update --all`.
- **`FixtureDeps`:** only needed while the old tool loads imports at runtime; delete it.
- **`Goudlokje.lean`:** imports exactly the linters, so that `import Goudlokje` in a worksheet
  enables everything.
- **README:** setting up a worksheet project (a `require`, `import Goudlokje`, `leanOptions` for
  probes and budget), what each check reports, the probe semantics (goal chains, `goalBlocker`),
  the `.test.json` v2 format, `check`/`update`, editor behaviour, and CI (plain `lake build`, or
  `goudlokje check`).
- **CI workflow:** `lake build`, `lake test`, and the CLI end-to-end test.
- **Benchmark:** compare the final `lake build` of the fixtures, cold and warm, with the B0 baseline
  (30.1 s), and record the result in `REFACTOR_PLAN.md`.
- Remove `REFACTOR_PLAN.md`/`PLAN.md`, or move them to `docs/`, once the branch is ready for review.

---

## Decisions taken while planning

1. **B1 allowed tactics:** (a), the allow-list option `goudlokje.allowedTactics`, default empty
   (2026-09-23). The old list was inconsistent because of wrong kind names: `norm_num`, `rfl` and
   `trivial` were effectively allowed, while `exact`, `show` and `constructor` were flagged.

# Goudlokje refactor plan: linters instead of a custom frontend

Branch: `feat/refactor-performance`

## Goals

- Do the analysis inside the normal Lean elaboration (`lake build`, editor) as linters, instead of
  re-elaborating every file twice in subprocesses.
- Well engineered: one source of truth for tactic classification, syntax-based checks instead of
  source-text heuristics, pure and testable step extraction.
- Performant: one elaboration per file (parallel and cached by Lake), a heartbeat budget for each
  probe, and deduplication of identical goals.
- Keep `.test.json` support and `update [--all]`. File formats may change; no migration tool is
  needed (existing files are regenerated with `update --all`).

## Decisions (from Q&A)

| Topic | Decision |
|---|---|
| Activation | Worksheets `import Goudlokje` (directly or through a project prelude). Options go in the worksheet project's lakefile (`leanOptions`, `weak.` prefix). |
| Expected shortcuts | Compared **inside the linter**: the linter reads `<file>.test.json` and only reports unexpected findings, so plain `lake build` is the CI check. |
| Stale `.test.json` cache | The linter records the hash of the `.test.json` it read. `goudlokje check` wraps `lake build`, detects hash mismatches and forces a rebuild of just those modules. |
| `update` data flow | A results sink: `update` runs `lake env lean -Dgoudlokje.resultsFile=<tmp> <file>` for each file, in parallel. When that option is set, the linter writes every finding (expected ones included) as JSON lines. The CLI then prompts (or applies `--all`) and writes `.test.json`. |
| Scope | Unchanged: only `:::input` areas, and only proofs that contain Verbose tactics. |
| Sorry (B3) | Use Lean's own sorry detection instead of our TermInfo walk. Sorry is an error unless the exercise is marked as allowed to contain a sorry in `.test.json` (for "true or false" exercises whose statement is false). |
| Formats | Free to change. Probe configuration moves into Lean options where possible (see spike S2). |

## Target architecture

```
Goudlokje.lean                 -- import this in worksheets; registers all linters
Goudlokje/Options.lean         -- register_option for every setting (see below)
Goudlokje/TacticKinds.lean     -- ONE table: SyntaxNodeKind (Name, not String) → role
                               --   role ∈ {synthetic, stepBoundary, opaque, verboseUser, rawLean}
Goudlokje/Scope.lean           -- input areas (cached per file), "is Verbose proof", outer-#doc dedup
Goudlokje/Steps.lean           -- InfoTree → Array Exercise { name, steps : Array ProofStep }
                               --   Verbose step filter + skip-last, pure and Array-based
Goudlokje/Probe.lean           -- run a probe on a goal: runTacticCode + heartbeat budget,
                               --   Outcome = closed | open | failed | timeout, messages isolated,
                               --   per-command cache keyed on (goal fingerprint, probe)
Goudlokje/Expectations.lean    -- .test.json v2 schema, cached load keyed on (path, mtime) + hash
Goudlokje/Linter/Shortcut.lean -- linter.goudlokje.shortcut
Goudlokje/Linter/RawTactic.lean      -- B1, syntax-based (cannot be suppressed; logs an error)
Goudlokje/Linter/TypeAscription.lean -- B2, syntax-based (Fix binder types, original typeAscription)
Goudlokje/Linter/Sorry.lean          -- B3, built on Lean's sorry detection, suppressible per exercise
Goudlokje/Sink.lean            -- JSON-lines writer used when goudlokje.resultsFile is set
Main.lean + Goudlokje/Cli/*    -- `goudlokje check` (lake build + hash check), `goudlokje update [--all]`
```

The linter infrastructure reuses Mathlib's helpers (`Mathlib/Lean/ContextInfo.lean`:
`runTacticCode`/`runTactic`, `InfoTree.foldInfo`/`visitM`, `whenLinterActivated`). We write our
own `Linter` instead of registering a TacticAnalysis pass, because a pass only sees one tactic
sequence at a time. It can't see the Verbose step boundaries inside a flat sequence, or the
`Exercise` name, which comes from the command's syntax. TacticAnalysis is also on by default and
brings passes such as `introMerge` that are on by default too.

### Options (`register_option`, set via the lakefile as `weak.…`)

- `linter.goudlokje.shortcut`, `linter.goudlokje.rawTactic`, `linter.goudlokje.typeAscription`,
  `linter.goudlokje.sorry`: Bool, turn each check on or off.
- `goudlokje.probes`: String, the probe tactics separated by `;;` (it is parsed once per command,
  as `tacticSeq`s).
- `goudlokje.probeHeartbeats`: Nat, the budget for each probe (a timeout counts as "not a shortcut"
  and can be reported under `verbose`).
- `goudlokje.resultsFile`: String, the JSON-lines sink; empty means off. Only the CLI sets it.

### `.test.json` v2 (keyed per exercise, robust to edits elsewhere in the file)

```json
{
  "testJsonVersion": 2,
  "exercises": {
    "ex-name": {
      "shortcuts": [{ "step": 2, "tactic": "decide" }],
      "lint": [{ "check": "typeAscription", "step": 3 }],
      "allowSorry": true
    }
  }
}
```

Stale entries: the linter reports stale shortcuts and lints for every exercise it elaborates.
Entries for exercises that no longer exist are found and removed by `update`.

### What gets removed

- `Analysis.lean`'s own frontend loop (`processCommandsCollectTrees`, `analyzeInput`), `ProbeWorker.lean` (subprocess isolation),
  `EnvCache`, `findExerciseName` (source-text scanning), and the four duplicated kind lists.
- The source-text heuristics in `Lint.lean` (`isSorryLine`, `extractTacticToken`, the `Fix x : T` line
  matching, the `(` character check).
- `DebugAnalysis.lean`. It is replaced by a `#goudlokje_explain` command that prints the step
  classification of the following declaration.
- Most of the hand-written orchestration in `TestSuite/Main.lean`. Linter tests become fixture modules with
  `#guard_msgs`, built by `lake build TestSuite` / `lake test`. The CLI keeps a small end-to-end test.

## Phases

**Phase 0: baseline and spikes (do first; each can change the design)**

- B0: record baseline timings and peak memory for `goudlokje check TestSuite/Fixtures` and the test suite.
- S1: a minimal linter fires once for each Verbose `Exercise` and for each inner command of a Waterproof
  `#doc` block, with correct positions. Confirm how to skip the outer `addBlockCmd`, which otherwise
  shows the same tactics a second time.
- S2: do lakefile `leanOptions` reach commands inside `#doc` blocks? The research says `config.fresh`
  resets scopes, which would drop them. If they don't, fall back to reading probes from
  `.goudlokje.json` (cached, and covered by the same hash-check mechanism).
- S3: is `maxHeartbeats` enforced inside `runTacticCode`? The research suggests it silently uses
  200000. Settle on a reliable way to budget each probe.
- S4: the hash-check mechanism. Where the linter records the `.test.json` hash so that it can be
  read after a cached build (the persisted lint log in the `.olean` vs. a message). How to force a
  rebuild of a single module (e.g. invalidate its `.trace`).
- S5: `lake env lean -D goudlokje.resultsFile=…` on a module that imports Goudlokje (the `weak.`/unknown
  option handling).
- S6: can Lean's sorry detection be attributed to an exercise and escalated selectively? Options
  include the command's message log, `Declaration.hasSorry`, and the sorry warning's kind.

**Phase 1: core, pure pieces.** `TacticKinds`, `Scope`, `Steps` and `Expectations`, with unit tests.
The `Steps` output must match the current `dumpFilterStages` on every fixture; this is the regression
oracle.

**Phase 2: shortcut linter.** Probe runner (budget, fingerprint cache, message isolation), in-linter
classification against `.test.json`, stale reporting, and the sink. Probe positions and results must
match the current tool on all fixtures.

**Phase 3: lint linters.** B1, B2 and B3 rebuilt on syntax, with `#guard_msgs` fixtures
(including the known false-positive fixture `LintB2FalsePositive`).

**Phase 4: CLI.** Map discovery to modules, `check` = `lake build <mods>` plus the hash check, and
`update [--all]` via the sink with bounded parallelism.

**Phase 5: clean-up.** Delete the old code, migrate the tests, update the README (how to set up a worksheet
project) and CI, and regenerate the fixture `.test.json` files. Compare timings with B0.

Each phase is a reviewable PR (or commit series) on this branch, and `lake build && lake test` stays
green throughout.

## Phase 0 results (2026-09-23)

**B0 baseline** (19 fixtures in `TestSuite/Fixtures`, 16 cores):
- Current `lake exe goudlokje check TestSuite/Fixtures`: **30.1 s** wall.
- Plain elaboration of the same files, which is the floor for a linter design: 21.7 s sequential,
  **4.7 s with 8 parallel jobs**.

**Spike findings.** The throwaway linter is kept outside the repo; every point below was verified
by running it.
- **S1, confirmed.** The linter fires once for each Verbose `Exercise` command. Its info tree holds
  the whole proof, source positions are correct, and the exercise name is in the command syntax. In
  `#doc` files it fires for each inner command of a code block, and a **second time** on the outer
  `Verso.Doc.Concrete.addBlockCmd`/`addLastBlockCmd` with the same tactic nodes. We skip those
  command kinds.
- **S2, confirmed.** Lakefile `leanOptions` (with the `weak.` prefix) reach commands inside `#doc`
  blocks, because Verso's `fresh` flag defaults to false. Probe config can therefore live in Lean
  options, and `.goudlokje.json` goes away.
- **S3, confirmed.** Mathlib's `runCoreMWithMessages` builds a `Core.Context` whose `maxHeartbeats`
  comes from empty options, so the default 200000 always applies. Our runner does
  `Core.withCurrHeartbeats` + `withTheReader Core.Context ({· with maxHeartbeats := b*1000})` +
  `tryCatchRuntimeEx`, with `Exception.isMaxHeartbeat` meaning timeout. An infinitely looping probe
  stops after about 5–10 ms at 200k. Probe messages must be saved and restored explicitly.
- **S4, confirmed.** Linter output recorded with `logLint` is persisted in the `.olean`, in the
  `Lean.Linter.lintLogExt` entries, and `readModuleData` reads them in about 1 ms without importing
  the module. Deleting `<build>/lib/lean/<Mod>.trace` makes `lake build` rebuild exactly that module
  and replay the rest. This relies on Lake internals, but it is simple.
- **S5, confirmed.** `lake env lean -Dgoudlokje.resultsFile=… File.lean` works for an option
  declared in an imported module, with or without the `weak.` prefix. It takes about 1 s per fixture.
- **S6, confirmed.** Lean's sorry warning has message kind `hasSorry`. The linter sees it for the
  command that produced it through `messages.reportedPlusUnreported`, even under async elaboration.
  B3 becomes: the exercise command has a `hasSorry` message and is not `allowSorry` → `logError`.

**Other observations**
- After a Verbose step boundary, the steps inside the step have `goalsBefore.length = 2`, because
  the remaining conjunct stays open. The current tool probes **every** goal in `goalsBefore`, so it
  also probes the pending conjunct at every step. The new design probes only the main goal,
  `goalsBefore.head`. This is a deliberate change in behaviour: fewer, more meaningful probes. It
  needs confirmation.
- Probes are cheap compared with elaboration: 0–2 ms each for `decide` and `norm_num` on the
  fixtures.

## Phase 1 results

- **No kind lists.** `Goudlokje/Origin.lean` classifies a syntax kind by the module that declares
  its parser, so "Verbose tactic" means the parser lives in `Verbose.*`. The planned
  `TacticKinds.lean` table is not needed.
- **Steps come from syntax.** `Goudlokje/Steps.lean` defines a step as an item of a source-level
  tactic sequence, matched to the outermost `TacticInfo` with the same range and kind. Wrappers,
  macro internals and `·`/`case`/`next` focusing never become steps. The only kind list left is
  those three focusing kinds.
- **Probe semantics (decided with the user).** A step is a probe point when it does not close its
  main goal (`closesMainGoal`: every goal left afterwards was already open, apart from the main
  goal). Probe points are grouped into **goal chains**: a step joins the chain of the step whose
  successor goal it works on. Only the first successful probe in a chain is reported, and probing
  a chain stops at that first success. Only the main goal is probed. Step boundaries such as
  `Let's first prove that` are probe points too (a probe there may close the whole exercise).
- **Oracle comparison.** Every old probe position that is still a probe point is found. Two old
  positions drop out on purpose: `LintB2:26` (a closing `trivial`, picked by the old tool because
  it merged two anonymous `example`s) and `LintB3:24` (a closing `sorry`).
- **Broken fixtures.** Three old fixtures do not elaborate (`VerboseMultiDecl`: an `Exercise`
  without `Assume:`; `VerboseWaterproofAssumeThatInBullet`: a missing `QED`; `Waterproof`:
  `norm_num` without importing Mathlib). They are to be fixed during the test migration.
- **Other pieces.** `Scope.lean` (input areas), `Expectations.lean` (`.test.json` v2) and
  `FileCache.lean` (a cache keyed on path and modification time, so the editor sees changes).
  `linter.goudlokje.explain` reports steps, step numbers and chains, replacing `DebugAnalysis`.
- **Tests.** The new tests live in the `Tests` library (`@[test_driver]`, run with `lake test`) and
  use `#guard_msgs`/`#guard`.

## Risks

- `#doc` option propagation (S2) and the double linting there (S1) are the main unknowns.
- Performance now depends on the probes running inside the build. Without a budget, a looping probe
  makes `lake build` hang, so S3 must be settled before Phase 2.
- Worksheets must be modules of a `lean_lib` in the worksheet project for `lake build` to check them.
  This must be documented as a setup requirement.
- A file that fails to elaborate gets no linter results; that is correct, since the build fails anyway.

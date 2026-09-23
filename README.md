# Goudlokje

Goudlokje helps teachers keep Lean worksheets with reference solutions *just right*: not
incorrect, and not too easy. It checks exercises written with
[Lean Verbose](https://github.com/PatrickMassot/verbose-lean4), in
[Waterproof](https://github.com/impermeable/waterproof-genre) worksheets:

| Check            | Reports                                                                                   | Severity |
|------------------|-------------------------------------------------------------------------------------------|----------|
| `shortcut`       | a *probe* tactic (e.g. `decide`) closes a goal before the end of the proof, so the exercise can be shortcut | error    |
| `rawTactic`      | a raw Lean tactic (e.g. `exact`) instead of a Verbose tactic                              | error    |
| `typeAscription` | a type annotation, `(e : T)` or `Fix x : T`                                               | warning  |
| `sorry`          | a `sorry` or `admit`                                                                      | error    |

The checks are Lean linters: they run while Lean elaborates the worksheet, during `lake build`
and in the editor. Only exercises written with Verbose (a Verbose `Exercise`/`Example`, or a
proof using Verbose tactics) are checked, and only in student input areas (between `:::input` and
`:::`).

Findings that are intended, for example a shortcut the reference solution cannot avoid, are
recorded per worksheet in a `.test.json` file and are then no longer reported.

---

## Setting up a worksheet project

Goudlokje requires the Lean toolchain in `lean-toolchain`; your project must use the same one.

1. Add Goudlokje as a dependency in `lakefile.lean`:

   ```lean
   require "goudlokje" from git "https://github.com/pimotte/goudlokje" @ "main"
   ```

2. Make the worksheets modules of a library and configure the checks through its options. The
   `weak.` prefix keeps modules that do not import Goudlokje from rejecting the options.

   ```lean
   lean_lib Worksheets where
     leanOptions := #[
       ⟨`weak.goudlokje.probes, "decide;; tauto;; omega;; norm_num;; simp"⟩,
       ⟨`weak.goudlokje.allowedTactics, "norm_num"⟩
     ]
   ```

3. Import Goudlokje in every worksheet (or in a module that all worksheets import):

   ```lean
   import Goudlokje
   import Verbose.English.All
   import WaterproofGenre
   ```

Then `lake build` checks the worksheets, and the editor shows the findings.

### Options

| Option                                   | Default | Meaning                                                                                      |
|------------------------------------------|---------|----------------------------------------------------------------------------------------------|
| `goudlokje.probes`                       | `""`    | Probe tactics, separated by `;;`. Without probes, the `shortcut` check does not run.         |
| `goudlokje.probeHeartbeats`              | `100`   | Heartbeat budget per probe, in thousands (like `maxHeartbeats`). A probe that runs out is not a shortcut. |
| `goudlokje.allowedTactics`               | `""`    | Raw Lean tactics allowed in Verbose proofs, as leading tokens separated by `;;`, e.g. `"norm_num;; rfl"`. |
| `linter.goudlokje.shortcut`, `.rawTactic`, `.typeAscription`, `.sorry` | `true` | Turn a check on or off.                 |
| `linter.goudlokje.explain`               | `false` | Debugging aid: shows the steps Goudlokje finds in each command and how it groups them.       |

Like any option, they can also be set in a file (`set_option … in` for a single exercise).

---

## Shortcuts

A *step* is a tactic in the proof as the student writes it. Goudlokje tries the probe tactics on
the goal of every step that does not itself close that goal: at a step that does, the student has
to write a step anyway, so a probe there saves nothing. In particular, the last step of a proof is
never a shortcut, and a one-step proof has none.

Steps that work on the same goal (for example `Let's now prove that P`, then `show P`, then the
step that proves it) form a *chain*. Per chain only the first step where some probe closes the
goal is reported, with every probe that closes it there.

Lean Verbose blocks the remaining goals until the student starts on them (`Let's now prove
that …`), so most probes cannot close them earlier. `tauto` can see through the block and may
report a shortcut at `Let's now prove that`.

---

## Expected findings: `.test.json`

Each worksheet `Sheet.lean` may have a `Sheet.test.json`, listing per exercise what is expected:

```json
{
  "exercises": {
    "1.1.13": {
      "allowSorry": true,
      "lint": [
        {"check":"typeAscription","step":3}
      ],
      "shortcuts": [
        {"step":1,"tactic":"decide"}
      ]
    }
  },
  "testJsonVersion": 2
}
```

- **Exercises** are identified by the title of a Verbose `Exercise`/`Example`, the name of a
  theorem, or the statement of an anonymous `example` (such as `"example : 1 + 1 = 2"`).
- **Steps** are numbered by line relative to the first step of the exercise, so they stay valid
  when other parts of the file change.
- **`allowSorry`** allows `sorry` in an exercise, e.g. in a true-or-false exercise whose statement
  is false.
- **`rawTactic` findings cannot be recorded.** Allow a tactic for the whole project with
  `goudlokje.allowedTactics` instead.

Expectations that no longer occur are reported as stale (warning). Rather than editing the file by
hand, use `goudlokje update`.

---

## The `goudlokje` command

Run it in the worksheet project with `lake exe goudlokje`. Both commands take worksheets or
directories (default: the current directory).

- **`goudlokje check [paths…]`** builds the worksheets and fails if something unexpected is found.
  This is `lake build` plus one thing: Lake does not notice a changed `.test.json`, so `check`
  rebuilds worksheets whose `.test.json` is newer than their build. (It does not notice a
  *deleted* `.test.json`; rebuild the worksheet or run `update` after deleting one.)
- **`goudlokje update [--all] [paths…]`** checks the worksheets again and updates their
  `.test.json`. It records new findings as expected and removes stale expectations, including
  those of exercises that no longer exist. It asks before each change; with `--all` it makes
  them all. Exercises that do not elaborate keep their expectations.

### CI

```yaml
- name: Check worksheets
  run: lake exe goudlokje check
```

A plain `lake build` of the worksheets is also a valid check, since unexpected findings are
errors.

---

## Development

```bash
lake build          # the linters and the goudlokje executable
lake test           # unit tests of the linters (the Tests library, #guard_msgs / #guard)
e2e/run.sh          # end-to-end tests of the commands, and a regression test of all findings
```

`e2e/run.sh` checks the fixtures in `e2e/fixtures` and compares everything found with
`e2e/fixtures/expected`. After an intended change of behaviour, run `e2e/run.sh --regenerate`
and review the diff.

Code overview (`Goudlokje/`):

| Module                      | Contents                                                                    |
|-----------------------------|-----------------------------------------------------------------------------|
| `Steps`, `Origin`           | proof steps from the syntax and info trees; Verbose or not, by the module that declares a tactic |
| `Scope`, `Exercise`         | input areas; the per-command context shared by the checks                   |
| `Probe`, `Checks/`          | running probes with a budget; the four checks                               |
| `Linter`, `Report`          | the linter: expectations, stale entries, messages, results for `update`     |
| `Expectations`              | the `.test.json` format                                                     |
| `Cli/`                      | the `check` and `update` commands                                           |

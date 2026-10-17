The Goudlokje project provides a tool for teachers to maintain worksheets of mathematical exercises in Lean and Lean Verbose.

The idea is that we have a worksheet with reference solutions. Lean checks that the reference solutions are correct, but for didactical reasons we also want to check that they are *just right*: written in the style students should use, and not too easy. An exercise is too easy if a tactic can complete it before the end of the proof; we call this a shortcut.

The checks are Lean linters, so they run whenever Lean elaborates a worksheet: during `lake build` and in the editor. They are:

- `shortcut`: a probe tactic (configured project-wide in `goudlokje.probes`) closes a goal before the end of the proof;
- `rawTactic`: a raw Lean tactic instead of a Verbose tactic;
- `typeAscription`: a type annotation in a proof step;
- `sorry`: a `sorry` or `admit`;
- `help`: the help tactic (`goudlokje.help`) gives no hint at a step, so a student who is stuck there gets no help.

Only exercises written with Lean Verbose are checked, and only in student input areas of Waterproof worksheets. Any worksheet can have an accompanying test file (`filename.lean` goes with `filename.test.json`) that records expected findings, such as a shortcut the reference solution cannot avoid; those are no longer reported.

The `goudlokje` command has two modes. `check` builds the worksheets and fails on anything unexpected, also when only a test file changed. `update` records new findings in the test files and removes stale ones; it asks before each change, and with `--all` it makes them all.

Teachers can record other ways to solve an exercise with `Alternative solution:`. The alternative is checked like the reference solution, and is removed together with it from the student version.

The tool should be easily usable in other Lean projects with the same toolchain version.

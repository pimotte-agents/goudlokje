# Goudlokje

A Lean 4 tool that helps teachers verify that worksheet exercises are neither incorrect nor trivially solvable.

It runs configurable tactics at every proof step in a worksheet and reports any **shortcuts** — places where a tactic closes a goal before the intended end of the proof. This lets you catch exercises that are accidentally too easy.

---

## How it works

1. You configure which tactics to probe in `.goudlokje.json`.
2. Goudlokje elaborates each `.lean` file and tries each probe tactic at every goal state.
3. Results are compared against a per-file `.test.json` that records *expected* shortcuts (e.g. in the reference solution itself).
4. Any *unexpected* shortcut causes `check` to exit non-zero, failing CI.

---

## Installation

Goudlokje is built with [Lake](https://github.com/leanprover/lake). Clone the repository and build the executable:

```bash
git clone https://github.com/pimotte/goudlokje
cd goudlokje
lake build goudlokje
```

The binary is placed in `.lake/build/bin/goudlokje`.

### Toolchain

Goudlokje is pinned to the Lean toolchain in `lean-toolchain`. Your project must use the same toolchain version.

---

## Configuration

Create a `.goudlokje.json` file at the root of your project:

```json
{
  "tactics": ["decide", "tauto", "omega"]
}
```

| Field     | Type            | Description                                              |
|-----------|-----------------|----------------------------------------------------------|
| `tactics` | array of string | Tactic expressions to probe at every goal in every proof |

If `.goudlokje.json` is absent, Goudlokje runs with no probe tactics (no shortcuts can be found).

---

## Usage

### `check` — validate worksheets (for CI)

```bash
# Check all .lean files in the current directory (recursively)
goudlokje check

# Check specific files or directories
goudlokje check Exercises/ Solutions/Sheet1.lean
```

Exits **0** if no unexpected shortcuts are found, **1** otherwise.

### `update` — record expected shortcuts

```bash
# Interactive: prompt for each found shortcut
goudlokje update Exercises/

# Non-interactive: accept all shortcuts without prompting
goudlokje update --all Exercises/
```

`update` reads existing `.test.json` files, shows new shortcuts and stale entries, and writes the updated file back to disk.

---

## Expected shortcuts (`.test.json`)

Each `.lean` file may have an accompanying `<filename>.test.json` that lists shortcuts which are *expected* (i.e. intentional or unavoidable). Goudlokje ignores these when running `check`.

Example `Sheet1.test.json`:

```json
{
  "expected": [
    { "file": "Sheet1.lean", "line": 12, "column": 4, "tactic": "decide" }
  ]
}
```

Use `goudlokje update --all` to generate these files automatically from found shortcuts.

---

## Running the test suite

```bash
lake exe goudlokje_tests
```

The test suite covers:
- Config parsing (`TestSuite/Config.lean`)
- TestFile round-trips (`TestSuite/TestFile.lean`)
- Shortcut classification (`TestSuite/Shortcuts.lean`)
- File discovery (`TestSuite/Discovery.lean`)
- Analysis integration with vanilla Lean, Lean Verbose, and Waterproof Genre fixtures (`TestSuite/Analysis.lean`)
- End-to-end `check` mode (`TestSuite/Check.lean`)
- End-to-end `update --all` mode (`TestSuite/Update.lean`)

---

## Supported proof styles

| Style              | Status |
|--------------------|--------|
| Vanilla Lean 4     | ✅     |
| Lean Verbose       | ✅     |
| Waterproof Genre   | ✅     |

---

## CI integration

Add a step to your GitHub Actions workflow:

```yaml
- name: Check for shortcuts
  run: |
    lake build goudlokje
    .lake/build/bin/goudlokje check
```

The step fails automatically if any unexpected shortcut is found.

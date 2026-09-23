#!/bin/sh
# End-to-end test of `goudlokje check` and `goudlokje update`, on a copy of the worksheets in this
# directory (library `E2EWorksheets` in the lakefile). Run from anywhere: `e2e/run.sh`.
set -eu
cd "$(dirname "$0")/.."
work=e2e/work/Worksheets
out=e2e/work/out.txt
fail() { echo "FAIL: $*"; cat "$out"; exit 1; }
goudlokje() { .lake/build/bin/goudlokje "$@" > "$out" 2>&1; }

lake build goudlokje
rm -rf e2e/work
mkdir -p "$work"
cp e2e/Sheet.lean "$work/Sheet.lean"

echo "check fails on unexpected findings"
goudlokje check "$work" && fail "check passed"
grep -q '`decide` closes the goal at step 1 of exercise "shortcut"' "$out" || fail "no shortcut"
grep -q '`sorry` at step 1 of exercise "true or false"' "$out" || fail "no sorry"

echo "update --all records them"
goudlokje update --all "$work" || fail "update failed"
diff -u e2e/Sheet.expected.json "$work/Sheet.test.json" || fail "unexpected .test.json"

echo "check passes, rechecking the worksheet since its .test.json changed"
goudlokje check "$work" || fail "check failed"

echo "check notices stale expectations after only .test.json changed"
cp e2e/Sheet.stale.json "$work/Sheet.test.json"
goudlokje check "$work" || fail "check failed"
grep -q 'expected shortcut `simp` at step 2 of exercise "shortcut" no longer occurs' "$out" ||
  fail "no stale warning"

echo "update --all removes stale expectations and removed exercises"
cp e2e/Sheet.stale.json "$work/Sheet.test.json"
grep -v 'Fix n : ℕ' e2e/Sheet.lean | sed 's/Exercise "annotation"/Exercise "renamed"/' > "$work/Sheet.lean"
goudlokje update --all "$work" || fail "update failed"
diff -u e2e/Sheet.updated.json "$work/Sheet.test.json" || fail "unexpected .test.json"

echo "PASS"

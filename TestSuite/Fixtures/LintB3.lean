-- Fixture for CheckB3 (sorry detection) tests.
-- Contains `sorry` in a proof body that CheckB3 should flag.
import Verbose.English.All

set_option linter.unusedTactic false
set_option warn.sorry false

-- A proof with `sorry`: CheckB3 should detect and report the sorry.
example : True := by
  sorry

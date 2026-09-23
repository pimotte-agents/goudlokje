import Goudlokje.Expectations

/-! Tests for reading and writing `.test.json` files. -/

open Goudlokje Lean

private def sample : Expectations := {
  exercises := ({} : Std.TreeMap String ExerciseExpectations compare)
    |>.insert "1.1.13" { shortcuts := #[{ step := 1, tactic := "decide" }], allowSorry := true }
    |>.insert "b" { lint := #[{ check := "typeAscription", step := 3 }] }
}

-- Round trip.
#guard match parseExpectations (toJson sample).compress with
  | .ok e => e.exercises.toList == sample.exercises.toList
  | .error _ => false

-- Absent fields take their defaults; unknown exercises have no expectations.
#guard match parseExpectations "{\"testJsonVersion\": 2, \"exercises\": {\"a\": {}}}" with
  | .ok e => e.get "a" == {} && e.get "missing" == {}
  | .error _ => false

-- Files without the current version are rejected, so old files are regenerated.
#guard (parseExpectations "{\"expected\": []}").isOk == false
#guard (parseExpectations "{\"testJsonVersion\": 1, \"exercises\": {}}").isOk == false

-- Empty fields are omitted when writing.
#guard (toJson ({ exercises := ({} : Std.TreeMap _ _ compare).insert "a" {} } : Expectations)).compress ==
  "{\"exercises\":{\"a\":{}},\"testJsonVersion\":2}"

-- Files are written with sorted keys, one per line.
#guard renderJson (toJson sample) == "{
  \"exercises\": {
    \"1.1.13\": {
      \"allowSorry\": true,
      \"shortcuts\": [
        {\"step\":1,\"tactic\":\"decide\"}
      ]
    },
    \"b\": {
      \"lint\": [
        {\"check\":\"typeAscription\",\"step\":3}
      ]
    }
  },
  \"testJsonVersion\": 2
}"

import Goudlokje.Report

/-! Tests for the results-file format. -/

open Goudlokje Lean

private def finding : Finding := {
  check := "shortcut", exercise := "1.1.13", step := 2, line := 20, column := 2
  tactic? := some "decide", message := "…", expected := false }

#guard (toJson (ResultRecord.exercise "1.1.13")).compress == "{\"exercise\":\"1.1.13\"}"

#guard (fromJson? (toJson (ResultRecord.finding finding))).toOption == some (ResultRecord.finding finding)
#guard (fromJson? (toJson (ResultRecord.exercise "a"))).toOption == some (ResultRecord.exercise "a")

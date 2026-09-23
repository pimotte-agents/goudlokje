import Lean.Linter.Init

/-!
# Options

All Goudlokje settings are Lean options. Set them per project in the lakefile, with the `weak.`
prefix so that modules that do not import Goudlokje accept them:

```lean
lean_lib Worksheets where
  leanOptions := #[⟨`weak.linter.goudlokje.explain, true⟩]
```
-/

namespace Goudlokje

register_option linter.goudlokje.explain : Bool := {
  defValue := false
  descr := "(Goudlokje) report the proof steps Goudlokje finds in each command, for debugging"
}

register_option linter.goudlokje.shortcut : Bool := {
  defValue := true
  descr := "(Goudlokje) report steps where a probe tactic (`goudlokje.probes`) closes the goal \
    before the end of the proof"
}

register_option goudlokje.probes : String := {
  defValue := ""
  descr := "(Goudlokje) the probe tactics, separated by `;;`, e.g. \"decide;; simp;; norm_num\""
}

register_option goudlokje.probeHeartbeats : Nat := {
  defValue := 100
  descr := "(Goudlokje) the heartbeat budget of a single probe, in thousands (like \
    `maxHeartbeats`); a probe that runs out does not count as a shortcut"
}

register_option goudlokje.resultsFile : String := {
  defValue := ""
  descr := "(Goudlokje) if set, all findings are appended to this file as JSON lines; \
    used by `goudlokje update`"
}

end Goudlokje

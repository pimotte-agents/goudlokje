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

end Goudlokje

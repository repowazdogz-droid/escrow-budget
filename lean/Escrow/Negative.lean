/-
  Escrow/Negative.lean — the two hostile-review defects preserved as TRUE negative theorems
  (not `sorry`, not `Fail`-encoded false statements). Each is a provable existential exhibiting a
  concrete counterexample.
-/
import Escrow.Safety
namespace Escrow

/-- Hostile-review finding #1: `WF ∧ Bound → Safety` is FALSE over ℤ once `InFlightNonneg` is
    dropped. Witness `sp=3, se=1, inf=-2, cap=2`: escrow ≥ 0 and `sp+se+inf = 2 ≤ cap`, yet
    `sp = 3 > 2`. So `InFlightNonneg` is a load-bearing hypothesis of `certificate_implies_safety`,
    not decoration. (Over the `Nat` protocol it holds automatically — which is why we prove there.) -/
theorem inflight_nonneg_is_necessary :
    ∃ sp se inf cap : Int, 0 ≤ se ∧ sp + se + inf ≤ cap ∧ ¬ sp ≤ cap :=
  ⟨3, 1, -2, 2, by omega, by omega, by omega⟩

/-- Hostile-review finding #2: the current-state-only invariant `Bound (A ≤ CAP)` is NOT inductive
    under an unconstrained crash "restore" (replace current escrow at a replica by its durable
    snapshot). Witness `cap=2, curEscrow=0, rest=0, durEscrow=3`: before restore `A = curEscrow +
    rest = 0 ≤ cap`, after restore `A = durEscrow + rest = 3 > cap`. So the crash model (Floor F2)
    must strengthen the invariant to constrain the durable state; the crash-free proof here does
    not cover it and does not claim to. -/
theorem restore_breaks_bound :
    ∃ cap curEscrow durEscrow rest : Nat,
      curEscrow + rest ≤ cap ∧ cap < durEscrow + rest :=
  ⟨2, 0, 3, 0, by omega, by omega⟩

end Escrow

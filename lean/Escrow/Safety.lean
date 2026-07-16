/-
  Escrow/Safety.lean — the certificate implies Safety.

  `certificate_implies_safety` is stated over `ℤ` on purpose: there ALL THREE hypotheses are
  load-bearing (drop `0 ≤ inf` and it is false — see Escrow/Negative.lean). `safety_of_inv` lifts
  it to the `Nat` protocol state, so `InFlightNonneg` is genuinely used on the protocol path too.
-/
import Escrow.Invariants
namespace Escrow

variable {R T : Type} [DecidableEq R] [DecidableEq T]

/-- Arithmetic core (over ℤ): `WF ∧ InFlightNonneg ∧ Bound → Safety`. All hypotheses required. -/
theorem certificate_implies_safety (sp se inf cap : Int)
    (hWF : 0 ≤ se) (hInFlightNonneg : 0 ≤ inf) (hBound : sp + se + inf ≤ cap) :
    sp ≤ cap := by
  omega

/-- Protocol safety from the certificate, via the arithmetic core (uses `InFlightNonneg`). -/
theorem safety_of_inv {rs : List R} {ts : List T} {cap : Nat} {s : State R T}
    (hwf : WF rs s) (hif : InFlightNonneg ts s) (hb : Bound cap rs ts s) : Safety cap rs s := by
  have hnat : sumSpent rs s + sumEscrow rs s + inflight ts s ≤ cap := by
    have h := hb; simp only [Bound, A] at h; omega
  have key := certificate_implies_safety
      (sumSpent rs s : Int) (sumEscrow rs s : Int) (inflight ts s : Int) (cap : Int)
      (Int.natCast_nonneg _) (Int.natCast_nonneg _) (by exact_mod_cast hnat)
  have : sumSpent rs s ≤ cap := by exact_mod_cast key
  simpa [Safety] using this

end Escrow

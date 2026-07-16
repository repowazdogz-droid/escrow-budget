/-
  Escrow/Reachability.lean — every reachable state is safe, for arbitrary finite replica/transfer
  sets and arbitrary non-negative amounts.

  `reachable_invariants` carries `DestOk ∧ Bound` by induction (WF/InFlightNonneg are free over
  `Nat`). `reachable_safe` is the headline theorem.
-/
import Escrow.Safety
namespace Escrow

variable {R T : Type} [DecidableEq R] [DecidableEq T]

/-- The inductive invariant along any execution: destinations valid and `A ≤ CAP`. -/
theorem reachable_invariants {rs : List R} {ts : List T} {g : R} {cap : Nat} {s : State R T}
    (hrn : rs.Nodup) (htn : ts.Nodup) (hg : g ∈ rs)
    (h : Reachable rs ts g cap s) : DestOk rs s ∧ Bound cap rs ts s := by
  induction h with
  | init =>
    refine ⟨genesis_destOk cap hg, ?_⟩
    have hA : A rs ts (genesis (T := T) g cap) = cap := genesis_A cap hg hrn
    simp only [Bound]; omega
  | step hp hs ih =>
    obtain ⟨hdo, hbd⟩ := ih
    refine ⟨destOk_preserved hdo hs, ?_⟩
    have hA := A_preserved hrn htn hdo hs
    simp only [Bound] at hbd ⊢; omega

/-- **Headline theorem**: reachable states never authorise more than CAP, for ANY finite replica
    set (`rs` Nodup, genesis `g ∈ rs`), any finite transfer-id set, any non-negative amounts, and
    any `CAP` (including 0). -/
theorem reachable_safe {rs : List R} {ts : List T} {g : R} {cap : Nat} {s : State R T}
    (hrn : rs.Nodup) (htn : ts.Nodup) (hg : g ∈ rs)
    (h : Reachable rs ts g cap s) : Safety cap rs s :=
  safety_of_inv (wf_all rs s) (inflightNonneg_all ts s)
    (reachable_invariants hrn htn hg h).2

end Escrow

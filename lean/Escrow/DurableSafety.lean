/-
  Escrow/DurableSafety.lean — the joint invariant implies CURRENT safety.
  Safety is about `cur.spent`; the durable bound is used only to survive `crash`.
-/
import Escrow.DurableInvariants
namespace Escrow

variable {R T : Type} [DecidableEq R] [DecidableEq T]

/-- Joint invariant ⇒ current authorised consumption ≤ CAP. -/
theorem durable_safety {rs : List R} {ts : List T} {cap : Nat} {d : DState R T}
    (hj : Jinv cap rs ts d) : Safety cap rs d.cur :=
  safety_of_inv (wf_all rs d.cur) (inflightNonneg_all ts d.cur) hj.1

end Escrow

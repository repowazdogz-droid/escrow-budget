/-
  Escrow/DurableReachability.lean — every reachable disciplined crash/recovery state is safe,
  for arbitrary finite replica/transfer sets and arbitrary non-negative amounts.
-/
import Escrow.DurableSafety
namespace Escrow

variable {R T : Type} [DecidableEq R] [DecidableEq T]

/-- The joint invariant holds along every disciplined crash/recovery execution. -/
theorem dreachable_Jinv {rs : List R} {ts : List T} {g : R} {cap : Nat} {d : DState R T}
    (hrn : rs.Nodup) (htn : ts.Nodup) (hg : g ∈ rs)
    (h : DReachable rs ts g cap d) : Jinv cap rs ts d := by
  induction h with
  | init => exact genesis_Jinv hg hrn
  | step hp hs ih => exact Jinv_preserved hrn htn hs ih

/-- **Headline crash-safety theorem**: for every state reachable from a valid genesis under the
    disciplined crash/recovery protocol (charge, write-ahead send, durable-dedup recv, duplicate
    receive/refusal, drop, persist, crash, no-op), current authorised consumption never exceeds
    CAP — for ANY finite `rs`/`ts` (Nodup), genesis `g ∈ rs`, any non-negative amounts, any CAP. -/
theorem durable_reachable_safe {rs : List R} {ts : List T} {g : R} {cap : Nat} {d : DState R T}
    (hrn : rs.Nodup) (htn : ts.Nodup) (hg : g ∈ rs)
    (h : DReachable rs ts g cap d) : Safety cap rs d.cur :=
  durable_safety (dreachable_Jinv hrn htn hg h)

end Escrow

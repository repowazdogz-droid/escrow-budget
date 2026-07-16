/-
  Escrow/DurableNegative.lean — the two Floor-D crash attacks as machine-checked counterexamples,
  showing WHY the durable clauses of the joint invariant are load-bearing. Each exhibits a concrete
  DURABLE state that violates `Bound dur` (`A dur > CAP`); since `crash` copies durable to current,
  such a state is exactly what would break current safety after a crash.

  These are TRUE theorems over the real definitions (fully proved, not failed tactic scripts).
-/
import Escrow.DurableReachability
import Escrow.Negative
namespace Escrow
namespace DurableNeg

abbrev R := Fin 2
abbrev T := Fin 1
def rs : List R := [0, 1]
def ts : List T := [0]

/-- Durable state after a LAZY-DEBIT send: transfer t0 (r0→r1, amount 1) is marked in-flight but
    the sender's DURABLE escrow was NOT debited (write-ahead skipped). r0 keeps its unit AND the
    transfer is in flight ⇒ `A dur = 2 > CAP = 1`. A crash would restore this to current. -/
def lazyDurable : State R T where
  escrow := fun r => if r = 0 then 1 else 0     -- r0 NOT debited
  spent  := fun _ => 0
  phase  := fun _ => Phase.inflight             -- transfer emitted / replayable
  amt    := fun _ => 1
  dest   := fun _ => 1

theorem lazy_debit_A : A rs ts lazyDurable = 2 := by rfl
theorem lazy_debit_breaks_durable_bound : ¬ Bound 1 rs ts lazyDurable := by
  simp only [Bound, lazy_debit_A]; omega

/-- Durable state after a VOLATILE-DEDUP receive: the credit persisted to r1's DURABLE escrow, but
    the durable transfer phase was NOT advanced to `received` (dedup evidence not durable). r1 holds
    the credited unit AND the transfer is still in flight ⇒ `A dur = 2 > CAP = 1`. After a crash the
    transfer replays and credits again. -/
def volatileDurable : State R T where
  escrow := fun r => if r = 1 then 1 else 0     -- r1 credited
  spent  := fun _ => 0
  phase  := fun _ => Phase.inflight             -- dedup NOT durably recorded
  amt    := fun _ => 1
  dest   := fun _ => 1

theorem volatile_dedup_A : A rs ts volatileDurable = 2 := by rfl
theorem volatile_dedup_breaks_durable_bound : ¬ Bound 1 rs ts volatileDurable := by
  simp only [Bound, volatile_dedup_A]; omega

end DurableNeg

/-- The Floor-F1 `restore_breaks_bound` (Escrow/Negative.lean) remains the reason a current-only
    invariant is inadequate; the durable bound above is precisely the added clause it demanded. -/
example : ∃ cap curEscrow durEscrow rest : Nat,
    curEscrow + rest ≤ cap ∧ cap < durEscrow + rest := restore_breaks_bound

end Escrow

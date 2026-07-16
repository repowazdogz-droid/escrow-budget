/-
  Escrow/DurableState.lean — joint volatile+durable state for the crash/recovery extension.

  ABSTRACT model of the DISCIPLINED Floor-D protocol (NOT a line-by-line refinement of
  spec/EscrowBudgetD.tla — see the correspondence table in SCOPE.md). A joint state pairs a
  volatile `cur` state with a durable checkpoint `dur`, each an ordinary Floor-F1 `State`.

  Recovery semantics made explicit (not hidden in constructors):
    * `Persist` copies the whole current state to durable  (dur := cur).
    * `Crash`   restores the whole current state from durable (cur := dur)  — models a
      simultaneous crash of all replicas; per-replica-independent crash is NOT covered (noted).
    * A transfer's replayability is carried by its `phase` (a dropped message keeps its right, so
      `Drop` is a no-op); duplicate delivery / retransmission after recovery is refused by the
      `recv` phase guard.

  The safety claim is about `cur.spent`. `dur` exists solely to bound what a crash can restore.
-/
import Escrow.Reachability
namespace Escrow

variable {R T : Type} [DecidableEq R] [DecidableEq T]

/-- Joint volatile + durable state. -/
structure DState (R T : Type) where
  cur : State R T      -- volatile / current
  dur : State R T      -- durable checkpoint

/-- The joint invariant (weakest attempted first): current AND durable authority bounded, and
    both have valid destinations. The DURABLE bound is the clause the hostile review showed was
    missing from the Floor-F1 current-only invariant. -/
def Jinv (cap : Nat) (rs : List R) (ts : List T) (d : DState R T) : Prop :=
  Bound cap rs ts d.cur ∧ Bound cap rs ts d.dur ∧ DestOk rs d.cur ∧ DestOk rs d.dur

/-- Genesis: current and durable both start at the Floor-F1 genesis. -/
def Dgenesis [DecidableEq R] (g : R) (cap : Nat) : DState R T :=
  { cur := genesis g cap, dur := genesis g cap }

end Escrow

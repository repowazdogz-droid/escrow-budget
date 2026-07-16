/-
  Escrow/State.lean — crash-free distributed escrow state and the safety quantities.

  Faithful to spec/EscrowBudgetC.tla (correct config), reduced to exactly what the safety
  argument needs. A transfer's lifecycle is a `Phase`; `InFlight` sums the amounts of transfers
  that are sent-but-not-yet-received (the `sentT \ recvd` set of the TLA model). Amounts are
  arbitrary `Nat` (including 0). `escrow`/`spent` are per-replica `Nat`, so `WF` and
  `InFlightNonneg` are provable outright — the Int negative control in Escrow/Negative.lean shows
  why they are nonetheless load-bearing in the general arithmetic.
-/
import Escrow.Basic
namespace Escrow

/-- Lifecycle of a transfer id. `inflight` == sent, not yet credited (in `sentT \ recvd`). -/
inductive Phase | unsent | inflight | received
deriving DecidableEq, Repr

structure State (R T : Type) where
  escrow : R → Nat        -- per-replica local spend rights
  spent  : R → Nat        -- per-replica consumed
  phase  : T → Phase      -- transfer lifecycle
  amt    : T → Nat        -- transfer amount (set at send)
  dest   : T → R          -- transfer destination (set at send)

variable {R T : Type}

/-- A transfer contributes its amount to InFlight exactly while it is in flight. -/
def contrib (s : State R T) (t : T) : Nat :=
  match s.phase t with
  | Phase.inflight => s.amt t
  | _              => 0

def inflight (ts : List T) (s : State R T) : Nat := sumOver ts (contrib s)
def sumEscrow (rs : List R) (s : State R T) : Nat := sumOver rs s.escrow
def sumSpent  (rs : List R) (s : State R T) : Nat := sumOver rs s.spent

/-- Total authority in circulation: A = Σspent + Σescrow + InFlight. -/
def A (rs : List R) (ts : List T) (s : State R T) : Nat :=
  sumEscrow rs s + sumSpent rs s + inflight ts s

/-- Well-formedness: no replica holds negative escrow (trivial over `Nat`; see Negative.lean). -/
def WF (rs : List R) (s : State R T) : Prop := ∀ r, r ∈ rs → 0 ≤ s.escrow r
/-- In-flight authority is non-negative (trivial over `Nat`; load-bearing over `Int`). -/
def InFlightNonneg (ts : List T) (s : State R T) : Prop := 0 ≤ inflight ts s
/-- The inductive safety certificate's bound: A ≤ CAP. -/
def Bound (cap : Nat) (rs : List R) (ts : List T) (s : State R T) : Prop := A rs ts s ≤ cap
/-- The safety property itself: authorised consumption never exceeds CAP. -/
def Safety (cap : Nat) (rs : List R) (s : State R T) : Prop := sumSpent rs s ≤ cap

/-- Genesis: the designated replica `g` holds all of CAP; nothing spent or in flight. -/
def genesis [DecidableEq R] (g : R) (cap : Nat) : State R T where
  escrow := fun r => if r = g then cap else 0
  spent  := fun _ => 0
  phase  := fun _ => Phase.unsent
  amt    := fun _ => 0
  dest   := fun _ => g

end Escrow

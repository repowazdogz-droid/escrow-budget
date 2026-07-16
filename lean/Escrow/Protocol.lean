/-
  Escrow/Protocol.lean — the crash-free transitions and reachability.

  Actions mirror EscrowBudgetC: charge, first send/debit, receive/credit, drop/loss, no-op.
  * drop/loss is a NO-OP on safety state: the TLA model keeps a dropped transfer's right in
    `sentT \ recvd` (permanently in flight), so `A` is unchanged. We mirror that exactly.
  * duplicate delivery and refusal are covered by `recv`'s `phase = inflight` guard (a received
    or unsent transfer cannot be (re-)credited) and by `noop`.
  No crash/recovery, no durable state — that is Floor F2.
-/
import Escrow.State
namespace Escrow

variable {R T : Type} [DecidableEq R] [DecidableEq T]

/-- One protocol transition. `rs`/`ts` are the (finite) replica and transfer rosters. -/
inductive Step (rs : List R) (ts : List T) : State R T → State R T → Prop
  | charge (s : State R T) (r : R) (a : Nat) (hr : r ∈ rs) (hle : a ≤ s.escrow r) :
      Step rs ts s
        { s with escrow := upd s.escrow r (s.escrow r - a),
                 spent  := upd s.spent  r (s.spent r + a) }
  | send (s : State R T) (i j : R) (t : T) (a : Nat)
         (hi : i ∈ rs) (hj : j ∈ rs) (ht : t ∈ ts)
         (hun : s.phase t = Phase.unsent) (hle : a ≤ s.escrow i) :
      Step rs ts s
        { s with escrow := upd s.escrow i (s.escrow i - a),
                 phase  := upd s.phase t Phase.inflight,
                 amt    := upd s.amt t a,
                 dest   := upd s.dest t j }
  | recv (s : State R T) (t : T) (ht : t ∈ ts) (hin : s.phase t = Phase.inflight) :
      Step rs ts s
        { s with escrow := upd s.escrow (s.dest t) (s.escrow (s.dest t) + s.amt t),
                 phase  := upd s.phase t Phase.received }
  | drop (s : State R T) : Step rs ts s s              -- loss: right stays in flight (A unchanged)
  | noop (s : State R T) : Step rs ts s s              -- refusal / duplicate delivery no-op

/-- Structural well-formedness: every transfer's destination is a real replica. -/
def DestOk (rs : List R) (s : State R T) : Prop := ∀ t, s.dest t ∈ rs

/-- Reachability from genesis. -/
inductive Reachable (rs : List R) (ts : List T) (g : R) (cap : Nat) : State R T → Prop
  | init : Reachable rs ts g cap (genesis g cap)
  | step {s s'} : Reachable rs ts g cap s → Step rs ts s s' → Reachable rs ts g cap s'

end Escrow

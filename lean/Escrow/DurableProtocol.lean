/-
  Escrow/DurableProtocol.lean — the disciplined crash/recovery transitions on the joint state.

  Each disciplined transition applies the SAME Floor-F1 delta the crash-free proof already analysed
  (so `A_preserved` can be reused per component):
    * charge  : current only (volatile until persisted).
    * send    : current AND durable are debited and marked in-flight — WRITE-AHEAD DEBIT is the
                durable update; dropping it is the lazy-debit attack.
    * recv    : current AND durable are credited and marked received — DURABLE RECEIVER DEDUP is
                the durable phase advance; dropping it is the volatile-dedup attack.
    * persist : dur := cur.        crash : cur := dur.        drop / noop : identity.
  The send/recv durable guards (`d.dur.phase t = ...`, `a ≤ d.dur.escrow i`) are explicit: the
  disciplined operator only emits/credits when the durable store can record it.
-/
import Escrow.DurableState
namespace Escrow

variable {R T : Type} [DecidableEq R] [DecidableEq T]

/-- One disciplined crash/recovery transition. -/
inductive DStep (rs : List R) (ts : List T) : DState R T → DState R T → Prop
  | charge (d : DState R T) (r : R) (a : Nat) (hr : r ∈ rs) (hle : a ≤ d.cur.escrow r) :
      DStep rs ts d
        { d with cur := { d.cur with escrow := upd d.cur.escrow r (d.cur.escrow r - a),
                                     spent  := upd d.cur.spent  r (d.cur.spent r + a) } }
  | send (d : DState R T) (i j : R) (t : T) (a : Nat)
         (hi : i ∈ rs) (hj : j ∈ rs) (ht : t ∈ ts)
         (hcun : d.cur.phase t = Phase.unsent) (hdun : d.dur.phase t = Phase.unsent)
         (hcle : a ≤ d.cur.escrow i) (hdle : a ≤ d.dur.escrow i) :
      DStep rs ts d
        { cur := { d.cur with escrow := upd d.cur.escrow i (d.cur.escrow i - a),
                              phase := upd d.cur.phase t Phase.inflight, amt := upd d.cur.amt t a,
                              dest := upd d.cur.dest t j },
          dur := { d.dur with escrow := upd d.dur.escrow i (d.dur.escrow i - a),
                              phase := upd d.dur.phase t Phase.inflight, amt := upd d.dur.amt t a,
                              dest := upd d.dur.dest t j } }
  | recv (d : DState R T) (t : T) (ht : t ∈ ts)
         (hcin : d.cur.phase t = Phase.inflight) (hdin : d.dur.phase t = Phase.inflight) :
      DStep rs ts d
        { cur := { d.cur with escrow := upd d.cur.escrow (d.cur.dest t)
                                          (d.cur.escrow (d.cur.dest t) + d.cur.amt t),
                              phase := upd d.cur.phase t Phase.received },
          dur := { d.dur with escrow := upd d.dur.escrow (d.dur.dest t)
                                          (d.dur.escrow (d.dur.dest t) + d.dur.amt t),
                              phase := upd d.dur.phase t Phase.received } }
  | persist (d : DState R T) : DStep rs ts d { cur := d.cur, dur := d.cur }
  | crash   (d : DState R T) : DStep rs ts d { cur := d.dur, dur := d.dur }
  | drop    (d : DState R T) : DStep rs ts d d
  | noop    (d : DState R T) : DStep rs ts d d

/-- Reachability from `Dgenesis`. -/
inductive DReachable (rs : List R) (ts : List T) (g : R) (cap : Nat) : DState R T → Prop
  | init : DReachable rs ts g cap (Dgenesis g cap)
  | step {d d'} : DReachable rs ts g cap d → DStep rs ts d d' → DReachable rs ts g cap d'

end Escrow

--------------------------- MODULE EscrowBudgetBad ---------------------------
(*
 * ADVERSARIAL / NEGATIVE model: identical to EscrowBudget EXCEPT the receive action
 * has NO deduplication. A duplicated transfer message therefore credits the destination
 * MORE THAN ONCE while only one unit was debited — breaking the conserved quantity, and
 * (after the excess is charged) the SAFETY property SumSpent <= CAP.
 *
 * Its purpose is to confirm the model + invariants actually CATCH a real bug: TLC must
 * report an invariant violation here. This guards against a vacuous "green" model.
 *)
EXTENDS Naturals, FiniteSets

CONSTANTS Replicas, CAP, Cids, Tids
ASSUME CAP \in Nat
ASSUME Replicas # {}

Messages == [to : Replicas, tid : Tids]

VARIABLES escrow, spent, net, applied, sentT, recvd
vars == <<escrow, spent, net, applied, sentT, recvd>>

RECURSIVE SumFn(_, _)
SumFn(f, S) == IF S = {} THEN 0
               ELSE LET r == CHOOSE x \in S : TRUE IN f[r] + SumFn(f, S \ {r})
SumEscrow == SumFn(escrow, Replicas)
SumSpent  == SumFn(spent, Replicas)
InFlight  == Cardinality(sentT \ recvd)
Genesis == CHOOSE r \in Replicas : TRUE

Init ==
  /\ escrow  = [r \in Replicas |-> IF r = Genesis THEN CAP ELSE 0]
  /\ spent   = [r \in Replicas |-> 0]
  /\ net = {} /\ applied = {} /\ sentT = {} /\ recvd = {}

Charge(r, cid) ==
  /\ cid \notin applied
  /\ escrow[r] >= 1
  /\ escrow'  = [escrow  EXCEPT ![r] = @ - 1]
  /\ spent'   = [spent   EXCEPT ![r] = @ + 1]
  /\ applied' = applied \cup {cid}
  /\ UNCHANGED <<net, sentT, recvd>>

SendXfer(i, j, t) ==
  /\ t \notin sentT
  /\ escrow[i] >= 1
  /\ escrow' = [escrow EXCEPT ![i] = @ - 1]
  /\ sentT'  = sentT \cup {t}
  /\ net'    = net \cup {[to |-> j, tid |-> t]}
  /\ UNCHANGED <<spent, applied, recvd>>

\* *** BUG: no `m.tid \notin recvd` guard and no update to `recvd`. Re-delivering the same
\* message credits again — duplicate delivery is NOT idempotent here. ***
RecvBad(m) ==
  /\ m \in net
  /\ escrow' = [escrow EXCEPT ![m.to] = @ + 1]
  /\ UNCHANGED <<spent, net, applied, sentT, recvd>>

Drop(m) == /\ m \in net /\ net' = net \ {m}
           /\ UNCHANGED <<escrow, spent, applied, sentT, recvd>>

Next ==
  \/ \E r \in Replicas, cid \in Cids : Charge(r, cid)
  \/ \E i, j \in Replicas, t \in Tids : SendXfer(i, j, t)
  \/ \E m \in net : RecvBad(m)
  \/ \E m \in net : Drop(m)

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ escrow \in [Replicas -> Nat] /\ spent \in [Replicas -> Nat]
  /\ net \in SUBSET Messages /\ applied \in SUBSET Cids
  /\ sentT \in SUBSET Tids /\ recvd \in SUBSET Tids
Conserved == SumSpent + SumEscrow + InFlight = CAP
Safety == SumSpent =< CAP
=============================================================================

--------------------------- MODULE EscrowBudgetC ---------------------------
(*
 * Floor C — distributed escrow with ARBITRARY non-negative amounts and realistic network
 * behaviour (reorder, duplicate delivery, loss), with sender- and receiver-side transfer
 * idempotency each toggled by a CONSTANT so their INDIVIDUAL necessity can be measured.
 *
 * Two invariants are tracked separately (they are NOT the same property):
 *
 *   SafetyLe   ==  SumSpent + SumEscrow + InFlight  <=  CAP     (the aggregate-cap theorem)
 *   Conserved  ==  SumSpent + SumEscrow + InFlight   =  CAP     (no budget lost to double-debit)
 *
 * where InFlight sums amtOf[t] over transfer ids debited-but-not-yet-credited (each id once).
 * Safety (SumSpent <= CAP) is a corollary of SafetyLe since SumEscrow, InFlight >= 0.
 *
 * FINDING under test (measured by the three configs):
 *   - RECEIVER-side transfer idempotency is NECESSARY for SafetyLe (double-credit CREATES
 *     budget -> over-authorisation).
 *   - SENDER-side transfer idempotency is UNNECESSARY for SafetyLe (a re-debit only DESTROYS
 *     budget -> the sum decreases). It is needed only for the stronger Conserved equality.
 *)
EXTENDS Naturals, FiniteSets

CONSTANTS Replicas, CAP, Cids, Tids, Amounts, SenderIdemp, ReceiverIdemp
ASSUME CAP \in Nat
ASSUME Replicas # {}
ASSUME Amounts \subseteq (Nat \ {0})
ASSUME SenderIdemp \in BOOLEAN /\ ReceiverIdemp \in BOOLEAN

Messages == [to : Replicas, tid : Tids]

VARIABLES escrow, spent, net, applied, sentT, recvd, amtOf
vars == <<escrow, spent, net, applied, sentT, recvd, amtOf>>

RECURSIVE SumFn(_, _)
SumFn(f, S) == IF S = {} THEN 0
               ELSE LET x == CHOOSE e \in S : TRUE IN f[x] + SumFn(f, S \ {x})
SumEscrow == SumFn(escrow, Replicas)
SumSpent  == SumFn(spent, Replicas)
InFlight  == SumFn(amtOf, sentT \ recvd)   \* amounts sent but not yet credited (each id once)
Genesis   == CHOOSE r \in Replicas : TRUE

Init ==
  /\ escrow = [r \in Replicas |-> IF r = Genesis THEN CAP ELSE 0]
  /\ spent  = [r \in Replicas |-> 0]
  /\ net = {} /\ applied = {} /\ sentT = {} /\ recvd = {}
  /\ amtOf = [t \in Tids |-> 0]

\* Charge an arbitrary amount at replica r from local escrow (idempotent per charge id).
Charge(r, cid, a) ==
  /\ cid \notin applied
  /\ a \in Amounts /\ a =< escrow[r]
  /\ escrow'  = [escrow  EXCEPT ![r] = @ - a]
  /\ spent'   = [spent   EXCEPT ![r] = @ + a]
  /\ applied' = applied \cup {cid}
  /\ UNCHANGED <<net, sentT, recvd, amtOf>>

\* First send of transfer id t: debit sender, record the amount, enqueue.
SendFirst(i, j, t, a) ==
  /\ t \notin sentT
  /\ a \in Amounts /\ a =< escrow[i]
  /\ escrow' = [escrow EXCEPT ![i] = @ - a]
  /\ sentT'  = sentT \cup {t}
  /\ amtOf'  = [amtOf EXCEPT ![t] = a]
  /\ net'    = net \cup {[to |-> j, tid |-> t]}
  /\ UNCHANGED <<spent, applied, recvd>>

\* Sender-side NON-idempotent retry: re-debits the same transfer amount. Enabled only when
\* sender idempotency is OFF. Over-approximated (any replica may re-debit), which is sound for
\* a safety check. Models "a retry that was not de-duplicated at the sender".
SendDup(i, t) ==
  /\ ~SenderIdemp
  /\ t \in sentT
  /\ amtOf[t] =< escrow[i]
  /\ escrow' = [escrow EXCEPT ![i] = @ - amtOf[t]]
  /\ UNCHANGED <<spent, net, applied, sentT, recvd, amtOf>>

\* Deliver a message. If receiver idempotency is ON, credit at most once per id; if OFF, a
\* retained message can be delivered again and RE-CREDITS (models receiver-side duplication).
Recv(m) ==
  /\ m \in net
  /\ (ReceiverIdemp => m.tid \notin recvd)
  /\ escrow' = [escrow EXCEPT ![m.to] = @ + amtOf[m.tid]]
  /\ recvd'  = recvd \cup {m.tid}
  /\ UNCHANGED <<spent, net, applied, sentT, amtOf>>

\* Message loss.
Drop(m) == /\ m \in net /\ net' = net \ {m}
           /\ UNCHANGED <<escrow, spent, applied, sentT, recvd, amtOf>>

Next ==
  \/ \E r \in Replicas, cid \in Cids, a \in Amounts : Charge(r, cid, a)
  \/ \E i, j \in Replicas, t \in Tids, a \in Amounts : SendFirst(i, j, t, a)
  \/ \E i \in Replicas, t \in Tids : SendDup(i, t)
  \/ \E m \in net : Recv(m)
  \/ \E m \in net : Drop(m)

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ escrow \in [Replicas -> Nat] /\ spent \in [Replicas -> Nat]
  /\ net \in SUBSET Messages /\ applied \in SUBSET Cids
  /\ sentT \in SUBSET Tids /\ recvd \in SUBSET Tids
  /\ amtOf \in [Tids -> Nat]

Safety    == SumSpent =< CAP
SafetyLe  == SumSpent + SumEscrow + InFlight =< CAP
Conserved == SumSpent + SumEscrow + InFlight =  CAP
=============================================================================

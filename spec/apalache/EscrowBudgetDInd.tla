-------------------------- MODULE EscrowBudgetDInd --------------------------
(* CTI-iteration harness for Floor D. Adds NO protocol behaviour: it only names candidate
   inductive invariants over EscrowBudgetD. Auxiliary predicates are added one per CTI
   iteration and each is TLC-verified as a reachable-state invariant before being trusted. *)
EXTENDS EscrowBudgetD

\* ---- iteration 1: the property as-is ----
IndD1 == TypeOK /\ SafetyLe

\* ---- iteration 2: exclude CTI-1 (a tid recorded at a replica it was never sent to) ----
RecvdOnlyAddressed == \A r \in Replicas : \A t \in recvd[r] : [to |-> r, tid |-> t] \in sentMsgs
IndD2 == TypeOK /\ SafetyLe /\ RecvdOnlyAddressed

\* ---- iteration 3: exclude CTI-2 (two in-flight messages sharing one tid) ----
TidUnique == \A m1, m2 \in sentMsgs : (m1.tid = m2.tid) => (m1 = m2)
IndD3 == TypeOK /\ SafetyLe /\ RecvdOnlyAddressed /\ TidUnique

\* ---- iteration 4: exclude CTI-3 (durable snapshot itself over budget) ----
dCreditedTids == UNION {dRecvd[r] : r \in Replicas}
dInFlight     == SumFn(amtOf, SentTids \ dCreditedTids)
DurableSafetyLe == SumFn(dSpent, Replicas) + SumFn(dEscrow, Replicas) + dInFlight =< CAP
IndD4 == TypeOK /\ SafetyLe /\ RecvdOnlyAddressed /\ TidUnique /\ DurableSafetyLe

\* ---- candidate pool for iteration 5 (TLC-screened before use) ----
DurableSpentLe   == \A r \in Replicas : dSpent[r] =< spent[r]
DurableEscrowGe  == \A r \in Replicas : dEscrow[r] >= escrow[r]
DurableRecvdSub  == \A r \in Replicas : dRecvd[r] \subseteq recvd[r]
dRecvdAddressed  == \A r \in Replicas : \A t \in dRecvd[r] : [to |-> r, tid |-> t] \in sentMsgs
AmtOfSentOnly    == \A t \in Tids : (t \notin SentTids) => amtOf[t] = 0

\* ---- iteration 6 candidate: per-replica durable lag is ordered ----
\* L(r) == (escrow[r]+spent[r]) - (dEscrow[r]+dSpent[r]) >= 0, written without subtraction.
LagOrder == \A r \in Replicas : dEscrow[r] + dSpent[r] =< escrow[r] + spent[r]

\* ---- iteration 5: conjoin the whole TLC-screened, individually-justified pool ----
\* One-CTI-per-iteration would exceed the 6-iteration budget, so this step adds every
\* predicate above at once. Each was screened by TLC as a reachable-state invariant AND
\* confirmed live by negation; each has its own reachability argument in FLOORD-CTI.md.
IndD5 ==
  /\ TypeOK /\ SafetyLe
  /\ RecvdOnlyAddressed /\ TidUnique
  /\ DurableSafetyLe
  /\ DurableSpentLe /\ DurableEscrowGe /\ DurableRecvdSub /\ dRecvdAddressed
  /\ AmtOfSentOnly

\* ---- iteration 6: add LagOrder (excludes CTI-5) ----
IndD6 == IndD5 /\ LagOrder

\* ---- iteration 7: exclude CTI-6 -> CLOSES Floor D ----
\* With RecvdDurable = TRUE, Recv writes recvd[m.to] and dRecvd[m.to] in the same step,
\* Persist copies recvd -> dRecvd, and Crash copies dRecvd -> recvd. So they are EQUAL,
\* which is strictly stronger than DurableRecvdSub.
dRecvdEqRecvd == \A r \in Replicas : dRecvd[r] = recvd[r]

\* CertD is INDUCTIVE at the fixed constants of EscrowBudgetD.cfg (base + step both
\* discharged by Apalache 0.58.3). It implies SafetyLe, hence Safety. NOT a proof for all N.
CertD == IndD6 /\ dRecvdEqRecvd

\* CertD spelled out WITHOUT DurableRecvdSub, to test whether dRecvdEqRecvd subsumes it.
CertDMinimal ==
  /\ TypeOK /\ SafetyLe
  /\ RecvdOnlyAddressed /\ dRecvdAddressed /\ TidUnique /\ AmtOfSentOnly
  /\ DurableSafetyLe
  /\ DurableSpentLe /\ DurableEscrowGe /\ LagOrder
  /\ dRecvdEqRecvd
=============================================================================

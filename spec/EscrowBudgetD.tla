--------------------------- MODULE EscrowBudgetD ---------------------------
(*
 * Floor D — crash / recovery / durable vs volatile state / partitions / retransmission.
 *
 * Each replica has DURABLE state (dEscrow, dSpent, dRecvd) and CURRENT (volatile) state
 * (escrow, spent, recvd). Persist(r) checkpoints current -> durable. Crash(r) reverts current
 * <- durable (all un-persisted work is lost). The network `sentMsgs` is monotonic and external
 * (a message, once emitted, is not un-sent by a crash), and Recv may fire on any sent message
 * any number of times — this single mechanism models reorder, duplication, loss, PARTITION
 * (delivery delayed arbitrarily), partition HEALING (delivered later), and RETRANSMISSION AFTER
 * RECOVERY (still deliverable after a crash).
 *
 * Two durability disciplines are toggled by CONSTANTS so their necessity is measured:
 *   DebitDurableBeforeSend : the sender persists the escrow debit atomically with emitting the
 *                            message (write-ahead). If FALSE, a crash after send reverts the
 *                            debit while the message survives in flight.
 *   RecvdDurable           : the receiver's dedup set survives a crash. If FALSE, a crash loses
 *                            recvd (while the credited balance is durable), so a retransmit
 *                            re-credits.
 *
 * HYPOTHESIS UNDER TEST (Floor C): "receiver-side faults are the only safety-critical faults",
 * and its structural form: "only budget-CREATING faults break safety; budget-DESTROYING faults
 * are safe." Floor D tries to refute both.
 *)
EXTENDS Naturals, FiniteSets

CONSTANTS Replicas, CAP, Tids, Amounts, DebitDurableBeforeSend, RecvdDurable
ASSUME CAP \in Nat /\ Replicas # {} /\ Amounts \subseteq (Nat \ {0})
ASSUME DebitDurableBeforeSend \in BOOLEAN /\ RecvdDurable \in BOOLEAN

Messages == [to : Replicas, tid : Tids]

VARIABLES escrow, spent, recvd, dEscrow, dSpent, dRecvd, sentMsgs, amtOf
vars == <<escrow, spent, recvd, dEscrow, dSpent, dRecvd, sentMsgs, amtOf>>

RECURSIVE SumFn(_, _)
SumFn(f, S) == IF S = {} THEN 0
               ELSE LET x == CHOOSE e \in S : TRUE IN f[x] + SumFn(f, S \ {x})

SentTids     == {m.tid : m \in sentMsgs}
CreditedTids == UNION {recvd[r] : r \in Replicas}
SumEscrow    == SumFn(escrow, Replicas)
SumSpent     == SumFn(spent, Replicas)
InFlight     == SumFn(amtOf, SentTids \ CreditedTids)   \* sent but not (currently) credited
Genesis      == CHOOSE r \in Replicas : TRUE

Init ==
  /\ escrow  = [r \in Replicas |-> IF r = Genesis THEN CAP ELSE 0]
  /\ spent   = [r \in Replicas |-> 0]
  /\ recvd   = [r \in Replicas |-> {}]
  /\ dEscrow = [r \in Replicas |-> IF r = Genesis THEN CAP ELSE 0]
  /\ dSpent  = [r \in Replicas |-> 0]
  /\ dRecvd  = [r \in Replicas |-> {}]
  /\ sentMsgs = {}
  /\ amtOf    = [t \in Tids |-> 0]

\* Local charge from current escrow (no charge id: charge idempotency is not safety-critical).
Charge(r, a) ==
  /\ a \in Amounts /\ a =< escrow[r]
  /\ escrow' = [escrow EXCEPT ![r] = @ - a]
  /\ spent'  = [spent  EXCEPT ![r] = @ + a]
  /\ UNCHANGED <<recvd, dEscrow, dSpent, dRecvd, sentMsgs, amtOf>>

\* Transfer: debit sender (current) and emit the message. Persist the debit iff disciplined.
SendXfer(i, j, t, a) ==
  /\ t \notin SentTids
  /\ a \in Amounts /\ a =< escrow[i]
  /\ escrow'   = [escrow EXCEPT ![i] = @ - a]
  /\ amtOf'    = [amtOf EXCEPT ![t] = a]
  /\ sentMsgs' = sentMsgs \cup {[to |-> j, tid |-> t]}
  /\ dEscrow'  = IF DebitDurableBeforeSend
                 THEN [dEscrow EXCEPT ![i] = escrow[i] - a]
                 ELSE dEscrow
  /\ UNCHANGED <<spent, recvd, dSpent, dRecvd>>

\* Receive: credit (current), record recvd (current), and durably record the new balance. Persist
\* recvd durably iff RecvdDurable. Guarded by current recvd, so a crash that loses recvd re-opens
\* the tid for a re-credit on retransmission.
Recv(m) ==
  /\ m \in sentMsgs
  /\ m.tid \notin recvd[m.to]
  /\ escrow'  = [escrow  EXCEPT ![m.to] = @ + amtOf[m.tid]]
  /\ recvd'   = [recvd   EXCEPT ![m.to] = @ \cup {m.tid}]
  /\ dEscrow' = [dEscrow EXCEPT ![m.to] = escrow[m.to] + amtOf[m.tid]]  \* balance is durable
  /\ dRecvd'  = IF RecvdDurable
                THEN [dRecvd EXCEPT ![m.to] = recvd[m.to] \cup {m.tid}]
                ELSE dRecvd
  /\ UNCHANGED <<spent, dSpent, sentMsgs, amtOf>>

\* Voluntary checkpoint (fsync).
Persist(r) ==
  /\ dEscrow' = [dEscrow EXCEPT ![r] = escrow[r]]
  /\ dSpent'  = [dSpent  EXCEPT ![r] = spent[r]]
  /\ dRecvd'  = IF RecvdDurable THEN [dRecvd EXCEPT ![r] = recvd[r]] ELSE dRecvd
  /\ UNCHANGED <<escrow, spent, recvd, sentMsgs, amtOf>>

\* Crash: lose all un-persisted (volatile) work; revert current <- durable. sentMsgs survives.
Crash(r) ==
  /\ escrow' = [escrow EXCEPT ![r] = dEscrow[r]]
  /\ spent'  = [spent  EXCEPT ![r] = dSpent[r]]
  /\ recvd'  = [recvd  EXCEPT ![r] = IF RecvdDurable THEN dRecvd[r] ELSE {}]
  /\ UNCHANGED <<dEscrow, dSpent, dRecvd, sentMsgs, amtOf>>

Next ==
  \/ \E r \in Replicas, a \in Amounts : Charge(r, a)
  \/ \E i, j \in Replicas, t \in Tids, a \in Amounts : SendXfer(i, j, t, a)
  \/ \E m \in sentMsgs : Recv(m)
  \/ \E r \in Replicas : Persist(r)
  \/ \E r \in Replicas : Crash(r)

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ escrow \in [Replicas -> Nat] /\ spent \in [Replicas -> Nat]
  /\ recvd \in [Replicas -> SUBSET Tids]
  /\ dEscrow \in [Replicas -> Nat] /\ dSpent \in [Replicas -> Nat]
  /\ dRecvd \in [Replicas -> SUBSET Tids]
  /\ sentMsgs \in SUBSET Messages /\ amtOf \in [Tids -> Nat]

Safety    == SumSpent =< CAP
SafetyLe  == SumSpent + SumEscrow + InFlight =< CAP
Conserved == SumSpent + SumEscrow + InFlight =  CAP

(* ----- inductive certificate -----
 * SafetyLe is TRUE on all 56 reachable states of EscrowBudgetD.cfg but is NOT INDUCTIVE on
 * its own. Closing it took SEVEN counterexample-to-induction rounds and NINE auxiliary
 * conjuncts; the full CTI sequence, each pre-state verbatim, and each reachability argument
 * are in FLOORD-CTI.md. For contrast, Floor A and Recovery each closed with ONE conjunct.
 * (Iteration produced ten conjuncts; DurableRecvdSub was then step-checked to be redundant
 * given dRecvdEqRecvd, leaving nine in CertDMinimal. Both forms are certified.)
 *
 * The reason Floor D is hard: its durable state is never a coherent snapshot of a past
 * state. Recv writes dEscrow eagerly (to the value escrow is simultaneously taking) but
 * never writes dSpent; Charge writes neither; Persist writes all three; Crash reads all
 * three. So the durable triple (dEscrow, dSpent, dRecvd) mixes components captured at
 * different moments, and the certificate has to pin the exact relationship between six
 * variables rather than name one conserved quantity.
 *
 * The nine conjuncts, grouped:
 *   well-formedness   RecvdOnlyAddressed, dRecvdAddressed, TidUnique, AmtOfSentOnly
 *   durable budget    DurableSafetyLe
 *   durable lag       DurableSpentLe, DurableEscrowGe, LagOrder
 *   durable dedup     dRecvdEqRecvd
 *
 * SCOPE: CertDMinimal (spec/apalache/EscrowBudgetDInd.tla) is certified INDUCTIVE by
 * Apalache at the FIXED CONSTANTS of EscrowBudgetD.cfg (Replicas = {r1, r2}, CAP = 2,
 * Tids = {t1}, Amounts = {1, 2}, DebitDurableBeforeSend = TRUE, RecvdDurable = TRUE).
 * Base, step, and CertDMinimal => SafetyLe are all discharged, so SafetyLe holds at
 * UNBOUNDED DEPTH for that instance. It is NOT a proof for all N.
 *
 * CONFIG-SPECIFIC: DurableEscrowGe needs DebitDurableBeforeSend = TRUE, and
 * DurableRecvdSub / dRecvdEqRecvd need RecvdDurable = TRUE. Under the fault configs those
 * are FALSE — correctly, since SafetyLe genuinely fails there. CertD must not be reused
 * across the fault matrix; `make apalache-inductive` runs both fault configs as negative
 * controls and requires the certificate to FAIL on each.
 *)
=============================================================================

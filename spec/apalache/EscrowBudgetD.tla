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
EXTENDS Naturals, FiniteSets, Apalache

CONSTANTS
  \* @type: Set(Str);
  Replicas,
  \* @type: Int;
  CAP,
  \* @type: Set(Str);
  Tids,
  \* @type: Set(Int);
  Amounts,
  \* @type: Bool;
  DebitDurableBeforeSend,
  \* @type: Bool;
  RecvdDurable,
  \* @type: Str;
  Genesis
ASSUME CAP \in Nat /\ Replicas # {} /\ Amounts \subseteq (Nat \ {0})
ASSUME DebitDurableBeforeSend \in BOOLEAN /\ RecvdDurable \in BOOLEAN

Messages == [to : Replicas, tid : Tids]

VARIABLES
  \* @type: Str -> Int;
  escrow,
  \* @type: Str -> Int;
  spent,
  \* @type: Str -> Set(Str);
  recvd,
  \* @type: Str -> Int;
  dEscrow,
  \* @type: Str -> Int;
  dSpent,
  \* @type: Str -> Set(Str);
  dRecvd,
  \* @type: Set({ to: Str, tid: Str });
  sentMsgs,
  \* @type: Str -> Int;
  amtOf
vars == <<escrow, spent, recvd, dEscrow, dSpent, dRecvd, sentMsgs, amtOf>>

\* @type: (Str -> Int, Set(Str)) => Int;
SumFn(f, S) == ApaFoldSet(LAMBDA acc, x : acc + f[x], 0, S)

SentTids     == {m.tid : m \in sentMsgs}
CreditedTids == UNION {recvd[r] : r \in Replicas}
SumEscrow    == SumFn(escrow, Replicas)
SumSpent     == SumFn(spent, Replicas)
InFlight     == SumFn(amtOf, SentTids \ CreditedTids)   \* sent but not (currently) credited
ASSUME Genesis \in Replicas

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
=============================================================================

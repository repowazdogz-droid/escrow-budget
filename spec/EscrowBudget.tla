---------------------------- MODULE EscrowBudget ----------------------------
(*
 * Floor A — minimal distributed model of an ESCROW BUDGET SERVICE.
 *
 * A fixed global cap CAP is partitioned into per-replica "escrow" (local spend rights).
 * Each replica may CHARGE against its own escrow with NO coordination, and may TRANSFER
 * escrow to another replica over an unreliable network (reorder / duplicate / loss).
 *
 * The load-bearing property is a CONSERVED QUANTITY:
 *
 *     SumSpent + SumEscrow + InFlight  =  CAP
 *
 * where InFlight is escrow that has left a sender but has not yet been credited at a
 * receiver. From this and non-negativity, the SAFETY theorem follows:
 *
 *     SumSpent  <=  CAP        (aggregate authorised consumption never exceeds the cap)
 *
 * This holds under message REORDERING (net is a set), DUPLICATE delivery (messages are
 * retained and receipt is idempotent via `recvd`), LOSS (Drop), and idempotent charge
 * RETRIES (via `applied`). No exactly-once delivery is assumed; duplicates and retries
 * are modelled explicitly.
 *
 * Minimal-model simplification (relaxed in a later floor): every charge and transfer
 * moves a UNIT (1) of budget, so InFlight is a count. Crash/recovery and partition are
 * added in Floors C/D; this floor establishes the protocol and the invariant.
 *)
EXTENDS Naturals, FiniteSets

CONSTANTS Replicas,  \* set of replica identifiers
          CAP,       \* global cap (a natural number)
          Cids,      \* finite set of charge-operation ids (for idempotent retry)
          Tids       \* finite set of transfer ids (for idempotent delivery / dedup)

ASSUME CAP \in Nat
ASSUME Replicas # {}

\* A transfer message in the network: which replica it credits, and its transfer id.
Messages == [to : Replicas, tid : Tids]

VARIABLES
  escrow,   \* [Replicas -> Nat]  local, uncoordinated spend rights
  spent,    \* [Replicas -> Nat]  consumption already authorised at each replica
  net,      \* SUBSET Messages    in-flight transfers (a SET: unordered => reorder)
  applied,  \* SUBSET Cids        charge ids already applied (idempotency)
  sentT,    \* SUBSET Tids        transfer ids debited from some sender
  recvd     \* SUBSET Tids        transfer ids already credited at their destination

vars == <<escrow, spent, net, applied, sentT, recvd>>

RECURSIVE SumFn(_, _)
SumFn(f, S) == IF S = {} THEN 0
               ELSE LET r == CHOOSE x \in S : TRUE IN f[r] + SumFn(f, S \ {r})

SumEscrow == SumFn(escrow, Replicas)
SumSpent  == SumFn(spent, Replicas)
\* Unit transfers that have been debited but not yet credited (includes lost ones).
InFlight  == Cardinality(sentT \ recvd)

\* The designated genesis replica initially holds the entire cap as escrow.
Genesis == CHOOSE r \in Replicas : TRUE

Init ==
  /\ escrow  = [r \in Replicas |-> IF r = Genesis THEN CAP ELSE 0]
  /\ spent   = [r \in Replicas |-> 0]
  /\ net     = {}
  /\ applied = {}
  /\ sentT   = {}
  /\ recvd   = {}

\* Charge one unit at replica r under charge id cid. Idempotent: a retry of the SAME cid
\* (duplicate request) is not re-applied. Requires local escrow >= 1 — NO coordination.
Charge(r, cid) ==
  /\ cid \notin applied
  /\ escrow[r] >= 1
  /\ escrow'  = [escrow  EXCEPT ![r] = @ - 1]
  /\ spent'   = [spent   EXCEPT ![r] = @ + 1]
  /\ applied' = applied \cup {cid}
  /\ UNCHANGED <<net, sentT, recvd>>

\* Replica i sends a unit of escrow to replica j with a fresh transfer id t.
\* The unit leaves i's escrow immediately and becomes in-flight.
SendXfer(i, j, t) ==
  /\ t \notin sentT
  /\ escrow[i] >= 1
  /\ escrow' = [escrow EXCEPT ![i] = @ - 1]
  /\ sentT'  = sentT \cup {t}
  /\ net'    = net \cup {[to |-> j, tid |-> t]}
  /\ UNCHANGED <<spent, applied, recvd>>

\* Deliver a transfer message. Idempotent: crediting happens once per tid. The message is
\* RETAINED in net, so it may be delivered again — which is correctly ignored (models
\* duplicate delivery / at-least-once transport with receiver-side dedup).
Recv(m) ==
  /\ m \in net
  /\ m.tid \notin recvd
  /\ escrow' = [escrow EXCEPT ![m.to] = @ + 1]
  /\ recvd'  = recvd \cup {m.tid}
  /\ UNCHANGED <<spent, net, applied, sentT>>

\* Message loss: an in-flight message is dropped without being credited. The debited unit
\* stays counted in InFlight (permanently lost capacity) — safety is preserved.
Drop(m) ==
  /\ m \in net
  /\ net' = net \ {m}
  /\ UNCHANGED <<escrow, spent, applied, sentT, recvd>>

Next ==
  \/ \E r \in Replicas, cid \in Cids : Charge(r, cid)
  \/ \E i, j \in Replicas, t \in Tids : SendXfer(i, j, t)
  \/ \E m \in net : Recv(m)
  \/ \E m \in net : Drop(m)

Spec == Init /\ [][Next]_vars

(* ----- invariants ----- *)
TypeOK ==
  /\ escrow  \in [Replicas -> Nat]
  /\ spent   \in [Replicas -> Nat]
  /\ net     \in SUBSET Messages
  /\ applied \in SUBSET Cids
  /\ sentT   \in SUBSET Tids
  /\ recvd   \in SUBSET Tids
  /\ recvd \subseteq sentT

\* The exact conserved quantity — the heart of the artefact.
Conserved == SumSpent + SumEscrow + InFlight = CAP

\* The safety theorem, a corollary of Conserved and non-negativity.
Safety == SumSpent =< CAP
=============================================================================

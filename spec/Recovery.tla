----------------------------- MODULE Recovery -----------------------------
(*
 * Theory-checkpoint model: separate SAFETY, NON-CREATION and CONSERVATION.
 *
 * Uses the SIGNED linear authority quantity  A == Σspent + Σescrow  (no flooring), with escrow
 * kept ≥ 0 by construction here (a separate well-formedness concern; overdraft is studied in the
 * executable). Authority can be LOST (escrow -> stranded, A decreases) and RECLAIMED
 * (stranded -> escrow, A increases). Reclaim is guarded by `SafeReclaim`:
 *   SafeReclaim = TRUE  : may reclaim at most what was stranded  -> A rises but stays ≤ CAP
 *   SafeReclaim = FALSE : reclaims unconditionally               -> A can exceed CAP (creation)
 *
 * Three DISTINCT properties (never conflated):
 *   Safety     ==  Σspent ≤ CAP                 (state predicate)
 *   Bound      ==  A ≤ CAP                       (state predicate; the inductive safety cert)
 *   MonotoneA  ==  [][A' ≤ A]_vars               (transition/action property: non-creation)
 *   ConservedA ==  [][A' = A]_vars               (transition/action property: conservation)
 *)
EXTENDS Naturals, FiniteSets

CONSTANTS Replicas, CAP, Amounts, SafeReclaim
ASSUME CAP \in Nat /\ Replicas # {} /\ Amounts \subseteq (Nat \ {0}) /\ SafeReclaim \in BOOLEAN

VARIABLES escrow, spent, stranded
vars == <<escrow, spent, stranded>>

RECURSIVE SumFn(_, _)
SumFn(f, S) == IF S = {} THEN 0 ELSE LET x == CHOOSE e \in S : TRUE IN f[x] + SumFn(f, S \ {x})
SumEscrow == SumFn(escrow, Replicas)
SumSpent  == SumFn(spent, Replicas)
A         == SumSpent + SumEscrow           \* signed linear authority in circulation
Genesis   == CHOOSE r \in Replicas : TRUE

Init ==
  /\ escrow  = [r \in Replicas |-> IF r = Genesis THEN CAP ELSE 0]
  /\ spent   = [r \in Replicas |-> 0]
  /\ stranded = 0

Charge(r, a) ==                                     \* conserving: escrow -> spent (ΔA = 0)
  /\ a \in Amounts /\ a =< escrow[r]
  /\ escrow' = [escrow EXCEPT ![r] = @ - a]
  /\ spent'  = [spent  EXCEPT ![r] = @ + a]
  /\ stranded' = stranded

Lose(r, a) ==                                       \* authority-destroying: escrow -> stranded (ΔA < 0)
  /\ a \in Amounts /\ a =< escrow[r]
  /\ escrow' = [escrow EXCEPT ![r] = @ - a]
  /\ stranded' = stranded + a
  /\ spent' = spent

Reclaim(r, a) ==                                    \* authority-restoring: stranded -> escrow (ΔA > 0)
  /\ a \in Amounts
  /\ (SafeReclaim => a =< stranded)                 \* guard: only reclaim what was stranded
  /\ escrow' = [escrow EXCEPT ![r] = @ + a]
  /\ stranded' = IF SafeReclaim THEN stranded - a ELSE stranded
  /\ spent' = spent

Next ==
  \/ \E r \in Replicas, a \in Amounts : Charge(r, a)
  \/ \E r \in Replicas, a \in Amounts : Lose(r, a)
  \/ \E r \in Replicas, a \in Amounts : Reclaim(r, a)

Spec == Init /\ [][Next]_vars

TypeOK    == escrow \in [Replicas -> Nat] /\ spent \in [Replicas -> Nat] /\ stranded \in Nat
Safety    == SumSpent =< CAP
Bound     == A =< CAP
MonotoneA  == [][A' =< A]_vars
ConservedA == [][A' =  A]_vars
=============================================================================

# SCOPE.md — exact claims, invariant, and assumptions

## Two DIFFERENT properties (kept separate — this is the Floor C result)

**Safety (the cap theorem)** — what the service promises:

> For every execution — regardless of message **reordering, duplication, loss, retry**, and
> (from Floor D) **crash/recovery** and **temporary partition** — authorised consumption never
> exceeds `CAP`:  `Σ spent ≤ CAP`. Its inductive form is the **inequality**
> `SafetyLe :  Σ spent + Σ escrow + InFlight ≤ CAP`  (all terms `≥ 0`).

**Conservation (a strictly stronger property)** — no budget is silently lost:

> `Conserved :  Σ spent + Σ escrow + InFlight = CAP`,

where `InFlight` sums each transfer id's amount while it is debited-but-not-yet-credited (each
id once, including permanently lost transfers). `Conserved ⟹ SafetyLe`, never the reverse.

Floors A/B fused these into one equality. Floor C shows they come apart: an **extra or
mismatched debit only DESTROYS budget** (the sum drops → `SafetyLe` still holds, `Conserved`
fails), whereas **only a receiver-side double-CREDIT makes budget** (the sum rises → `SafetyLe`
fails). So the assumptions split cleanly by which property they defend.

**Bounded-checked now (Floors A, C):** `Safety`, `SafetyLe`, `Conserved` by **TLC** over full
*bounded* state spaces (Floor A: units; Floor C: arbitrary amounts `{1,2}`, idempotency toggled
by flags). Bounded evidence — **not** the unbounded theorem, which is Floor F (Lean 4). This
document never describes a bounded check as unbounded.

## Assumptions — grouped by the property each one defends

**Safety-critical (needed for `Σ spent ≤ CAP`):**

1. **Correct genesis.** Initially `Σ escrow = CAP`, `spent = 0`; the cap is fully, disjointly
   partitioned at init and never minted later.
2. **Local no-overspend.** A charge/transfer of `a` at replica `i` requires `a ≤ escrow[i]`;
   escrow and spent stay non-negative.
3. **Receiver-side transfer idempotency.** The receiver credits **at most once per transfer
   id**, crediting an amount that was actually debited for that id. Removing it CREATES budget
   (counterexample: `EscrowBudgetC_ReceiverDup`, 4 states).
4. **Durable receiver dedup (Floor D).** The receiver's dedup set survives crashes; otherwise a
   crash loses it while the credited balance is durable, and a retransmit re-credits
   (counterexample: `EscrowBudgetD_VolatileRecvd`, 4 states).
5. **Write-ahead debit before emit (Floor D).** A transfer's escrow debit is durable *before*
   the message is emitted; otherwise a crash reverts the debit while the message is in flight,
   and a **sender-side** crash creates budget (counterexample: `EscrowBudgetD_LazyDebit`, 3
   states — this refuted the "receiver-side only" reading; see below).
6. **No budget creation.** No reachable action — **including crash recovery** — raises the total
   except genesis. (Assumptions 3–5 are the concrete ways this can be violated once crashes
   exist; see the structural finding.)

**Conservation-only (needed for `= CAP`, i.e. no waste — NOT for the cap):** *These were once
assumed to be safety-critical; Floor B and C show they are not.*

5. **Charge idempotency** — no double-charge of one client request. Double-applying a charge id
   moves escrow→spent, preserving both `SafetyLe` and `Conserved` of the aggregate; it breaks
   only a **per-request** property (`per_request_ok`). *(Floor B; mutation-checked.)*
6. **Sender-side transfer idempotency** — a non-idempotent retry re-debits, only *destroying*
   budget. `SafetyLe` holds, `Conserved` fails. *(Floor C; model-checked: `SenderDup` holds
   Safety/SafetyLe, `SenderDupConserved` violates Conserved in 3 states.)*
7. **Globally-unique transfer ids** — two distinct transfers sharing an id each debit, but the
   receiver dedups and credits once → budget destroyed. `SafetyLe` holds, `Conserved` fails.
   *(Floor C; tested-only: `test_id_collision_breaks_conservation_not_safety`.)*

**Modelling assumption (both properties):**

8. **Atomic debit-before-send.** A transfer debits the sender before the amount is in flight;
   the amount is never simultaneously in an escrow and in flight.

Amounts are **arbitrary non-negative** (Floor B reference and Floor C model+impl). The Floor A
TLA+ model used units; the invariant shape is identical.

## Evidence grade per claim (never silently upgraded)

| Claim | Evidence |
|---|---|
| `Safety`/`SafetyLe`/`Conserved` hold (correct protocol) | **B** model-checked (TLC, bounded) + **C** executable PBT |
| Receiver-side idempotency is safety-critical | **B** model-checked counterexample + **C** mutation + negative-control test |
| Sender-side idempotency is conservation-only (not safety) | **B** model-checked (both directions) + **C** mutation/test |
| Transfer-id uniqueness is conservation-only (not safety) | **C** executable test only (not yet model-checked) |
| Charge idempotency is per-request-only (not safety) | **B** mutation-checked (Floor B) + **C** mutation |
| Safety survives all crash/partition/retransmit interleavings (disciplined) | **B** model-checked (`EscrowBudgetD`, full state space) + **C** PBT with crashes |
| Durable receiver dedup is safety-critical | **B** model-checked counterexample + **C** replay/mutation |
| Write-ahead debit is safety-critical (sender-side crash) | **B** model-checked counterexample + **C** replay/mutation |
| Crashes destroy budget (Conserved fails, Safety holds) | **B** model-checked + **C** replay |
| Unbounded, all-N version of any of the above | **not yet** — Floor F (Lean 4) |

## Floor D: the theorem changed — which assumption moved, and why

**Refuted (narrow reading of Floor C's asymmetry):** *"receiver-side faults are the only
safety-critical faults."* Counterexample `EscrowBudgetD_LazyDebit` (3 states): a **sender**
debits escrow in volatile memory, emits the transfer, then **crashes before persisting the
debit**; on recovery escrow reverts high while the message is still in flight → `Σescrow +
InFlight = 3 > CAP = 2`. Budget is created by a **sender-side** crash. The narrow reading is
false and is retired.

**What moved:** nothing was removed; **two new safety-critical assumptions appeared** with
crashes — *durable receiver dedup* (#4) and *write-ahead debit* (#5). Both were added to the
safety group only after a model-checked counterexample forced them (never pre-emptively).

**Survived (structural reading):** *"only budget-CREATING faults break safety; budget-DESTROYING
faults are safe."* The refutation hunt (`EscrowBudgetD`, correct discipline, full state space)
found **no** crash/partition/retransmit interleaving that breaks `Safety`/`SafetyLe`. Crashes
that lose un-persisted work only **destroy** budget: `EscrowBudgetD_Conserved` shows `Conserved`
fails under crashes while `Safety` holds. Both crash *safety*-faults (lazy-debit, volatile-recvd)
**create** budget; the destruction mutant (`crash-drops-inflight`) is caught only by
conservation. So the safety boundary is exactly *budget creation* — on **either** side.

**The simplification this yields (see README / report section G):** crashes and partitions
introduce **no new kind** of safety boundary. Safety reduces to a single structural requirement —
**no reachable action, recovery included, may increase the conserved quantity
`Σspent + Σescrow + InFlight` above CAP** (equivalently: *recovery must be contractive on
budget*). Write-ahead debit and durable receiver-dedup are not two separate rules but the two
concrete ways a crash could otherwise violate that one requirement.

**Note on `Conserved` under crashes:** it is **not** preserved (crashes lose budget). We do not
claim it in the presence of crashes; only `Safety`/`SafetyLe` are claimed there.

## Partition behaviour (honest CAP trade-off)

During a network partition a replica serves charges **only from its local escrow** — no
coordination is needed, so it stays **available for those charges**. If a replica's local
escrow is **exhausted**, further charges are **REJECTED** until a transfer refills it, which
requires connectivity. So the service **trades availability for safety exactly when a
replica's local escrow runs out during a partition**. This is deliberate and is the entire
availability cost. Message **loss** during a partition costs *capacity* (a lost transfer's
unit is gone) but never *safety*.

## NOT claimed

- **No liveness / progress.** Charges may be rejected; transfers may be lost. We prove only
  safety (`Σ spent ≤ CAP`), never that any charge eventually succeeds.
- **No availability.** See the partition trade-off above. This is a safety-only (CP-leaning)
  service; it is available for locally-funded charges and unavailable for charges that would
  need cross-replica coordination during a partition.
- **No fairness / allocation quality.** Nothing bounds how budget is distributed among
  replicas or clients.
- **No exactly-once delivery, no bounded staleness, no ordered channels.** The transport may
  reorder, duplicate, and drop arbitrarily; safety does not depend on any of these.
- **No unbounded theorem yet** (Floor A is bounded TLC only; Floor F is the machine-checked
  unbounded proof).

## Trusted base (so far)

The Rocq/Lean kernels (Floor F, later); TLC and the TLA+ semantics for the bounded checks; the
pinned TLA+ Tools **v1.7.4** verified by committed SHA-256. TLC results are bounded evidence,
not a proof for all N.

# SCOPE.md — exact claims, invariant, and assumptions

## The safety theorem (target)

> For every execution — regardless of message **reordering, duplication, loss, retry**, and
> (from Floor D) **crash/recovery** and **temporary partition** — the sum of successfully
> authorised consumption never exceeds `CAP`:  `Σ_i spent[i] ≤ CAP`.

It is a corollary of the **conserved quantity** (an inductive invariant of the protocol):

> `Σ_i spent[i]  +  Σ_i escrow[i]  +  InFlight  =  CAP`,   with all terms `≥ 0`,

where `InFlight` = escrow debited from a sender but not yet credited at a receiver (including
permanently lost transfers). Since `Σ escrow ≥ 0` and `InFlight ≥ 0`, `Σ spent ≤ CAP`.

**What is machine-checked now (Floor A):** the two invariants above, by **TLC** over the full
*bounded* reachable state space (2 replicas, CAP=2, 2 charge ids, 2 transfer ids). This is a
*bounded* result — **not** yet the unbounded theorem. The unbounded, all-N, all-execution
version is Floor F (Lean 4), proving the invariant is preserved by every transition by
induction. This document does **not** describe the bounded check as unbounded.

## Assumptions the theorem requires (be precise)

1. **Correct genesis.** Initially `Σ escrow = CAP` and `spent = 0`. The cap is fixed and
   fully, disjointly partitioned at initialisation. (No mechanism mints budget later.)
2. **Local no-overspend.** A charge of amount `a` at replica `i` requires `a ≤ escrow[i]`; it
   moves `a` from `escrow[i]` to `spent[i]`. Escrow and spent are non-negative.
3. **Idempotent charges (explicit dedup — NOT exactly-once transport).** Every charge carries
   a unique id; re-applying the same id at a replica is a no-op. Retries and duplicate
   requests are modelled and de-duplicated; we do **not** assume the transport delivers
   exactly once.
4. **Idempotent transfers.** Every transfer carries a unique id; the receiver credits at most
   once per id. Duplicate delivery is modelled and safely ignored.
5. **Atomic debit-before-send.** A transfer debits the sender's escrow *before* the unit is
   in flight; the unit is never simultaneously in an escrow and in flight.
6. **No budget creation.** No action increases the conserved total; only genesis sets it.
7. **Floor A simplification (temporary).** Charges/transfers move a **unit** (1). Arbitrary
   non-negative amounts are added in Floor C; the invariant is identical in shape.

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

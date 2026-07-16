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

## Theory checkpoint: Safety ≠ Non-creation ≠ Conservation

The Floor-D checkpoint proposed a monotonicity "law" (`A⁺` never increases). That **conflated
three distinct properties** and is corrected here. Let `A = Σspent + Σescrow + InFlight` (the
**signed** linear authority in circulation).

**Corrected definitions (kept apart):**

| Name | Statement | Kind |
|---|---|---|
| **Safety** | `Σspent ≤ CAP` | state predicate (the claim) |
| **Bound** | `A ≤ CAP` | state predicate (inductive safety certificate) |
| **Well-formedness (WF)** | `∀i: escrow[i] ≥ 0` | state predicate (solvency / no overdraft) |
| **Non-creation** | `A' ≤ A` on every step | transition property |
| **Conservation** | `A' = A` on every step | transition property |

**Formal questions — which are actually true:**

- **A. `A⁺ ≤ CAP ⟹ Σspent ≤ CAP`** — **TRUE by arithmetic** for the *floored* `A⁺ = Σspent +
  Σmax(escrow,0) + InFlight` (all terms ≥ 0 ⟹ `Σspent ≤ A⁺`). For the *signed* `A` it is
  **FALSE without WF** (overdraft: `A = CAP` yet `Σspent > CAP`); **TRUE with `WF`**.
- **B. genesis `A = CAP` + every step non-increasing ⟹ Safety** — **TRUE** (induction: `A` stays
  ≤ CAP, then A). This is a **sufficient** condition, not necessary.
- **C. every safety violation requires a state with `A > CAP`** — **formulation-dependent.** TRUE
  for floored `A⁺` (safety fails ⟹ `A⁺ ≥ Σspent > CAP`). **FALSE for signed `A`**: the overdraft
  counterexample has `Σspent > CAP` while signed `A = CAP` — the violation is a WF break, not an
  `A`-increase.
- **D. every increase in `A` is a safety violation** — **FALSE.** Model-checked counterexample
  (`Recovery_Monotone`, 3 states): `A = 3 →` Lose `→ A = 2 →` safe Reclaim `→ A = 3`. The reclaim
  **raises `A` from 2 to 3**, but `3 ≤ CAP`, so Safety holds. Non-creation fails; Safety intact.

**The local transition rule — necessary and sufficient vs sufficient-only:**

- **`A' ≤ CAP`** (with `WF` maintained) is **necessary and sufficient** to keep `Bound`/Safety
  inductively. This is the safety rule.
- **`A' ≤ A` (non-creation / monotonicity)** is **sufficient only**, **not necessary**, and
  **false for legitimate recovery**: a safe reclaim of stranded authority raises `A` within
  headroom. Requiring monotonicity would forbid recovering lost budget for no safety benefit.
- **`A' = A` (conservation)** is stronger still and **already false** in our protocol (crashes and
  drops destroy budget, safely). Not claimed under faults.

Trade-off, stated plainly: *non-increasing `A` prevents authority re-creation entirely (simple,
but bans safe recovery); bounded `A' ≤ CAP` permits recovering previously lost or stranded
authority while still guaranteeing safety.* We adopt the **bound**, not monotonicity.

**Transition classification (signed `A`; WF tracked separately):**

| Class | Δ`A` | examples | Safety |
|---|---|---|---|
| conserving | `= 0` | charge, send, receive, drop, persist, idempotent retry, double-charge | safe |
| authority-destroying | `< 0` | sender double-debit, id-collision, crash-loss, dropped in-flight | safe |
| authority-restoring within headroom | `> 0`, `A' ≤ CAP` | **safe reclaim** | safe |
| authority-creating beyond CAP | `> 0`, `A' > CAP` | double-credit, credit-without-debit, debit-revert-live-msg, unsafe reclaim | **UNSAFE** |
| overdraft (separate axis) | `= 0` (signed) | spend/charge past escrow | **UNSAFE** — breaks WF, not `A` |

The overdraft row is why signed `A` alone is not a certificate: it is conserving in `A` yet unsafe,
caught only by `WF` (or by the floored `A⁺`).

**Chosen formulation (clearest honest theorem):** the **signed linear `A` plus an explicit
`WF: escrow ≥ 0` invariant**, over the floored `A⁺` and over an explicit debt term.
Rationale: `A` stays **linear**, so Conservation (`A' = A`), Non-creation (`A' ≤ A`) and Bound
(`A ≤ CAP`) are all clean statements about the *same* quantity — exactly the separation required.
Flooring (`A⁺`) buys a single sufficient scalar and makes statement C hold, but is **non-linear**
(muddies conservation) and **hides** the overdraft-vs-creation distinction. An explicit
authority-minus-debt representation is unnecessary here because overdraft is **disallowed** (a WF
violation), not a state to be settled.

> **Safety theorem (corrected):** for all reachable states, `WF ∧ (A ≤ CAP)`, and hence
> `Σspent ≤ CAP`. Maintained by: the local no-overspend guard (preserves `WF`) and the local
> bound `A' ≤ CAP` (preserves `Bound`). **Not** by monotonicity.

**Evidence grades (never upgraded):**

| Claim | Evidence |
|---|---|
| `WF ∧ A ≤ CAP ⟹ Σspent ≤ CAP` | arithmetic (by inspection); **not** machine-checked (Floor F) |
| Safety/Bound hold under safe recovery | **B** model-checked (`Recovery_Safe`, full space) + **C** PBT |
| Non-creation holds for the *current* protocol | **B** model-checked (`EscrowBudgetC_Monotone`, `[][A'≤A]`) |
| Non-creation is **not** necessary (safe A-increase exists) | **B** counterexample (`Recovery_Monotone`) + **C** test |
| Conservation fails while Safety holds | **B** (`Recovery_Conservation`) + **C** test |
| Unguarded reclaim creates beyond CAP | **B** (`Recovery_Unsafe`) + **C** test |
| Overdraft is conserving in signed `A` yet unsafe (needs WF) | **C** executable test only |

**Revised Lean (Floor F) target:** prove, for all N, that `WF ∧ (A ≤ CAP)` is an **inductive
invariant** — every transition preserves `escrow ≥ 0` (local guard) and `A' ≤ CAP` — and that it
implies `Σspent ≤ CAP`. **Do not** target monotonicity (`A' ≤ A`) or conservation (`A' = A`) as
the safety theorem; both are stronger than needed and the first is false once recovery exists.

## Floor E: hostile testing of the frozen theory

The certificate `WF ∧ (A ≤ CAP)` was stress-tested, not re-derived. **The theory survived
hostile testing unchanged.**

- **Hostile harness** (`impl/fault_harness.py`): a stateful Hypothesis machine composing
  duplicated delivery, duplicated/retried send, arbitrary reorder, retry storms, loss, delayed
  delivery, crash-before/after-persist, repeated and simultaneous crashes, over varying replica
  count / CAP / amounts. **10,000 executions × 40 steps**: the certificate held on every step.
  Teeth check: the same harness on a broken (volatile-recvd) protocol is caught quickly.
- **Differential** (`impl/spec_model.py`): an independent Python BFS of `EscrowBudgetC`
  reproduces TLC's **66** distinct reachable states exactly, with `Safety`/`SafetyLe`/`Conserved`
  holding on all — the executable transition semantics conform to the model. No divergence.
- **Mutation**: the dedicated suites kill **12/12** (5 reference + 4 distributed + 3 crash). A
  conservation-only mutant (extra destruction) **survives the safety-focused harness by design**
  — it does not break `WF`/`Bound`/`Safety`; only a conservation check catches it (test in
  `test_floor_e.py`). No safety-breaking mutant survives.
- **Falsification attempts (all failed to break the theory):** `WF ∧ A≤CAP` with Safety violated
  — arithmetically impossible, never observed. Safety-holds-while-Bound-fails — reachable **only
  in a broken protocol** and *consistent* with Bound being sufficient-not-necessary (Bound is the
  earlier indicator). Impl traces inconsistent with the model — none (differential 66 = 66).

**Evidence grades (Floor E):** hostile-harness result and differential are **property-tested**
(C) and **model-checked-conformant** (B, via the 66-state match); the "safety ⟸ WF ∧ A≤CAP"
implication remains **arithmetic, not machine-proved** (Floor F).

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

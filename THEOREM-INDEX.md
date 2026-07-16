# THEOREM-INDEX.md

Every headline result, its evidence, grade, assumptions, and scope. **Grades are never conflated;**
"machine proof" means Lean only.

> On axioms: the Lean headline proofs have **zero project-defined axioms and no `sorry`**; they
> depend on Lean's standard `propext` and `Quot.sound`. This is **not** "axiom-free."

## Lean machine proofs (`lean/Escrow/`)

| Claim | Theorem | Grade | Assumptions | Scope / notes |
|---|---|---|---|---|
| Crash-free safety, all finite N | `reachable_safe` (`Reachability.lean`) | machine proof `[propext, Quot.sound]` | `rs.Nodup`, `ts.Nodup`, genesis `g ∈ rs`, amounts `Nat`, any `CAP` | No crash transitions; charge/send/recv/drop/noop |
| Crash/recovery safety, all finite N | `durable_reachable_safe` (`DurableReachability.lean`) | machine proof `[propext, Quot.sound]` | same + disciplined `DStep` | **Global** crash; abstract model (see `MODEL-CORRESPONDENCE.md`) |
| Certificate ⇒ safety (load-bearing hyps) | `certificate_implies_safety` (`Safety.lean`) | machine proof | stated over `ℤ`: `0≤se`, `0≤inf`, `sp+se+inf≤cap` | All three hyps needed; see negative control below |
| Conservation of `A` per transition | `A_preserved` (`Invariants.lean`) | machine proof | `rs`/`ts` Nodup, `DestOk` | Reused by both F1 and F2 |
| Joint invariant inductive | `Jinv_preserved` (`DurableInvariants.lean`) | machine proof | as above | `Bound cur ∧ Bound dur ∧ DestOk cur ∧ DestOk dur` |
| InFlight non-negative | `inflightNonneg_all` (`Invariants.lean`) | machine proof | none (holds by construction: amounts are `Nat`) | Load-bearing only over `ℤ` (the arithmetic core) |

### Lean negative controls (true theorems, `Negative.lean` / `DurableNegative.lean`)

| Fact demonstrated | Theorem |
|---|---|
| Without `InFlightNonneg`, `WF ∧ Bound → Safety` is false over ℤ | `inflight_nonneg_is_necessary` |
| Current-only invariant is not inductive under unconstrained restore | `restore_breaks_bound` |
| Lazy debit (write-ahead skipped) ⇒ `A dur = 2 > CAP` | `lazy_debit_breaks_durable_bound` |
| Volatile dedup (durable dedup skipped) ⇒ `A dur = 2 > CAP` | `volatile_dedup_breaks_durable_bound` |

### Load-bearing check (controlled proof mutations, run out-of-band, reverted)

Write-ahead debit and durable receiver dedup are genuinely load-bearing: removing write-ahead debit,
making receiver dedup volatile, letting `crash` restore escrow without phase consistency, letting
`persist` copy balance but not dedup, and letting `recv` re-emit a credited right **each break
`Jinv_preserved`**. Four analogous F1 mutations each break `reachable_safe`.

## TLA+ / TLC (bounded exhaustive; `spec/`)

| Claim | Model / config | Grade | Result |
|---|---|---|---|
| Safety, SafetyLe, Conserved (crash-free) | `EscrowBudget`, `EscrowBudgetC` | bounded exhaustive | hold |
| Broken variant caught | `EscrowBudgetBad` | bounded exhaustive | counterexample (negative control) |
| Receiver-idemp is cap-safety-critical | `EscrowBudgetC_ReceiverDup` | bounded | `SafetyLe` violated (negative control) |
| Sender-idemp is conservation-only | `EscrowBudgetC_SenderDup{,Conserved}` | bounded | Safety holds / Conserved violated |
| Crash discipline safe; lazy-debit & volatile-recvd unsafe | `EscrowBudgetD{,_LazyDebit,_VolatileRecvd,_Conserved}` | bounded | hold / violated (negative controls) |
| Safety ≠ Non-creation ≠ Conservation | `Recovery_{Safe,Monotone,Conservation,Unsafe}` | bounded | as designed |

## Python / Hypothesis (executable testing; `impl/`)

| Claim | Where | Grade |
|---|---|---|
| Reference/distributed/crash models pass deterministic + property tests | `impl/test_*.py` | executable testing |
| Hostile harness holds the certificate over 10⁴ composed-fault runs × 40 steps | `impl/fault_harness.py` | property testing |
| Mutation suites kill 12/12 injected faults | `impl/mutation_*.py` | mutation testing |
| Independent Python BFS reproduces TLC's 66 reachable states | `impl/spec_model.py` | bounded differential (agreement only) |

## Assumptions that appear in the Lean theorems (surfaced, not buried)

`[DecidableEq R] [DecidableEq T]`; `rs.Nodup`, `ts.Nodup` (finite duplicate-free rosters); genesis
`g ∈ rs`; amounts `Nat` (⇒ `WF`, `InFlightNonneg` by construction); disciplined transitions carry
their own guards (write-ahead durable debit, durable dedup phase-advance). No hidden helper-definition
smuggles an assumption.

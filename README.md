# escrow-budget

A **formally verified distributed budget protocol**. Multiple replicas hold portions of one global
budget. They may charge locally and transfer rights over an unreliable network. The protocol proves
that **aggregate authorised spending cannot exceed the global cap**, including under disciplined
crash/recovery, **provided write-ahead debit and durable receiver dedup are enforced**.

This repository is a **verification artefact**, not a production service: it contains protocol
models (TLA+), an executable model (Python), and machine-checked proofs (Lean 4), with every claim
mapped to its evidence grade.

## What is proved, precisely

Let `A = Σ spent + Σ escrow + InFlight` (in-flight = amounts sent but not yet received). The
**safety property** is the *bound*, not conservation:

```
    Σ spent[i]  ≤  CAP        (aggregate authorised consumption never exceeds the cap)
```

- **Crash-free** (`Escrow.reachable_safe`, Lean 4): for **arbitrary finite** replica and transfer
  sets, **arbitrary non-negative amounts**, and **any CAP (including 0)**, every reachable state
  satisfies `Σ spent ≤ CAP`. The inductive certificate is `WF ∧ InFlightNonneg ∧ Bound (A ≤ CAP)`.
- **Crash/recovery** (`Escrow.durable_reachable_safe`, Lean 4): the same, for the disciplined
  crash/recovery protocol (charge, write-ahead send, durable-dedup recv, duplicate-refusal, drop,
  persist, **global crash**, no-op), via the joint invariant `Bound cur ∧ Bound dur ∧ DestOk cur ∧
  DestOk dur`.

Both Lean headline theorems have **zero project-defined axioms and no `sorry`**; they depend on
Lean's standard `propext` and `Quot.sound` (audited by `make lean`).

## Scope — read this before trusting anything

- **No liveness, no fairness, no progress.** We never prove any charge or transfer eventually
  succeeds; charges may be rejected and transfers may be lost.
- **No availability.** A replica whose local escrow is exhausted must reject charges until a
  transfer refills it; **partitions may reduce availability** (safety is never affected).
- **No Byzantine replicas.** All replicas follow the protocol; there is no adversarial/faulty-node
  model.
- **No implementation refinement.** The Lean proof is about the *abstract* protocol. There is **no
  machine-checked refinement** connecting Lean, TLA+, and the Python model — they are cross-checked
  only at **bounded** scale (see `MODEL-CORRESPONDENCE.md`).
- **Crash scope is exactly as formalised.** The Lean crash is **global** (all replicas restore from
  durable simultaneously). Per-replica-independent crash is **model-checked (TLA+) and
  property-tested (Python) only**, not in the Lean proof.
- **Conservation is NOT the safety claim.** `A = CAP` (exact conservation) holds only without loss;
  crashes and message loss *destroy* budget safely. Safety is the inequality `A ≤ CAP`.
- **Static membership.** The replica/transfer sets are an arbitrary but **fixed** finite roster;
  replicas joining or leaving mid-execution is out of scope.
- **Safety depends on the discipline.** `write-ahead debit` and `durable receiver dedup` are
  machine-checkably load-bearing — remove either and the proof breaks (see `THEOREM-INDEX.md`).

## Reproduce every check

Requires a JDK (TLC), `curl` (fetches the pinned, checksummed TLA+ Tools), Python 3 with
`hypothesis`, and the Lean toolchain via `elan`/`lake` (`lean/lean-toolchain` pins the version).

```
make clean && make check          # TLA+ (positive + negative controls) + Python + Lean F1/F2
                                   # + placeholder scan + axiom audit
rm -rf lean/.lake && make clean && make check   # full rebuild from an empty Lean cache
```

`tools/tla2tools.jar` is **not** committed; `scripts/run-tlc.sh` downloads the pinned v1.7.4 release
on demand and verifies it against the committed SHA-256. Expected-negative TLA+ models are **negative
controls** (they must produce their counterexample), not release failures.

## Evidence grades (never conflated)

| Layer | Establishes |
|---|---|
| **Lean 4** | Unbounded machine proof of the abstract crash-free and crash/recovery protocols |
| **TLA+ / TLC** | Bounded exhaustive state exploration of small instances |
| **Python / Hypothesis** | Executable-model testing + fault injection (10⁴ composed-fault runs) |
| **Differential** | Bounded state-space agreement only (66-state match) — **not** a refinement proof |

## Documentation

- [`SCOPE.md`](SCOPE.md) — exact claims, assumptions, and the full development record.
- [`CLAIMS-AUDIT.md`](CLAIMS-AUDIT.md) — every public claim mapped to its evidence, with overstatement fixes.
- [`THEOREM-INDEX.md`](THEOREM-INDEX.md) — claim → theorem/model/test → grade → assumptions → scope.
- [`TCB.md`](TCB.md) — trusted computing base.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — protocol/state flow and the verification pipeline.
- [`MODEL-CORRESPONDENCE.md`](MODEL-CORRESPONDENCE.md) — Lean ↔ TLA+ ↔ Python mapping (no refinement claimed).
- [`RELEASE-NOTES.md`](RELEASE-NOTES.md) — floor-by-floor development history.
- [`PROVENANCE.md`](PROVENANCE.md) — how this artefact was built and what it reuses.

## Provenance

Successor artefact to the public `capctl-iris` (a shared-memory concurrent capability meter in
Iris/Rocq); this project targets the distributed-systems verification gap and reuses the
pinned-TLA+ toolchain pattern and the conserved-quantity design philosophy. See `PROVENANCE.md`.

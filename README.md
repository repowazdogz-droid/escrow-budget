# escrow-budget

A **verified distributed budget service** that never authorises aggregate consumption above a
fixed global cap `CAP`, under message **reordering, duplication, loss, retry, crash/recovery,
and temporary partition**. Multiple replicas serve charges *without synchronous coordination*
by holding disjoint **escrow** (local spend rights); the cap is a **conserved quantity**.

## The idea (escrow / bounded-counter)

The cap is partitioned into per-replica escrow. A replica CHARGES against its own escrow with
no coordination, and may TRANSFER escrow to another replica over an unreliable network. The
load-bearing property is an exact **conserved quantity** — nothing creates or destroys budget:

```
    Σ spent[i]  +  Σ escrow[i]  +  InFlight   =   CAP
```

where `InFlight` is escrow that has left a sender but not yet been credited at a receiver.
From this and non-negativity, the **safety theorem** follows immediately:

```
    Σ spent[i]  ≤  CAP          (aggregate authorised consumption never exceeds the cap)
```

Because escrow is disjoint and local, charges are served during a partition **without
coordination** — the honest cost is that a replica whose local escrow is exhausted must
**reject** further charges until a transfer refills it (availability is traded for safety
exactly there; see `SCOPE.md`). We claim **no** availability, fairness, or liveness.

## Floor C finding (the point of this floor)

Floors A/B treated one exact equality — `Σspent + Σescrow + InFlight = CAP` — as *the* safety
invariant. Floor C separates it into two properties and shows which assumptions each needs:

- **Safety** (the cap): `Σspent + Σescrow + InFlight ≤ CAP`. Depends on exactly **one**
  idempotency — **receiver-side transfer dedup**. A receiver double-credit *creates* budget and
  breaks the cap.
- **Conservation** (no waste): the exact `= CAP`. Additionally needs **sender-side** transfer
  idempotency **and globally-unique transfer ids**.

The insight: *every* extra or mismatched **debit** (sender retry, id collision, double-charge)
only **destroys** budget — safe, just wasteful. Only a **receiver double-credit** is
safety-critical. So charge idempotency, sender idempotency, and transfer-id uniqueness are
**conservation/utilisation** concerns, **not** premises of the cap theorem. Verified three ways:
the TLC config matrix (`make tlc-c`), Hypothesis PBT + adversarial replays, and mutation
classification (`make impl-c`). Smallest counterexamples and per-claim evidence grades in
`SCOPE.md`.

## Floor D result (crash/recovery — the theory got *simpler*)

Floor D treated Floor C's asymmetry as a hypothesis and attacked it with crashes and partitions.
Outcome:

- **The narrow reading is FALSE.** "Receiver-side faults are the only safety-critical faults" is
  refuted by a 3-state counterexample: a **sender** that debits escrow but crashes *before
  persisting the debit* creates budget (escrow reverts high while the transfer is in flight).
- **The structural reading SURVIVED every refutation attempt** (full-state-space TLC hunt +
  400×50-step crash PBT + mutation): *only budget-**creating** faults break safety; budget-
  **destroying** faults are safe.* Crashes that lose un-persisted work only destroy budget
  (`Conserved` fails, `Safety` holds).

**The simplification:** crashes and partitions add **no new kind** of safety boundary. Safety is
exactly *"no reachable action, recovery included, increases the conserved quantity above CAP"* —
**recovery must be contractive on budget.** The two crash-era safety requirements (write-ahead
the debit before emitting; keep receiver-dedup durable) are just the two concrete ways a crash
could otherwise create budget. Verified three ways: `make tlc-d`, `make impl-d`. Counterexamples
and the retired assumption are in `SCOPE.md`.

## Status — Floor D (this branch)

- **Floor D — crash/recovery model + impl** (`spec/EscrowBudgetD.tla`, `impl/durable.py`):
  durable vs volatile state, `Persist`/`Crash`, monotonic external network (models partition,
  healing, retransmission-after-recovery), two durability disciplines toggled by flags. A
  4-config TLC matrix (refutation hunt + both crash safety-faults + destruction control), a
  Hypothesis crash-PBT, and mutation testing (3/3, classified cap-safety vs conservation-only).

## Status — Floors A + B + C (earlier)

- **Floor C — distributed model + impl** (`spec/EscrowBudgetC.tla`, `impl/distributed.py`):
  arbitrary amounts, explicit message ids, unreliable network (reorder/duplicate/loss/retry),
  sender/receiver idempotency toggled by flags. A **4-config TLC matrix** measures each
  assumption's necessity in both directions; a **Hypothesis stateful PBT** checks the cap under
  random adversarial schedules; **mutation testing** (4/4) classifies each fault as
  cap-safety / conservation-only / per-request-only. See the finding above.

## Status — Floors A + B (earlier)

- **Floor A — protocol model** (`spec/EscrowBudget.tla`): replicas, charge, transfer, and an
  unreliable network (reorder / duplicate / loss); idempotent transfers (explicit dedup — **no**
  exactly-once delivery assumed). Invariants `Conserved` and `Safety`, bounded-checked by **TLC**
  (pinned TLA+ Tools v1.7.4, SHA-256-verified) over the full reachable state space. A
  deliberately-broken variant (`spec/EscrowBudgetBad.tla`) is **caught** by TLC.
- **Floor B — executable reference** (`impl/escrow.py`): a centralised state machine with
  **arbitrary** non-negative amounts whose single source of truth is the conserved quantity
  (self-checked after every op). Tests (`impl/test_escrow.py`, 8 cases incl. a negative control)
  pass; **mutation testing** (`impl/mutation_check.py`) kills **5/5** injected faults.
  Finding (a strengthening): charge idempotency is **not** required for the cap theorem — it's
  a separate per-request property, caught by a distinct check (see `SCOPE.md`).

## Floor E result (hostile testing — theory survived unchanged)

The frozen certificate `WF ∧ (A ≤ CAP)` was attacked, not re-derived: a Hypothesis harness
composing every fault (dup delivery/send, reorder, retry storms, loss, delay, crash before/after
persist, repeated + simultaneous crashes) over varying replica count / CAP / amounts held the
certificate across **10,000 executions × 40 steps** (`make stress`). An independent Python BFS
reproduced TLC's **66** reachable states exactly (differential conformance). Mutation: **12/12**
killed; a conservation-only mutant survives the *safety* harness by design (caught only by a
conservation check). Every falsification attempt failed. **The theory survived hostile testing
unchanged** — see `SCOPE.md`.

## Floor F1 result (machine-checked, crash-free)

`lean/` machine-proves the **crash-free** protocol safe in **Lean 4** (pinned `v4.32.0`, no
mathlib): `Escrow.reachable_safe` — every state reachable from genesis has `Σspent ≤ CAP`, for
**arbitrary finite replica/transfer sets, arbitrary non-negative amounts, any CAP including 0**.
The inductive certificate is the corrected `WF ∧ InFlightNonneg ∧ Bound` (the `InFlightNonneg`
hypothesis is the hostile-review fix, load-bearing over ℤ). **Axioms: `[propext, Quot.sound]`
only — no `sorry`, no `Classical.choice`, no custom axioms** (`make lean` audits this). The two
hostile-review defects are preserved as true negative theorems (`Escrow/Negative.lean`), and four
controlled mutations each break the proof.

**Crash/recovery is explicitly NOT machine-proved** — it remains model-checked (Floor D) and
property-tested (Floor E) only. That extension is Floor F2 (see `SCOPE.md`), gated on a stronger
current+durable invariant.

Planned floors: **F2** machine-checked crash/recovery theorem (deferred) · **G** release +
hostile audit.

## Run

Requires a JDK (for TLC) and `curl` (to fetch the pinned, checksummed TLA+ Tools):

```
make check      # correct model must PASS; broken model must be CAUGHT
```

`tools/tla2tools.jar` is not committed; `scripts/run-tlc.sh` downloads the pinned v1.7.4
release on demand and verifies it against `tools/tla2tools.jar.sha256`.

## Provenance

Successor artefact to `capctl-iris` (shared-memory concurrent capability meter, Iris/Rocq).
This project targets the *distributed-systems verification* gap; it reuses the pinned-TLA+
toolchain pattern and the conserved-quantity design philosophy. See `SCOPE.md` for exact
claims and assumptions.

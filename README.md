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

## Status — Floors A + B (this branch)

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

Planned floors: **C** distributed message-passing under duplication/reordering/retry (generalised
amounts) · **D** crash/recovery + partition · **E** distributed impl + model-based / property-based
tests (Hypothesis) + fault injection · **F** machine-checked *unbounded* conserved-quantity
theorem (Lean 4) · **G** release + hostile audit.

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

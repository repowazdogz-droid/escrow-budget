# ARCHITECTURE.md

## The protocol

One global budget `CAP` is partitioned into per-replica **escrow** (local spend rights). Every unit
of authority is always in exactly one place, which is what the safety argument tracks:

```
    CAP  =  Σ spent        (already consumed, per replica)
          + Σ escrow       (held locally, ready to spend)
          + InFlight       (debited from a sender, not yet credited to a receiver)
```

Safety is the **bound** `Σ spent ≤ CAP`. It follows from `A = Σspent + Σescrow + InFlight ≤ CAP`
together with `escrow ≥ 0` and `InFlight ≥ 0` (all three are the certificate).

### Transfer lifecycle (one transfer id `t`)

```
   unsent ──send(i→j, amount a)──▶ inflight ──recv──▶ received
             debit escrow[i] by a     credit escrow[j] by a
             (write-ahead: durable     (durable dedup: durable
              debit persisted)          phase→received persisted)
```

- **charge(r, a)** (`a ≤ escrow[r]`): move `a` from `escrow[r]` to `spent[r]`. No coordination.
- **send**: `a` leaves the sender's escrow and becomes in-flight (`A` unchanged).
- **recv** (guard `phase = inflight`, so a received transfer cannot be re-credited): in-flight `a`
  becomes the receiver's escrow (`A` unchanged). Duplicate delivery / retransmission is refused.
- **drop**: message lost — the right stays represented as in-flight (safe: `A` unchanged; the unit
  is simply never spendable again).

Every ordinary transition **preserves `A`** (`A_preserved`); loss and crash only *destroy* `A`
(safe). Nothing except genesis can *increase* `A`.

## Crash / persist (Floor F2)

Each replica has a **volatile** current state and a **durable** checkpoint.

- **persist**: `durable := current` (checkpoint).
- **crash**: `current := durable` (restore; **global** in the Lean model).
- **write-ahead debit**: `send` persists the debit to durable *as part of sending* — so a crash can
  never restore escrow to a pre-debit value while the transfer is replayable.
- **durable receiver dedup**: `recv` persists the received-status to durable — so a crash can never
  lose the dedup evidence and let a retransmission double-credit.

The joint invariant `Bound cur ∧ Bound dur ∧ DestOk cur ∧ DestOk dur` is inductive; **crash is safe
because the durable state is itself bounded** (`crash` sets `cur := dur`, and `Bound dur` holds).

## Verification pipeline (evidence layers)

```
  TLA+ models  ──TLC (bounded exhaustive)──▶  positive models hold;
  spec/*.tla                                  negative models = intended counterexamples

  Python model ──deterministic + Hypothesis property + fault injection──▶  certificate holds
  impl/*.py    ──10,000 composed-fault runs; 12/12 mutants killed

  Differential ──independent Python BFS reproduces TLC's 66 states──▶  bounded agreement only

  Lean 4       ──kernel-checked, mathlib-free──▶  reachable_safe, durable_reachable_safe
  lean/Escrow  ──axioms [propext, Quot.sound]; no sorry; mutations break the proof
```

`make check` runs all four layers plus a placeholder scan and axiom audit. The layers are **not**
connected by a machine-checked refinement (`MODEL-CORRESPONDENCE.md`); Lean proves the abstract
protocol, TLC/Python provide bounded/tested evidence for the richer concrete behaviours.

## Trust boundary

See `TCB.md`. In short: trust the Lean kernel + `propext`/`Quot.sound`, TLC + TLA+ semantics
(pinned, checksum-verified) for the bounded results, and CPython + Hypothesis for the tests. The
faithfulness of each model to the intended protocol is argued, not machine-proved.

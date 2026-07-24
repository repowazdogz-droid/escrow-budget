# Inductive-invariant difficulty tracks a nameable conserved quantity, not state-space size

**The observation.** Across the three specs in this artefact, how hard it was to find an
inductive invariant had no relationship to how large the state space was. It tracked one thing:
whether the model had a **conserved quantity that could be named as a single equation**. Where
one existed, the induction closed with a single extra conjunct. Where none existed, it took
seven rounds and nine conjuncts — on the *smallest* state space of the three.

This is an observation from three specs in one artefact, not a law. See *Scope and limits*.

## Evidence

| spec | reachable states | conserved quantity | conjuncts to close | CTI rounds |
|---|---|---|---|---|
| `EscrowBudget` (Floor A) | **257** | `SumSpent + SumEscrow + InFlight = CAP` | **1** (`NetTidsSent`) | 1 |
| `Recovery` | **35** | `A + stranded = CAP` | **1** (`ConservedTotal`) | 1 |
| `EscrowBudgetD` (Floor D) | **56** | none nameable | **9** † | 7 |

State counts are TLC's distinct-state counts at each spec's shipped `.cfg`. Conjunct counts are
the auxiliary predicates added beyond `TypeOK /\ <property>`.

† Iteration produced ten; one (`DurableRecvdSub`) was step-checked to be redundant given
`dRecvdEqRecvd`, so the minimal certificate needs nine. Both forms are certified by
`make apalache-inductive`.

Floor D has **less than a quarter** of Floor A's state space and took **nine times** the
conjuncts. If state-space size predicted difficulty, this table would be sorted the other way.

## Mechanism: why Floor D has no conserved quantity to name

Floors A and Recovery each have a single quantity that every action leaves invariant. In
Floor A, `Charge` moves a unit escrow→spent, `SendXfer` moves it escrow→in-flight, `Recv` moves
it in-flight→escrow; the three-term sum never changes. In Recovery, `Lose` moves authority
escrow→stranded and a guarded `Reclaim` moves it back; `A + stranded` never changes. In both
cases the invariant is the conservation equation plus one well-formedness fact, and that is the
whole certificate.

Floor D has no such quantity because **its durable state is never a coherent snapshot of any
past state**. Different actions write different components of the durable triple
`(dEscrow, dSpent, dRecvd)` at different moments:

| action | `dEscrow` | `dSpent` | `dRecvd` |
|---|---|---|---|
| `Charge(r, a)` | — | — | — |
| `SendXfer(i, j, t, a)` | written, to `escrow[i] - a` (iff `DebitDurableBeforeSend`) | — | — |
| `Recv(m)` | written, to `escrow[m.to] + amtOf[m.tid]` | — | written (iff `RecvdDurable`) |
| `Persist(r)` | written, to `escrow[r]` | written, to `spent[r]` | written, to `recvd[r]` |
| `Crash(r)` | — (read: restores `escrow[r]`) | — (read: restores `spent[r]`) | — (read: restores `recvd[r]`) |

Read the `Charge` and `Recv` rows together and the problem is visible. `Charge` moves budget
from `escrow` to `spent` and writes **nothing** durable, so after a charge the durable copy is
stale in two directions at once: `dEscrow[r]` is too high and `dSpent[r]` is too low. `Recv`
then writes `dEscrow` eagerly — bringing the escrow component up to date — while leaving
`dSpent` stale. So the durable triple mixes one component captured *now* with another captured
at some arbitrary earlier point.

`Crash(r)` reads all three together and installs them as current state. That is the action the
induction must survive, and it is why no single equation suffices: the certificate has to
constrain how far each durable component may lag *relative to the others*, per replica. That is
what the nine conjuncts do — four rule out malformed records, one bounds the durable budget,
three bound the per-replica lag (`DurableSpentLe`, `DurableEscrowGe`, `LagOrder`), and one
forces the durable dedup set to stay in lockstep (`dRecvdEqRecvd`).

The CTIs got progressively subtler in exactly the way this predicts. CTI-1 was an obviously
malformed state (a tid credited at a replica it was never sent to). CTI-5 was two replicas
lagging in *opposite* directions such that `Persist` on one double-counts against the staleness
of the other — a state where every predicate found so far held, both the current and durable
sums equalled CAP exactly, and it was still unreachable.

## The diagnostic, before you start

Before beginning CTI iteration on a spec, ask:

> **Is there a single equation, over the state variables, that every action preserves?**

Work through the actions one at a time and ask what each does to a candidate sum. If you can
write that equation, expect to close in one or two rounds: the certificate is the equation plus
whatever well-formedness facts the guards rely on but do not state. Budget accordingly.

If you cannot write it, look for the specific reason — and the most common one is a
**split-write pattern**: two or more variables that jointly represent one logical fact, written
by *different* actions at *different* times. Durable-vs-volatile pairs are the obvious case;
so are cache-vs-source, replica-vs-leader, and index-vs-collection. When you see that pattern,
expect a per-component lag invariant rather than a conservation law, expect the conjunct count
to scale with the number of split components rather than with the state space, and expect the
late CTIs to be states where every individual component looks fine.

A practical corollary: the cheap screen is to write down the candidate equation *before*
running anything. It costs minutes and it tells you which of the two regimes you are in.

## Scope and limits

- **n = 3.** Three specs, one artefact, one author, all modelling variants of the same
  escrow-budget protocol. That is a shared-lineage sample, not an independent one — the three
  are not three draws from "distributed protocols".
- **The comparison is not controlled.** Floor D differs from Floor A in more than the presence
  of a conserved quantity: it has eight state variables to Floor A's six, adds crash and
  persist actions, and carries two boolean configuration constants. The mechanism above
  argues the split-write pattern is what did the damage, but this evidence cannot separate it
  from "Floor D is simply a more complex model".
- **Conjunct count is a proxy, and a soft one.** Iteration produced ten and one proved
  redundant on inspection; a sharper invariant might use fewer still, and nobody searched for
  the minimum. Round count is likewise sensitive to how well each CTI was diagnosed, which is a
  property of the person doing it, not only of the spec. Treat "9 vs 1" as an order-of-magnitude
  contrast, not a measurement.
- **All state counts are at fixed constants.** They would change with the constants, and so
  might the difficulty ordering.
- **Says nothing about** proof assistants, unbounded-N verification, liveness, or specs whose
  hardness comes from arithmetic or data structures rather than from split writes. The one
  case here where a conserved quantity existed but the spec was still awkward — Recovery's
  `Bound`, documented as inductive when it was not — failed for a different reason: the
  quantity was named but the *wrong* one was chosen.

What would move this from observation to something firmer: apply the diagnostic *before*
starting on a spec nobody in this artefact wrote, record the prediction, then run the CTI loop
and score it. That is a prediction with a date attached, which is the only version of this
claim worth more than the anecdote above.

## Provenance

Derived from the work recorded in [`FLOORD-CTI.md`](FLOORD-CTI.md) (Floor D, 7 CTI rounds) and
the certificates in `spec/EscrowBudget.tla` and `spec/Recovery.tla`. All inductiveness results
produced with Apalache 0.58.3 via `scripts/apalache-inductive.sh`; all state counts with TLC
2.19. Decision to adopt Apalache for inductiveness checking only: `D166`.

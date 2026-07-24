# Inductive-invariant difficulty tracks coupled state components, not state-space size

**Status: revised 2026-07-24 after a falsification test. The original version of this note
overstated its case in two ways; both corrections are recorded below rather than quietly
edited out.** The surviving claim is weaker and more specific than the one first published.

## What survives

Across four TLA+ models in this artefact, the number of conjuncts an inductive invariant
needs had **no relationship to state-space size**. The largest state space needed the
second-fewest conjuncts; the smallest needed the most.

What it tracked instead: **how many independent state components a single action can install
wholesale.** Crash/recovery models have a durable copy that `Crash` installs over the current
state in one step, so the certificate must relate every durable component to its current
counterpart — regardless of how coherently those components were written.

## Evidence

All counts are **greedy-minimised**: conjuncts were dropped one at a time and the certificate
re-checked, repeating until no single further drop preserved closure. Counts are auxiliary
predicates beyond `TypeOK /\ <the property being certified>`.

| spec | reachable states | property | minimal conjuncts | crash/recovery? |
|---|---|---|---|---|
| `Recovery` | 35 | `Bound` | **1** (`ConservedTotal`) | no |
| `EscrowBudget` (Floor A) | 257 | `Safety` | **2** (`Conserved`, `NetTidsSent`) | no |
| `EscrowBudgetD` (Floor D) | 56 | `SafetyLe` | **5** | yes |
| `EscrowBudgetD` atomic-write variant | 41 | `SafetyLe` | **4** | yes |

Floor A has **4.6×** Floor D's state space and needs fewer than half the conjuncts. That is
the observation, and it is the part that held up.

## Correction 1 — the original magnitude was inflated

The first version of this note reported "9 vs 1" and said Floor D took "nine times the
conjuncts". Both numbers were wrong, for two separate reasons:

- **Floor D's 9 was never minimised.** It was whatever the CTI loop happened to accumulate.
  Greedy minimisation brings it to **5**; four of the nine are individually droppable and
  `DurableSafetyLe`, `DurableSpentLe`, `RecvdOnlyAddressed` and `AmtOfSentOnly` all fall out.
- **The baselines were inconsistent.** Floor A was counted as "1" by treating `Conserved` as
  the starting point rather than as part of the certificate. Counted the same way as the
  others — auxiliary predicates beyond `TypeOK /\ <property>` — it is **2**.

The corrected ratio is roughly 2.5–5×, not 9×. The ordering survives; the magnitude does not.
Comparing an unminimised certificate against minimised ones is not a measurement, and the
original table did exactly that.

## Correction 2 — "no nameable conserved quantity" was the wrong mechanism

The original note asserted that Floor D is hard because **its durable state is never a
coherent snapshot of any past state**: `Charge` writes nothing durable, `Recv` writes
`dEscrow` eagerly but never `dSpent`, so the durable triple mixes components captured at
different moments. The diagnostic built on this told readers to look for a *split-write
pattern*.

**That was tested directly and it does not carry the weight it was given.** A variant was
built (`EscrowBudgetDAtomic`, scratch only — never shipped) in which `Recv` and `SendXfer`
write the whole durable triple coherently, so the durable state is *always* a coherent
snapshot. The CTI loop was re-run from `TypeOK /\ SafetyLe`.

Result: the minimal certificate went from **5 conjuncts to 4**. One conjunct.

The predicted effect *did* occur, and exactly where predicted — the two lag inequalities

```tla
DurableEscrowGe == \A r \in Replicas : dEscrow[r] >= escrow[r]
LagOrder        == \A r \in Replicas : dEscrow[r] + dSpent[r] =< escrow[r] + spent[r]
```

collapse into the single per-replica equality

```tla
LagEq == \A r \in Replicas : dEscrow[r] + dSpent[r] = escrow[r] + spent[r]
```

So the split-write mechanism is **real but minor**: it accounts for one conjunct out of five.
It is not why Floor D is hard.

**The sharper refutation:** the atomic variant *has* a nameable conserved quantity — `LagEq`
is a clean per-replica conservation equality, exactly the kind of thing the original note said
Floor D lacked. And it still needs **4** conjuncts, against Recovery's 1. So "has a nameable
conserved quantity ⇒ closes in about one conjunct" is false. Having the quantity is not
sufficient.

Both minimal Floor D certificates need the same three things, coherent writes or not:

```tla
TidUnique       \* at most one in-flight message per transfer id
dRecvdEqRecvd   \* the durable dedup set tracks the current one
dRecvdAddressed \* a durable credit record implies a matching sent message
```

plus one lag predicate. Those are about **crash/recovery existing at all** — `Crash` installs
the durable triple wholesale, so the certificate must pin every durable component against its
current counterpart. Write coherence changes how many predicates that pinning takes; it does
not remove the need for it.

## The revised diagnostic, before you start

Ask, in order:

1. **Can a single action replace several state components at once with values from elsewhere?**
   Crash-restores-from-durable, snapshot-restore, cache-invalidate, leader-handoff, rollback.
   If yes, expect the certificate to carry roughly one conjunct per component pair that action
   relates, and expect that to dominate everything else. This is the one that predicted well.
2. **Is there a single equation over the state variables that every action preserves?** If yes
   it will be the backbone of the certificate — but it is not sufficient on its own, and it does
   not by itself get you to one or two conjuncts.
3. **Do not use state-space size as a proxy for difficulty.** On this evidence it carries no
   signal at all, and it points the wrong way as often as not.

The split-write question from the original note is worth asking, but demote it: expect it to
cost about one conjunct, not to be the deciding factor.

## Scope and limits

- **n = 4 models, one artefact, one author, one protocol family.** Shared lineage, not an
  independent sample. Three of the four are variants of the same escrow-budget protocol.
- **Only one intervention was run.** The atomic-write variant is a single manipulation testing
  a single mechanism. It changes the protocol (`Recv` and `SendXfer` become full checkpoints),
  so "4 vs 5" compares two related protocols, not one protocol under two representations. A
  purely representational test — ghost variables that leave the transition relation on the
  original variables untouched — was **not** run, and would be the cleaner experiment. Its
  known hazard is that a sufficiently informative ghost closes any invariant trivially, so it
  needs a naturalness criterion decided in advance.
- **"Locally minimal" is not "minimal".** Greedy single-drop minimisation finds a set where no
  *one* further conjunct can go. It does not find the globally smallest set, and it does not
  explore different starting certificates that might close with fewer. Single-drop redundancy
  also does not compose: on the atomic variant three conjuncts were each individually
  droppable, but dropping all three together does **not** close.
- **Conjunct count is a coarse proxy for difficulty,** and it is sensitive to how each predicate
  was phrased. `LagEq` does the work of two inequalities; someone who wrote the inequalities
  more cleverly might have needed fewer from the start.
- **All counts are at fixed constants** and would change with them.
- **Says nothing about** proof assistants, unbounded-N verification, liveness, or models whose
  hardness comes from arithmetic or data structures.

What would move this from observation to something firmer: run the ghost-variable version to
separate representation from protocol; then apply the revised diagnostic to a crash/recovery
spec from outside this artefact, record the predicted conjunct count *before* running the CTI
loop, and score it.

## Provenance

Certificates and CTI sequence: [`FLOORD-CTI.md`](FLOORD-CTI.md), `spec/EscrowBudget.tla`,
`spec/Recovery.tla`, `spec/EscrowBudgetD.tla`. Inductiveness results from Apalache 0.58.3 via
`scripts/apalache-inductive.sh` (which asserts on Apalache's init-predicate log line, not its
exit code); state counts from TLC 2.19. The falsification test and all minimisation runs were
done in a scratch tree; `EscrowBudgetDAtomic` is **not** part of the artefact and is not
shipped. Apalache adoption decision: `D166`.

# State-space size does not predict inductive-invariant difficulty. Nothing else here does either.

**Status: revised twice on 2026-07-24.** The original claim was corrected once after an
in-artefact falsification test, and its replacement was then refuted outright by a
pre-registered test against an outside spec ([`PREDICTION.md`](PREDICTION.md)). What is left
is a negative result and a counting rule. Both revisions are recorded rather than edited out.

## What survives

Across five TLA+ models — four in this artefact and one outside it — the number of conjuncts
an inductive invariant needs has **no relationship to state-space size**. Two specs with
near-identical state spaces (257 and 288 reachable states) differ 3.5× in conjuncts.

**No positive mechanism survives.** Two were proposed and both are refuted:

| # | proposed mechanism | refuted by |
|---|---|---|
| 1 | difficulty tracks a nameable **conserved quantity** | the atomic-write variant *has* one and still needs 4 |
| 2 | difficulty tracks components a single action **installs wholesale** | TwoPhase has **none** and needs 7 — more than Floor D, which has one |

Refutation 2 was a **pre-registered** prediction: band 2–4, discriminating prediction "fewer
than Floor D's 5", committed and tagged before the answer was read. The answer was 7. See
[`PREDICTION.md`](PREDICTION.md) for the frozen prediction and the scoring.

The honest position is that I cannot predict conjunct count from spec structure. A third
mechanism would have to be pre-registered against an unexamined spec before it means
anything, and no such mechanism is offered here.

## The conjunct-counting rule

`LagEq` showed the metric is granularity-sensitive — one equality did the work of two
inequalities — so the number means nothing until the splitting convention is fixed. This rule
was fixed in advance of the TwoPhase test, not chosen after seeing results:

1. Start from the certificate conjoined with the property being certified.
2. Discard the type-correctness conjunct and the property itself. What remains are the
   **auxiliary** conjuncts — those are what get counted.
3. **Greedy-minimise**: drop one auxiliary conjunct, re-check every obligation, keep the drop
   if it still closes; repeat until no single further drop closes. Report the locally minimal
   set, not the set as written.
4. **COARSE count** = top-level conjuncts of that minimal set, flattening `/\` but **not**
   descending under `\A`, `\E`, or `=>`.
5. **FINE count** = same, after maximally distributing `\A` over `/\`.

Report both. COARSE is the headline; FINE bounds how much of the number is phrasing. If they
disagree by more than about 2×, the measurement did not discriminate and no comparison should
be drawn from it. On TwoPhase they agreed exactly (7 and 7), so that result stands.

Two consequences worth stating separately, because ignoring either inflates comparisons:

- **Step 3 is not optional.** Every certificate examined was non-minimal as written — Floor D
  9 → 5, TwoPhase's published invariant 9 → 7. The first version of this note compared an
  unminimised count against minimised ones and reported a 9× effect that was really ~2.5×.
- **Obligations, plural.** "Closes" means base (`Init => Inv`), step (`Inv /\ Next => Inv'`)
  **and** implication (`Inv => property`). Dropping the third lets a candidate pass by being
  strong on preservation and useless for the goal.

## Evidence

All counts greedy-minimised under the rule above.

| spec | source | reachable states | minimal conjuncts | wholesale-replacing action? |
|---|---|---|---|---|
| `Recovery` | this artefact | 35 | **1** | no |
| `EscrowBudget` (Floor A) | this artefact | 257 | **2** | no |
| `TwoPhase` (3 RMs) | tlaplus/Examples | **288** | **7** | **no** |
| `EscrowBudgetD` (Floor D) | this artefact | 56 | **5** | yes |
| `EscrowBudgetD` atomic-write | scratch variant | 41 | **4** | yes |

The two rows that matter: **Floor A and TwoPhase have near-identical state spaces (257 vs 288)
and differ 3.5× in conjuncts** — so size predicts nothing, now confirmed on a spec from outside
this artefact. And **TwoPhase, with no wholesale-replacing action, needs more than Floor D,
which has one** — so the mechanism proposed in the previous revision is wrong.

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

## Correction 3 — the replacement diagnostic failed its first outside test

Correction 2 proposed a diagnostic: *"can a single action replace several state components at
once? If yes, expect that to dominate."* It was pre-registered against Gray & Lamport's
two-phase commit and **scored wrong**. TwoPhase has no such action anywhere and needs **7**
conjuncts — more than Floor D, which has one and needs 5. Predicted band was 2–4. Full
pre-registration and scoring: [`PREDICTION.md`](PREDICTION.md), tag `prediction-twophase`.

The diagnostic is withdrawn. It is not restated here in weakened form, because a heuristic
that predicted the wrong ordering on its only out-of-sample test has no demonstrated
predictive content at all.

## What to actually do, given no diagnostic works

1. **Do not use state-space size as a proxy for difficulty.** This is the one thing the
   evidence supports, and it is supported out-of-sample: 257 states → 2 conjuncts, 288 states
   → 7.
2. **Do not budget from spec structure.** Five specs, two mechanisms, both refuted. Run the CTI
   loop and find out; it is cheap (1–2 s per obligation) compared with the time spent theorising
   about how many rounds it ought to take.
3. **Minimise before comparing anything.** Every certificate examined was non-minimal as
   written. Comparisons of as-written counts are meaningless.

A post-hoc reading of TwoPhase — that its cost comes from relating a monotone message history
to two state variables, roughly one conjunct per "what does this message imply about state"
fact — is available and plausible. It is deliberately **not** promoted to a diagnostic: it was
invented after seeing the answer, which is exactly how the two refuted mechanisms were
produced. It would need pre-registering against an unexamined spec to earn any credit.

## Scope and limits

- **n = 5 models**, of which four are one artefact, one author, one protocol family. Only
  `TwoPhase` is genuinely external. A single out-of-sample point refuted the diagnostic; it
  cannot establish a replacement.
- **One target was burned before use.** `Voting.tla` was disqualified as a prediction target
  because a `grep` printed its one-line `Inv` in full before any prediction was made. Recorded
  in `PREDICTION.md` rather than dropped.
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

What would move this forward: more out-of-sample points, each pre-registered. The procedure
now exists and works — freeze the claim, write the prediction, commit and tag it, then look.
It cost one afternoon and it converted a confident-sounding mechanism into a scored miss,
which is the only reason anything in this note can be trusted. The mechanism that would
actually predict conjunct count remains unknown, and this note no longer claims otherwise.

## Provenance

Certificates and CTI sequence: [`FLOORD-CTI.md`](FLOORD-CTI.md), `spec/EscrowBudget.tla`,
`spec/Recovery.tla`, `spec/EscrowBudgetD.tla`. Inductiveness results from Apalache 0.58.3 via
`scripts/apalache-inductive.sh` (which asserts on Apalache's init-predicate log line, not its
exit code); state counts from TLC 2.19. The falsification test and all minimisation runs were
done in a scratch tree; `EscrowBudgetDAtomic` is **not** part of the artefact and is not
shipped. Apalache adoption decision: `D166`.

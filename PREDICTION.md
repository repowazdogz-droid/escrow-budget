# Pre-registered prediction: applying the revised diagnostic to an outside spec

**Written 2026-07-24, BEFORE looking at the target's inductive invariant.** Committed and
tagged before the answer was read. Scored in the section appended afterwards.

The claim being tested is the revised one in [`METHOD-NOTE.md`](METHOD-NOTE.md): inductive-
invariant difficulty tracks **coupled state components a single action installs wholesale**,
not state-space size. Every previous data point comes from one artefact and one protocol
family, so the claim has never met a spec it was not derived from.

---

## Target

`specifications/transaction_commit/TwoPhase.tla` from
[tlaplus/Examples](https://github.com/tlaplus/Examples) — Gray & Lamport's two-phase commit.
Its inductive invariant is published separately in `TwoPhase_proof.tla` (154 lines), which is
**unopened at the time of writing**. I have read only `TwoPhase.tla` lines 1–138: constants,
variables, `TPTypeOK`, `TPInit`, and all seven actions, stopping at `TPNext`.

Chosen because (a) it is not mine, (b) it has a *published* inductive invariant rather than one
I would derive myself and thereby fit to my prediction, and (c) it is small enough to check.

### Disclosure: one target was already burned

I first surveyed `PaxosHowToWinATuringAward/Voting.tla` with a `grep` for definition names. That
printed `Inv == TypeOK /\ VotesSafe /\ OneValuePerBallot` in full, because the definition fits
on one line. **Voting's answer (2 auxiliary conjuncts) was therefore known to me before any
prediction, and Voting cannot be used to score this diagnostic.** It is recorded here rather
than silently dropped. The reading method was changed afterwards to line-range printing that
stops before the invariant.

---

## The counting rule, fixed in advance

`LagEq` showed the metric is granularity-sensitive: one equality did the work of two
inequalities, so "number of conjuncts" is not well defined until the splitting convention is.
Fixed **now**, before the answer is known:

1. Start from the certificate as published (or derived), conjoined with the property being
   certified.
2. Discard the type-correctness conjunct (`TPTypeOK` here) and the property itself. What
   remains are the **auxiliary** conjuncts.
3. Greedy-minimise: drop one auxiliary conjunct, re-check base and step, keep the drop if it
   still closes; repeat until no single further drop closes. Report the locally minimal set.
4. **COARSE count** = number of top-level conjuncts in that minimal set, flattening `/\` but
   **not** descending under `\A`, `\E`, or `=>`.
5. **FINE count** = same, after maximally distributing `\A` over `/\` (rewriting
   `\A x : (P /\ Q)` as `(\A x : P) /\ (\A x : Q)`) and flattening again.

Both are reported. COARSE is the headline; FINE bounds how much of the number is a phrasing
artefact. Predictions below are in COARSE.

Recomputed under this rule, the in-artefact reference class is unchanged: Recovery 1, Floor A 2,
Floor D 5, Floor D atomic-write variant 4.

---

## Applying the diagnostic

**Question 1 — can a single action replace several state components at once with values from
elsewhere?**

Working through all seven actions:

| action | writes | shape |
|---|---|---|
| `TMRcvPrepared(rm)` | `tmPrepared` | grows by one element |
| `TMCommit` | `tmState`, `msgs` | constant assignment + monotone growth |
| `TMAbort` | `tmState`, `msgs` | constant assignment + monotone growth |
| `RMPrepare(rm)` | `rmState`, `msgs` | one-point update + monotone growth |
| `RMChooseToAbort(rm)` | `rmState` | one-point update |
| `RMRcvCommitMsg(rm)` | `rmState` | one-point update |
| `RMRcvAbortMsg(rm)` | `rmState` | one-point update |

**Answer: no.** No action installs a saved copy over live state. There is no durable/volatile
pair, no crash, no rollback, no snapshot restore. `msgs` is monotone and never removed from.
Two actions write two variables each, but neither is a wholesale replacement — one is a
constant assignment and the other is set growth.

So the diagnostic's dominant term contributes **zero**.

**Question 2 — is there a single equation every action preserves?** No. There is no conserved
numeric quantity; this is a state-machine agreement protocol, not a budget. So there is no
conservation backbone to serve as the certificate's spine either.

**Residual cost.** What remains is coupling between `msgs` and the two state variables: the
certificate must say which messages can exist given the states, and vice versa. Four variables,
one of them a monotone history.

---

## The prediction

**COARSE count: 2–4 auxiliary conjuncts. Point estimate 3.**

**Reference class:** the four in-artefact specs (1, 2, 4, 5). The two without a
wholesale-replacing action needed 1 and 2.

**Adjustment from the outside view:** TwoPhase has four variables and a monotone message set
that must be related to two separate state variables — more cross-variable coupling than
Recovery (3 variables, one conserved sum, 1 conjunct), roughly comparable to Floor A (6
variables, 2 conjuncts). Adjust upward from 1–2 to 2–4.

**The discriminating prediction, which is what actually tests the claim:**

> **TwoPhase needs strictly fewer auxiliary conjuncts than Floor D's 5**, despite TwoPhase
> being a real distributed commit protocol and Floor D being a toy. If TwoPhase needs 5 or
> more, the diagnostic has failed on its first outside test.

This is falsifiable on the ordering alone, independent of whether the band is right.

**Dominant uncertainty:** the granularity of the published invariant. If `TwoPhase_proof.tla`
states its invariant as one large conjunct with everything inside a single `\A`, the COARSE
count could be 1 while the FINE count is 6, and the headline number would be an artefact of
Lamport's phrasing rather than a property of the protocol. This is exactly the `LagEq` problem
and it is why both counts are reported. If COARSE and FINE disagree by more than ~2×, I will
say the measurement did not discriminate rather than claim a hit.

**Second uncertainty — tractability.** `msgs` contains records of two different shapes
(`[type, rm]` and `[type]`). Apalache's type system may require a variant type or reject the
spec outright, which would block the mechanised step check. Fallback: TLC can check
inductiveness directly when the invariant is enumerable, by supplying it as `INIT` with a small
constant set. If neither works, the honest outcome is **prediction unscored**, not a fudged
score.

**What would make me wrong in an interesting way:** TwoPhase needing 5+ conjuncts would show
that ordinary cross-variable coupling — with no wholesale-replacing action anywhere — is
sufficient to make an inductive invariant expensive, which would mean the crash/recovery
mechanism I promoted is not the driver either. That would be the second refutation in two
rounds and would say the honest answer is "I cannot predict this yet".

---

## Scoring

*Appended after the pre-registration commit `4fa6271`, tagged `prediction-twophase`.*

### Result: WRONG, on both the band and the discriminating prediction

| | predicted | actual |
|---|---|---|
| COARSE conjuncts | 2–4 (point 3) | **7** |
| vs Floor D's 5 | strictly fewer | **more** |

The published `Inv` in `TwoPhase_proof.tla` has 9 auxiliary conjuncts beyond `TPTypeOK`.
Greedy-minimised under the pre-registered rule it comes to **7** (`C3` and `C4` drop out):

```tla
C1 == ~ (CommitMsg \in msgs /\ AbortMsg \in msgs)
C2 == tmState = "init" => CommitMsg \notin msgs /\ AbortMsg \notin msgs
C5 == \A rm \in tmPrepared : PrepMsg(rm) \in msgs
C6 == \A rm \in RM : PrepMsg(rm) \in msgs => rmState[rm] # "working"
C7 == \A rm \in RM : rmState[rm] = "committed" => CommitMsg \in msgs
C8 == CommitMsg \in msgs => \A rm \in RM : PrepMsg(rm) \in msgs
C9 == \A rm \in RM : rmState[rm] = "aborted" =>
         \/ AbortMsg \in msgs \/ PrepMsg(rm) \notin msgs
```

**The granularity escape hatch is closed.** COARSE = 7 and FINE = 7 under the pre-registered
rule (no surviving conjunct has a `/\` directly under a quantifier). Under a stricter rule
that also distributes `=>` over `/\`, FINE = 8. The counts agree, so the measurement
discriminates and the miss cannot be blamed on phrasing.

### Method

Checked with **TLC**, not Apalache: `msgs` mixes record shapes (`[type, rm]` and `[type]`),
which Apalache's type system rejects without a variant encoding. TLC does the inductive check
directly because the candidate is finitely enumerable — supply it as `INIT`, `TPNext` as
`NEXT`, and check the candidate plus `TCConsistent` as invariants. Three obligations per
candidate: reachable-state truth, one-step preservation, and implication of `TCConsistent`.

The same guard discipline applies in TLC form: a candidate must generate **many** initial
states (532 for the published set). If TLC reports ≤1 initial state with no violation, it
silently used `TPInit` and the check is void. One refinement was needed — TLC aborts
mid-enumeration when it finds a violation, so it never prints the "Finished computing initial
states" line; that is a legitimate failure, not a guard failure, and the two must be
distinguished or every genuine rejection looks like a broken harness.

`TPTypeOK` was restated as `TPTypeOKEnum` (`\subseteq S` → `\in SUBSET S`) so TLC can use it
as a generator. The two forms were model-checked equivalent on all reachable states.

### What this refutes

TwoPhase has **no** wholesale-replacing action — no crash, no rollback, no durable/volatile
pair, `msgs` monotone — and it needs **7** conjuncts. Floor D **has** such an action and needs
**5**. The revised diagnostic predicted the opposite ordering. It is wrong.

That is two mechanisms proposed and two refuted:

1. *"difficulty tracks a nameable conserved quantity"* — refuted by the atomic-write variant,
   which has one and still needs 4.
2. *"difficulty tracks components a single action installs wholesale"* — refuted here, by a
   spec with none that needs more than the spec with one.

### What survives

Only the negative claim, and it survives cleanly:

| spec | reachable states | minimal conjuncts |
|---|---|---|
| `Recovery` | 35 | 1 |
| `EscrowBudget` (Floor A) | 257 | 2 |
| `TwoPhase` (3 RMs) | **288** | **7** |
| `EscrowBudgetD` | 56 | 5 |

Floor A and TwoPhase have near-identical state spaces (257 vs 288) and differ 3.5× in
conjuncts. **State-space size predicts nothing.** That is now supported by an outside spec.

### The honest position

I cannot predict conjunct count from spec structure with any heuristic tried so far. The
plausible reading of TwoPhase — that its cost comes from relating a monotone message history
to two state variables, one conjunct per "what does this message imply about state" fact — is
a *post-hoc* explanation invented after seeing the answer, exactly like the two that already
failed. It is recorded as a hypothesis with no predictive credit, and it does not go into
`METHOD-NOTE.md` as a diagnostic.

A third mechanism would need to be pre-registered against a spec not yet examined before it
means anything.

### Incidental observation

Both published/derived certificates examined carried redundant conjuncts: Floor D's 9 → 5,
TwoPhase's published 9 → 7. Small n, but it suggests inductive invariants as written tend to
be non-minimal, and that comparisons using as-written counts (as the first version of
`METHOD-NOTE.md` did) will be inflated.

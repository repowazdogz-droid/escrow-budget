# Floor D — closing the inductive invariant by CTI iteration

**Outcome: CLOSED at iteration 7.** `CertD` is inductive at the fixed constants of
`EscrowBudgetD.cfg`; base, step, and `CertD => SafetyLe` are all discharged, so `SafetyLe`
holds at **unbounded depth** for that instance. Nine auxiliary conjuncts are needed
(`CertDMinimal`); the as-iterated `CertD` carries a tenth, `DurableRecvdSub`, which was
step-checked to be redundant given `dRecvdEqRecvd`.

> **History.** Iterations 1–6 were run in a previous session and stopped at a 6-iteration
> budget with the candidate still open; this document then read "STALLED, not closed". The
> predicate diagnosed from CTI-6 but left unchecked at that point — `dRecvdEqRecvd` — was
> subsequently step-checked and closed the induction. The stall record is kept below rather
> than rewritten, because the CTI sequence is the useful artefact and the stall was a real
> state of the work, not an error to erase.

Floor D (`spec/EscrowBudgetD.tla`) models crash / recovery / durable-vs-volatile state /
partition / retransmission. TLC shows `Safety` and `SafetyLe` hold on all 56 reachable states
of `EscrowBudgetD.cfg`. **Neither is inductive on its own** — that took seven rounds of
strengthening to repair. See [`METHOD-NOTE.md`](METHOD-NOTE.md) for why Floor D, with a
*smaller* state space than Floor A, was by far the harder of the two.

## Method

Every obligation runs through `scripts/apalache-inductive.sh`, which asserts on Apalache's log
line naming the init predicate rather than on its exit code. That guard is load-bearing:
Apalache exits `0` with `The outcome is: NoError` when `--init` is silently ignored, which
would report a candidate as inductive when it was never checked.

Every auxiliary predicate is **TLC-verified** as an invariant on all 56 reachable states, and
separately **verified live** by negating it in a scratch copy and confirming TLC reports it
violated. The second check is not ceremony: a predicate that is never evaluated produces the
identical "No error has been found" as one that passed. (During this run the negation helper
itself silently failed to apply its mutation on the first attempt and reported "No error" for
five predicates — an unmutated file passing a mutation test. The helper was fixed to abort
loudly when the mutation does not apply, and all five were re-screened.)

- Base obligation: `Init => Inv`, run at `--length=0`.
- Step obligation: `Inv /\ Next => Inv'`, run at `--length=1` with `Inv` supplied as INIT.

**Scope, carried over:** any certificate closed this way would be inductive at the FIXED
CONSTANTS of `EscrowBudgetD.cfg` (`Replicas = {r1, r2}`, `CAP = 2`, `Tids = {t1}`,
`Amounts = {1, 2}`, `DebitDurableBeforeSend = TRUE`, `RecvdDurable = TRUE`). Not a proof for
all N. Two of the predicates below are valid *only* under those boolean constants, as noted.

**Stop conditions** (from the brief): closed, OR 6 iterations without closing, OR an auxiliary
predicate that cannot be justified as a reachable-state invariant. The first pass terminated on
the second condition; the follow-up pass terminated on the first.

Apalache 0.58.3 · TLA+ Tools 1.7.4 (TLC 2.19) · candidates in `spec/apalache/EscrowBudgetDInd.tla`.

---

## Summary of the sequence

| # | candidate | base | step | CTI shows |
|---|---|---|---|---|
| 1 | `TypeOK /\ SafetyLe` | ok | fail | tid credited at a replica it was never sent to |
| 2 | + `RecvdOnlyAddressed` | ok | fail | two in-flight messages sharing one tid |
| 3 | + `TidUnique` | ok | fail | durable snapshot itself over budget |
| 4 | + `DurableSafetyLe` | ok | fail | `dSpent[r] > spent[r]` |
| 5 | + 5 durable-lag predicates | ok | fail | `Persist` double-counts across two lagging replicas |
| 6 | + `LagOrder` | ok | fail | `dEscrow` holds a credit that `dRecvd` does not record |
| 7 | + `dRecvdEqRecvd` = **`CertD`** | ok | **ok** | — **closed** |

Every base obligation discharged; every failure through iteration 6 was the step obligation.
Runtimes were 1.0–1.9 s throughout — the cost here is *diagnosis*, not compute.

---

## Iteration 1 — `IndD1 == TypeOK /\ SafetyLe`

```
  OK    IndD1   base   discharged   (1.5s)
  FAIL  IndD1   step   outcome=Error        (1.8s)
```

### CTI-1 (verbatim)

```tla
State0 ==
    /\ amtOf = SetAsFun({<<"ModelValue_t1", 1>>})
    /\ dEscrow = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 0>> })
    /\ dRecvd = SetAsFun({ <<"ModelValue_r1", {}>>, <<"ModelValue_r2", {}>> })
    /\ dSpent = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 0>> })
    /\ escrow = SetAsFun({ <<"ModelValue_r1", 1>>, <<"ModelValue_r2", 1>> })
    /\ recvd = SetAsFun({ <<"ModelValue_r1", {"ModelValue_t1"}>>, <<"ModelValue_r2", {}>> })
    /\ sentMsgs = {[tid |-> "ModelValue_t1", to |-> "ModelValue_r2"]}
    /\ spent = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 0>> })
(* State1 [_transition(2)] *)   \* Recv([to |-> r2, tid |-> t1])
    ... escrow = SetAsFun({ <<"ModelValue_r1", 1>>, <<"ModelValue_r2", 2>> })
    /\ recvd = SetAsFun({ <<"ModelValue_r1", {"ModelValue_t1"}>>,
                          <<"ModelValue_r2", {"ModelValue_t1"}>> })
InvariantViolation ==  SumSpent + SumEscrow + InFlight  > 2
```

### Why unreachable

`t1 \in recvd[r1]`, but the only message in `sentMsgs` is addressed to `r2`. `InFlight` sums
`amtOf` over `SentTids \ CreditedTids`, and `CreditedTids` unions `recvd[r]` over **all**
replicas — so r1's spurious record cancels the in-flight amount for a message not yet
delivered anywhere. `Recv` at the true destination then credits `escrow[r2] += 1` while
`InFlight` is already 0 and cannot fall further. Total goes 2 → 3.

### Predicate added

```tla
RecvdOnlyAddressed == \A r \in Replicas : \A t \in recvd[r] : [to |-> r, tid |-> t] \in sentMsgs
```

**Reachability.** `Init` sets every `recvd[r] = {}`. `Recv(m)` is the only action growing
`recvd`, and grows exactly `recvd[m.to]` by `m.tid` for `m \in sentMsgs` — addressed-correct by
construction. `Crash(r)` replaces `recvd[r]` with `dRecvd[r]` or `{}`. `Persist`, `Charge`,
`SendXfer` leave `recvd` alone, and `sentMsgs` only grows, so no existing pair is invalidated.

---

## Iteration 2 — `+ RecvdOnlyAddressed`

```
  OK    IndD2   base   discharged   (1.7s)
  FAIL  IndD2   step   outcome=Error        (1.9s)
```

### CTI-2 (verbatim, key lines)

```tla
    /\ recvd = SetAsFun({ <<"ModelValue_r1", {}>>, <<"ModelValue_r2", {"ModelValue_t1"}>> })
    /\ sentMsgs
      = { [tid |-> "ModelValue_t1", to |-> "ModelValue_r1"],
        [tid |-> "ModelValue_t1", to |-> "ModelValue_r2"] }
    /\ escrow = SetAsFun({ <<"ModelValue_r1", 1>>, <<"ModelValue_r2", 1>> })
```

### Why unreachable

Two distinct messages carry the same tid `t1`. `SendXfer` is guarded by `t \notin SentTids`, so
a tid is emitted at most once and there can be at most one message per tid. With the duplicate
present, the second copy is deliverable to r1 after r2 already credited it, crediting the same
amount twice while `InFlight` records it once.

### Predicate added

```tla
TidUnique == \A m1, m2 \in sentMsgs : (m1.tid = m2.tid) => (m1 = m2)
```

**Reachability.** `Init` has `sentMsgs = {}`. `SendXfer(i,j,t,a)` requires `t \notin SentTids`,
so the emitted message's tid differs from every tid already present. No other action writes
`sentMsgs`, and it never shrinks.

---

## Iteration 3 — `+ TidUnique`

```
  OK    IndD3   base   discharged   (1.2s)
  FAIL  IndD3   step   outcome=Error        (1.4s)
```

### CTI-3 (verbatim, key lines)

```tla
    /\ dSpent = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 3>> })
    /\ spent = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 0>> })
    /\ escrow = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 2>> })
    /\ sentMsgs = {}
(* State1 [_transition(4)] *)   \* Crash(r2)
```

### Why unreachable

`dSpent[r2] = 3` exceeds `CAP = 2` on its own. The **durable** snapshot is unconstrained by
`SafetyLe`, which bounds only the current state. `Crash(r2)` restores `spent[r2] := dSpent[r2]`
and `SumSpent` jumps to 3. Reachable durable states are snapshots of past reachable states and
so obey the same budget.

### Predicate added

```tla
dCreditedTids   == UNION {dRecvd[r] : r \in Replicas}
dInFlight       == SumFn(amtOf, SentTids \ dCreditedTids)
DurableSafetyLe == SumFn(dSpent, Replicas) + SumFn(dEscrow, Replicas) + dInFlight =< CAP
```

**Reachability.** The durable-side analogue of `SafetyLe`. `Persist(r)` copies current values,
which satisfy `SafetyLe`; `Recv` and `SendXfer` write `dEscrow` to the value `escrow` is
simultaneously taking; `Crash` does not write durable state at all. TLC confirms it on all 56
reachable states.

---

## Iteration 4 — `+ DurableSafetyLe`

```
  OK    IndD4   base   discharged   (1.2s)
  FAIL  IndD4   step   outcome=Error        (1.3s)
```

### CTI-4 (verbatim, key lines)

```tla
    /\ amtOf = SetAsFun({<<"ModelValue_t1", 0>>})
    /\ dEscrow = SetAsFun({ <<"ModelValue_r1", 1>>, <<"ModelValue_r2", 0>> })
    /\ dSpent = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 1>> })
    /\ escrow = SetAsFun({ <<"ModelValue_r1", 1>>, <<"ModelValue_r2", 1>> })
    /\ spent = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 0>> })
    /\ sentMsgs = {}
(* State1 [_transition(1)] *)   \* SendXfer(r2, r1, t1, 1)
```

### Why unreachable

`dSpent[r2] = 1` while `spent[r2] = 0` — durable spend exceeding current spend. `dSpent` is
written only by `Persist(r)`, which sets it *equal* to `spent[r]`; `Charge` only raises `spent`;
`Crash` sets `spent := dSpent`. So the durable figure can lag but never lead.

### Predicates added (TLC-screened pool)

```tla
DurableSpentLe  == \A r \in Replicas : dSpent[r] =< spent[r]
DurableEscrowGe == \A r \in Replicas : dEscrow[r] >= escrow[r]
DurableRecvdSub == \A r \in Replicas : dRecvd[r] \subseteq recvd[r]
dRecvdAddressed == \A r \in Replicas : \A t \in dRecvd[r] : [to |-> r, tid |-> t] \in sentMsgs
AmtOfSentOnly   == \A t \in Tids : (t \notin SentTids) => amtOf[t] = 0
```

**Reachability arguments.**
- `DurableSpentLe` — as above: `Persist` equalises, `Charge` raises `spent`, `Crash` equalises.
- `DurableEscrowGe` — `Charge` lowers `escrow` without touching `dEscrow`; `SendXfer` (under
  `DebitDurableBeforeSend = TRUE`) and `Recv` both set `dEscrow[r]` to the new `escrow[r]`;
  `Persist` and `Crash` equalise. **Depends on `DebitDurableBeforeSend = TRUE`.**
- `DurableRecvdSub` — `Recv` adds the tid to both; `Persist` copies forward; `Crash` copies
  back. **Depends on `RecvdDurable = TRUE`.**
- `dRecvdAddressed` — same argument as `RecvdOnlyAddressed`, on the durable set.
- `AmtOfSentOnly` — `amtOf[t]` is written only by `SendXfer`, in the same step that puts `t`
  into `SentTids`; `Init` sets all amounts to 0.

Deviation from one-CTI-per-iteration, stated plainly: the whole pool was conjoined at once
because one-at-a-time would have exhausted the 6-iteration budget. Each member is individually
justified above and individually TLC-screened.

---

## Iteration 5 — `+ the five durable-lag predicates`

```
  OK    IndD5   base   discharged   (1.2s)
  FAIL  IndD5   step   outcome=Error        (1.4s)
```

### CTI-5 (verbatim, key lines)

```tla
    /\ dEscrow = SetAsFun({ <<"ModelValue_r1", 2>>, <<"ModelValue_r2", 0>> })
    /\ dSpent = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 0>> })
    /\ escrow = SetAsFun({ <<"ModelValue_r1", 1>>, <<"ModelValue_r2", 0>> })
    /\ spent = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 1>> })
    /\ sentMsgs = {}
(* State1 [_transition(3)] *)   \* Persist(r2)
```

### Why unreachable

Both the current sum (1 + 1 + 0) and the durable sum (0 + 2 + 0) equal CAP, and every
predicate so far holds. The state is nonetheless unreachable because **two replicas lag in
opposite directions**: r1 has charged 1 without persisting (`dEscrow[r1] = 2 > escrow[r1] = 1`)
while r2 has spent 1 without persisting (`spent[r2] = 1 > dSpent[r2] = 0`). `Persist(r2)` then
folds r2's spend into the durable total while r1's durable escrow still counts the budget r1
already consumed — the same unit counted twice. Durable total goes 2 → 3.

In reachable states the escrow lag can never exceed the spend lag: `Charge` grows both by the
same amount, and every other action zeroes the escrow lag or both.

### Predicate added

```tla
\* L(r) == (escrow[r]+spent[r]) - (dEscrow[r]+dSpent[r]) >= 0, written without subtraction.
LagOrder == \A r \in Replicas : dEscrow[r] + dSpent[r] =< escrow[r] + spent[r]
```

**Reachability.** `Init` gives `L(r) = 0`. `Charge` moves `a` from `escrow` to `spent`, leaving
the current sum unchanged and the durable side untouched, so `L` is unchanged. `SendXfer(i,…,a)`
and `Recv` both set `dEscrow` to the new `escrow`, leaving `L(r) = spent[r] - dSpent[r] >= 0` by
`DurableSpentLe`. `Persist` and `Crash` set `L(r) = 0`.

---

## Iteration 6 — `+ LagOrder` (last permitted)

```
  OK    IndD6   base   discharged   (1.1s)
  FAIL  IndD6   step   outcome=Error        (1.4s)
```

### CTI-6 (verbatim, key lines)

```tla
    /\ amtOf = SetAsFun({<<"ModelValue_t1", 1>>})
    /\ dEscrow = SetAsFun({ <<"ModelValue_r1", 1>>, <<"ModelValue_r2", 0>> })
    /\ dRecvd = SetAsFun({ <<"ModelValue_r1", {}>>, <<"ModelValue_r2", {}>> })
    /\ dSpent = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 0>> })
    /\ escrow = SetAsFun({ <<"ModelValue_r1", 0>>, <<"ModelValue_r2", 0>> })
    /\ recvd = SetAsFun({ <<"ModelValue_r1", {"ModelValue_t1"}>>, <<"ModelValue_r2", {}>> })
    /\ sentMsgs = {[tid |-> "ModelValue_t1", to |-> "ModelValue_r1"]}
    /\ spent = SetAsFun({ <<"ModelValue_r1", 1>>, <<"ModelValue_r2", 1>> })
(* State1 [_transition(3)] *)   \* Persist(r2)
```

### Why unreachable

`dEscrow[r1] = 1` records that r1's credit for `t1` was made durable, but `dRecvd[r1] = {}`
says the same transfer is still durably in flight. The one unit is counted twice on the durable
side — once as escrow, once in `dInFlight`. `Persist(r2)` adds r2's spend on top and the
durable total goes 2 → 3.

Under `RecvdDurable = TRUE`, `Recv` writes `dEscrow[m.to]` and `dRecvd[m.to]` **in the same
step**, so that divergence cannot arise.

### Predicate added

```tla
dRecvdEqRecvd == \A r \in Replicas : dRecvd[r] = recvd[r]   \* requires RecvdDurable = TRUE
```

**Reachability.** Strictly stronger than `DurableRecvdSub`. `Init` sets both to `{}`. Under
`RecvdDurable = TRUE`, `Recv(m)` adds `m.tid` to `recvd[m.to]` **and** `dRecvd[m.to]` in the
same step. `Persist(r)` copies `recvd[r]` into `dRecvd[r]`; `Crash(r)` copies `dRecvd[r]` back
into `recvd[r]`. `Charge` and `SendXfer` touch neither. So the two sets move together and are
equal in every reachable state.

---

## Iteration 7 — `+ dRecvdEqRecvd` → **CLOSED**

```
  OK    EscrowBudgetDInd CertD   base   discharged   (1.1s)
  OK    EscrowBudgetDInd CertD   step   discharged   (1.5s)
```

Guard evidence, from Apalache's own `detailed.log` rather than the runner's summary — this is
the line that distinguishes a real step obligation from the silent-`--init` trap:

```
[main] INFO a.f.a.t.p.p.ConfigurationPassImpl -   > Set the initialization predicate to CertD
[main] INFO a.f.a.t.p.p.ConfigurationPassImpl -   > Set the transition predicate to Next
[main] INFO a.f.a.t.b.p.BoundedCheckerPassImpl - The outcome is: NoError
```

### The certificate

```tla
CertD == TypeOK /\ SafetyLe
      /\ RecvdOnlyAddressed /\ dRecvdAddressed /\ TidUnique /\ AmtOfSentOnly
      /\ DurableSafetyLe
      /\ DurableSpentLe /\ DurableEscrowGe /\ DurableRecvdSub /\ LagOrder
      /\ dRecvdEqRecvd
```

Grouped by what each conjunct does:

| group | conjuncts | excludes |
|---|---|---|
| well-formedness | `RecvdOnlyAddressed`, `dRecvdAddressed`, `TidUnique`, `AmtOfSentOnly` | malformed message/credit records |
| durable budget | `DurableSafetyLe` | durable snapshot over budget |
| durable lag | `DurableSpentLe`, `DurableEscrowGe`, `LagOrder` | current/durable divergence beyond what Charge can create |
| durable dedup | `DurableRecvdSub`, `dRecvdEqRecvd` | a credit recorded in `dEscrow` but not in `dRecvd` |

`DurableRecvdSub` is implied by `dRecvdEqRecvd`. That is not asserted — `CertDMinimal`, which
drops it, was separately step-checked and **also discharges** (base 1.3s, step 1.4s). So the
certificate needs **nine** auxiliary conjuncts; `CertD` retains the tenth only as the record of
iteration 5. `make apalache-inductive` certifies both.

### Obligations discharged

| obligation | command | result |
|---|---|---|
| base | `Init => CertD`, `--length=0` | discharged (1.1s) |
| step | `CertD /\ Next => CertD'`, `--length=1` | discharged (1.5s) |
| implication | `CertD => SafetyLe`, `--length=0` | discharged |

Together these give `SafetyLe` (hence `Safety`) at **unbounded depth** for this configuration.

### Verification that the result is not vacuous

- **TLC:** `CertD` holds on all 56 reachable states of `EscrowBudgetD.cfg`.
- **Liveness of the check:** negating `CertD` makes TLC report it violated, so it is genuinely
  evaluated rather than silently ignored.
- **Negative controls:** `CertD`'s step obligation **fails** under `EscrowBudgetD_LazyDebit`
  (`DebitDurableBeforeSend = FALSE`) and under `EscrowBudgetD_VolatileRecvd`
  (`RecvdDurable = FALSE`) — as it must, since `SafetyLe` genuinely fails in both. Both run in
  `make apalache-inductive`.

### Scope

Certified at the FIXED CONSTANTS of `EscrowBudgetD.cfg`: `Replicas = {r1, r2}`, `CAP = 2`,
`Tids = {t1}`, `Amounts = {1, 2}`, `DebitDurableBeforeSend = TRUE`, `RecvdDurable = TRUE`.
Unbounded in **depth**, fixed in **size**. **Not a proof for all N**, and not transferable to
the fault configurations — `DurableEscrowGe` depends on `DebitDurableBeforeSend = TRUE`, and
`DurableRecvdSub` / `dRecvdEqRecvd` on `RecvdDurable = TRUE`.

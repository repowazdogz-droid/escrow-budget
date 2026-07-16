# MODEL-CORRESPONDENCE.md

Three tools model the same protocol at different rigour and scale. **No machine-checked refinement
connects them.** Their agreement is established only at bounded scale (a state-count differential
for one small configuration). Read this as "these are three views of one design," not "these are
proved equivalent."

## Layers and what each establishes

| Tool | Artefacts | Establishes | Grade |
|---|---|---|---|
| **Lean 4** | `lean/Escrow/*.lean` | Safety for the **abstract** protocol, **all** finite N, all amounts, all CAP | unbounded machine proof |
| **TLA+ / TLC** | `spec/*.tla`, `spec/*.cfg` | Safety + the assumption-necessity matrix on **small bounded** instances | bounded exhaustive |
| **Python / Hypothesis** | `impl/*.py` | An executable model passes deterministic + property + fault-injection tests | executable testing |
| **Differential** | `impl/spec_model.py` | Independent Python BFS reproduces TLC's **66** reachable states for `EscrowBudgetC` | bounded agreement only |

## Field / action correspondence (crash/recovery, Floor D ↔ F2 ↔ Python)

| Concept | Lean F2 (`Durable*.lean`) | TLA+ `EscrowBudgetD` | Python `impl/durable.py` |
|---|---|---|---|
| current escrow / spent | `cur.escrow` / `cur.spent` | `escrow` / `spent` | `DurableReplica.escrow/spent` |
| durable escrow / spent | `dur.escrow` / `dur.spent` | `dEscrow` / `dSpent` | `d_escrow` / `d_spent` |
| transfer status (cur) | `cur.phase` (unsent/inflight/received) | `sentT`, `recvd` | `recvd`, `sentMsgs` |
| transfer status (dur) | `dur.phase` | `dRecvd`, `sentMsgs` | `d_recvd`, `sentMsgs` |
| in-flight amount | `InFlight = Σ amt over inflight` | `InFlight` (`sentT \ recvd`) | `inflight()` |
| write-ahead debit | durable escrow debit in `send` | `DebitDurableBeforeSend = TRUE` | `debit_for_send` persists `d_escrow` |
| durable receiver dedup | durable phase→received in `recv` | `RecvdDurable = TRUE` | `credit` persists `d_recvd` |
| persist / global crash | `persist` (`dur:=cur`) / `crash` (`cur:=dur`) | `Persist` / `Crash` | `persist()` / `crash()` |
| message loss | `drop` (no-op; right stays) | `Drop` (tid stays in `sentT\recvd`) | `drop()` |
| safety quantity | `A cur ≤ CAP ⇒ Σ cur.spent ≤ CAP` | `SafetyLe` / `Safety` | `safety_le()` / `total_spent` |

## Deliberate abstractions in the Lean model (not refinements)

- **Global crash** (`cur := dur` for the whole state) — models simultaneous all-replica crash.
  Per-replica-independent crash is **only** in TLA+ (Floor D) and Python (Floor E).
- **Full persist** (`dur := cur`) — selective/partial persistence is abstracted away.
- **Replayability via `phase`** — a dropped message keeps its right (`drop` = no-op), mirroring the
  TLA+ model keeping the right in `sentT \ recvd`; duplicate delivery / retransmission after
  recovery is refused by `recv`'s `phase = inflight` guard.
- **Lockstep durable deltas** — `send`/`recv` apply the same delta to `dur` as to `cur`, which is
  equivalent-for-safety to Floor D's snap-to-current write-ahead.

Because these are abstractions rather than refinements, the honest statement is: **the Lean proof
covers the disciplined protocol under these modelling choices**, and TLA+/Python provide bounded
evidence that the richer (per-replica, partial-persist) behaviours are also safe.
